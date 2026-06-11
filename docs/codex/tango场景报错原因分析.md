是的，这两个错误本质上是 **Tango 当前配置的 `goal_source: topological` 专属问题**，不是这两个场景本身一定坏掉。

更精确地说：不是 “Tango 控制器” 必然有问题，而是你现在的 Tango 配置走了 [topological 目标生成链路](/home/xzy/projects/my_research/object-rel-nav/configs/tango_failed.yaml:31)。另外两个配置分别是：

- Robohop: `goal_source: gt_metric`
- ObjectReact: `goal_source: gt_topometric`

所以它们根本没有执行 Tango 这两个出错分支。

**1. `q5...` 为什么只有 Tango 报 `Could not find goalNodeIdx`**

Tango/topological 会加载：

```text
nodes_fast_sam_lightglue.pickle
```

然后在初始化时尝试从预测 topological graph 里找到真实 goal object 对应的节点。代码在 [task_setup.py](/home/xzy/projects/my_research/object-rel-nav/libs/experiments/task_setup.py:279)：

```python
if self.args.goal_source == "topological":
    goalNodeIdx = self.get_task_goalNodeIdx()
```

`get_task_goalNodeIdx()` 里会拿最终目标 mask 和 map graph 里同一张图的预测 mask 做 IoU。如果最大 IoU 是 0，就返回 `None`，然后抛错：

```python
ValueError: Could not find goalNodeIdx ...
```

也就是说：`q5...` 这个 episode 里，`nodes_fast_sam_lightglue.pickle` 没有成功覆盖/匹配到最终目标物体节点。

Robohop 的 `gt_metric` 不需要这个图节点；ObjectReact 的 `gt_topometric` 用的是 GT topometric graph 和 instance id/path length，也不做这一步 FastSAM-LightGlue 的 goal node IoU 匹配。所以它们不会报这个错。

**2. `k1...` 的 `(47,3) (8,)` 是 topological localizer 的一个代码 bug**

我刚才复跑 `k1cupFYWXJ6_0000000_sofa_19_` 拿到了完整 traceback，真正位置是：

```text
libs/localizer/loc_topo.py:105
dists = np.linalg.norm(self.mapImgPositions - qryPosition, axis=1)
```

调用链是：

```text
main.py:159
task_setup.py:689
goal_gen.py:101
loc_topo.py:179
loc_topo.py:101
loc_topo.py:203
loc_topo.py:105
```

关键 bug 在 [loc_topo.py](/home/xzy/projects/my_research/object-rel-nav/libs/localizer/loc_topo.py:101)：

```python
matchPairs = self.localize(qryImg, qryNodes, refImgInds)
```

但 `localize()` 的函数签名是：

```python
def localize(self, qryImg, qryNodes, qryPosition=None, refImgInds=None):
```

所以这里第三个位置参数 `refImgInds` 被错误传成了 `qryPosition`。`refImgInds` 长度是 8，于是后面就变成：

```python
(47, 3) - (8,)
```

然后 numpy broadcast 失败。

修法应该是把那行改成关键字参数：

```python
matchPairs = self.localize(qryImg, qryNodes, refImgInds=refImgInds)
```

**结论**

这两个错误都来自 `goal_source: topological`：

- `q5...`：预测 topological graph 里找不到 goal node。
- `k1...`：topological relocalization 分支有参数传错 bug。

另外两个方法不报错，是因为它们用 GT metric / GT topometric 目标，不走 FastSAM + LightGlue + topological goal node/localizer 这条链路。