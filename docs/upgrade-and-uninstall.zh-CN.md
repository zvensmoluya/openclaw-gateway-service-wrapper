# 升级与卸载

## 升级流程

1. 拉取最新仓库内容，或者解压新的 release 包。
2. 检查 `service-config.json`。
3. 重新执行安装命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

如果旧安装状态异常，需要强制替换，可以加 `-Force`。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

如果还要删除生成的 WinSW 产物：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## 默认保留内容

- 仓库脚本和文档
- `service-config.json`
- `stateDir` 下的 OpenClaw 状态数据

## `-PurgeTools` 会额外删除

- `tools/winsw/<serviceName>/` 下生成的 WinSW 可执行文件和 XML
- `.runtime/` 下的运行状态文件
