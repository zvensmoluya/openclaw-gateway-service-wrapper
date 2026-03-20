# 运维说明

## 安装

使用仓库默认配置安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

使用显式 wrapper 配置安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

带凭据安装：

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

如果 `serviceAccountMode` 保持默认的 `currentUser`，`install.ps1` 会自动提示输入当前用户密码。

安装成功后，wrapper 会把实际使用的 wrapper 配置路径记到 `.runtime/active-config.json`。

## 启动、停止、重启

一旦有 remembered config，后续常用脚本可以省略 `-ConfigPath`：

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1
powershell -ExecutionPolicy Bypass -File .\stop.ps1
powershell -ExecutionPolicy Bypass -File .\restart.ps1
```

如果只想在某一次命令里覆盖 remembered config，可以显式传参：

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1 -ConfigPath .\service-config.local.json
```

## 状态与诊断

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

`status.ps1` 和 `doctor.ps1` 都支持 `-Json`。

这两个命令都会报告：

- `configSource`：`explicit`、`remembered` 或 `repoDefault`
- `sourcePath`：当前真正生效的 wrapper 配置路径
- `rememberedPath`：当前 remembered 的 wrapper 配置路径，如果没有则为 `null`

`doctor.ps1` 还会检查 `configPath` 指向的 OpenClaw 配置文件是否存在，以及 JSON 语法是否有效。

## 运行期产物

- `tools/winsw/<serviceName>/`：生成出的 WinSW 可执行文件和 XML
- `.runtime/active-config.json`：remembered wrapper 配置元数据
- `.runtime/<serviceName>.state.json`：运行状态记录
- `logs/`：WinSW 日志

## 运维说明

- 目标机器上需要已经可用的 `openclaw` CLI
- 健康检查默认访问 `http://127.0.0.1:<port>/health`
- 默认停机逻辑只会结束记录下来的服务进程树，不会扫端口误杀其他进程
- 如果 remembered config 指向的文件已经失效，运维脚本会直接失败，直到你显式传入 `-ConfigPath` 或重新成功安装
