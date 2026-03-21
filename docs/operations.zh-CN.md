# 运维说明

## 安装

使用仓库默认配置安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

由于默认的 `serviceAccountMode` 现在是 `credential`，安装时会提示输入真正要运行服务的 Windows 账户。

使用显式 wrapper 配置安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

跳过当前用户的托盘启动项注册：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipTray
```

带凭据安装：

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

如果你刻意使用已弃用的 `currentUser` 别名，`install.ps1` 会提示输入当前 Windows 用户的密码，并把服务安装到同一个账户下。

安装成功后，wrapper 会把实际使用的 wrapper 配置路径记到 `.runtime/active-config.json`。

默认情况下，安装还会在当前 Windows 用户的 Startup 文件夹里创建 `tray-controller.ps1` 的启动快捷方式。Windows Service 和托盘控制器是两层不同的东西：前者是机器级后台服务，后者是登录会话里的控制入口。

如果目标机器上的服务流量必须走代理，请在安装或重装前先在 wrapper 配置里设置 `httpProxy`、`httpsProxy`、`allProxy` 和/或 `noProxy`。wrapper 会在运行期把这些值导出给 OpenClaw 子进程。

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

## 托盘控制器

安装它的用户登录后，`tray-controller.ps1` 会以无黑窗的方式出现在 Windows 通知区域。

托盘菜单提供：

- `Start`
- `Stop`
- `Restart`
- `Refresh`
- `Exit Tray`

行为说明：

- `Stop` 只会停止服务，不会把服务启动类型切到 `Disabled`。
- `Exit Tray` 只会关闭当前登录会话里的托盘控制器，不会停止服务。
- 托盘动作会先请求 UAC 提权，然后通过 `invoke-tray-action.ps1` 再调用现有的 `start.ps1`、`stop.ps1`、`restart.ps1`。

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
- `identity.configuredMode`：配置里的服务身份模式
- `identity.expectedStartName`：wrapper 期望的 Windows 服务账户
- `identity.actualStartName`：服务当前实际使用的 Windows 账户
- `identity.installLayout`：`generated` 或 `legacyRoot`
- `proxy.httpProxy` / `proxy.httpsProxy` / `proxy.allProxy` / `proxy.noProxy`：wrapper 侧的脱敏代理输入，以及每个值来自 wrapper 配置还是 ambient environment

`doctor.ps1` 还会检查 `configPath` 指向的 OpenClaw 配置文件是否存在，以及 JSON 语法是否有效。

## 运行期产物

- `tools/winsw/<serviceName>/`：生成出的 WinSW 可执行文件和 XML
- `.runtime/active-config.json`：remembered wrapper 配置元数据
- `.runtime/<serviceName>.state.json`：运行状态记录
- `logs/`：WinSW 日志

## 运维说明

- 目标机器上需要已经可用的 `openclaw` CLI
- wrapper 代理字段属于服务级环境注入，和上游 OpenClaw 里的 `channels.telegram.proxy` 这类模块级配置不是一回事
- 健康检查默认访问 `http://127.0.0.1:<port>/health`
- 默认停机逻辑只会结束记录下来的服务进程树，不会扫端口误杀其他进程
- 如果 remembered config 指向的文件已经失效，运维脚本会直接失败，直到你显式传入 `-ConfigPath` 或重新成功安装
- 如果 `status.ps1` 或 `doctor.ps1` 报告 `LocalSystem` 或 `legacyRoot`，应当重新按显式凭据重装，而不是用 Git 的安全目录设置去掩盖问题
