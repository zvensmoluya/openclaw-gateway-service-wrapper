# 运维说明

## 安装

使用仓库默认配置安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

由于默认的 `serviceAccountMode` 现在是 `credential`，而 wrapper 也已经收紧成单用户模型，所以安装时会提示输入当前登录 Windows 用户自己的密码。

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

如果你刻意使用已弃用的 `currentUser` 别名，`install.ps1` 仍然会提示输入当前 Windows 用户的密码，并把服务安装到同一个账户下。

`serviceAccountMode: localSystem` 已不再支持。正确做法是直接用目标 Windows 用户本人来安装服务，而不是把内建服务账户和这个用户的 profile 路径混在一起。

安装成功后，wrapper 会把实际使用的 wrapper 配置路径记到 `.runtime/active-config.json`。

默认情况下，安装还会在当前 Windows 用户的 Startup 文件夹里创建 `tray-controller.ps1` 的启动快捷方式。Windows Service 和托盘控制器是两层不同的东西：前者是机器级后台服务，后者是登录会话里的控制入口。

安装成功后，wrapper 还会注册一个按需触发的计划任务 `\OpenClaw\<serviceName>-Restart`。当 OpenClaw 触发“有意的整进程 Windows 重启”时，wrapper 会通过这个任务把重启动作重新桥接回 WinSW 管理的服务生命周期。

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

- wrapper 配置可设置 `tray.title`、`tray.notifications`、`tray.refresh.*` 和可选的 `tray.icons.*` 覆盖项。
- 健康且非 stale 的托盘空闲时不再周期性跑 fast 刷新，只按配置的深刷间隔做 deep 刷新；fast 刷新主要留给 degraded / stale 状态和菜单展开后的即时更新。
- 内置默认托盘图标位于 `assets/tray/`。
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
- 如果 `status.ps1` 或 `doctor.ps1` 报告 `LocalSystem` 或 `legacyRoot`，应当在目标 Windows 用户登录的情况下重新安装，而不是用 Git 的安全目录设置去掩盖问题
