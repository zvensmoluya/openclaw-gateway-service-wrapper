# 运维说明

## 安装

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

带凭据安装：

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

如果 `serviceAccountMode` 保持默认的 `currentUser`，`install.ps1` 会自动提示输入当前用户密码。

## 启动与停止

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1
powershell -ExecutionPolicy Bypass -File .\stop.ps1
powershell -ExecutionPolicy Bypass -File .\restart.ps1
```

## 状态与诊断

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

`status.ps1` 和 `doctor.ps1` 都支持 `-Json`。

## 运行期产物

- `tools/winsw/<serviceName>/`：生成出的 WinSW 可执行文件和 XML
- `.runtime/<serviceName>.state.json`：运行状态记录
- `logs/`：WinSW 日志

## 运维说明

- 目标机器上需要已经可用的 `openclaw` CLI。
- 健康检查默认访问 `http://127.0.0.1:<port>/health`。
- 默认停机逻辑只会结束记录下来的服务进程树，不会扫端口误杀其他进程。
