# 升级与卸载

## 升级流程

1. 拉取最新仓库内容，或者解压新的 release 包
2. 检查你实际使用的 wrapper 配置：
   - `service-config.json`
   - 或你安装时显式传入的配置文件，例如 `service-config.local.json`
3. 重新执行安装命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

如果你原本就是用显式配置安装的，升级时也继续传同一份配置：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

如果旧安装已经不健康、需要强制替换，可以加 `-Force`。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

在成功安装过一次之后，`uninstall.ps1` 通常可以省略 `-ConfigPath`，因为 wrapper 会在 `.runtime/active-config.json` 里记住最后一次成功安装的配置路径。

如果还要删除生成的 WinSW 产物：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## 默认保留内容

- 仓库脚本和文档
- 你的 wrapper 配置文件，例如 `service-config.json` 或 `service-config.local.json`
- `stateDir` 下的 OpenClaw 状态数据

## `-PurgeTools` 额外删除内容

- `tools/winsw/<serviceName>/` 下生成的 WinSW 可执行文件和 XML
- `.runtime/` 下的运行状态和 remembered config 元数据
