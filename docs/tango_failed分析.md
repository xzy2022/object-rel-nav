
详细分析结果在`docs/codex/tango场景报错原因分析.md`

24 个失败的汇总：
- exceeded_steps: 22：跑满最大步数还没成功，不是 Python 报错。
- q5QZSEeHe5g_0000000_plant_32_：初始化 episode 时找不到 goalNodeIdx。
- k1cupFYWXJ6_0000000_sofa_19_：在 episode_runner.get_goal(...) 时出现 numpy shape 不匹配：(47,3) 和 (8,) 不能 broadcast。


```bash
python main.py -c configs/tango_failed.yaml
```

根据实验结果,这两个错误都只有`tango`方法会遇到.

第一类错误已经很清楚：只有 goal_source: topological 会在初始化时把真实终点物体 mask 和预测 map graph 节点做 IoU 匹配，匹配不到就直接抛 goalNodeIdx。我再追第二个 (47,3) vs (8,)，它应该发生在 Tango 的 query segmentation/matching 后处理里。

第二个 shape 报错的 main.py #159 只是外层调用点。要解释“为什么只有 Tango”，代码层面已经足够：只有 topological 分支会调用 FastSAM -> LightGlue localizer -> Goal_Gen.get_goal_mask() 这条视觉匹配链；另外两个方法直接用 GT semantic / GT graph path length 生成目标代价，不需要 query-map mask matching。