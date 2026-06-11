# 本地补丁

这个目录用于保存主仓库需要一并携带的本地补丁，主要面向 vendored 代码或
submodule 内的修改。

## ObjectReact

补丁文件：

- `object_react-pytorch26-load.patch`

用途：

- 为 ObjectReact 的 checkpoint 加载流程补上 PyTorch 2.6+ 下
  `torch.load()` 的兼容性处理

在项目根目录执行应用补丁：

```bash
git -C libs/control/object_react apply "$PWD/patches/object_react-pytorch26-load.patch"
```

检查补丁是否可以干净应用：

```bash
git -C libs/control/object_react apply --check "$PWD/patches/object_react-pytorch26-load.patch"
```

撤销补丁：

```bash
git -C libs/control/object_react apply -R "$PWD/patches/object_react-pytorch26-load.patch"
```
