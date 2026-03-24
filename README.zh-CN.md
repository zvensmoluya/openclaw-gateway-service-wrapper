# openclaw-gateway-service-wrapper

`openclaw-gateway-service-wrapper` 是给 OpenClaw gateway 使用的 Windows 服务包装器，不是上游 OpenClaw 项目本体。

这个仓库只负责包装层：

- 下载并校验 WinSW，按配置生成服务定义
- 提供安装、启动、停止、重启、状态、卸载和诊断脚本
- 提供发布打包、文档和测试
- 默认兼容当前行为：服务名 `OpenClawService`，端口 `18789`

英文文档见 [README.md](./README.md)。

## 快速开始

1. 选择一份 wrapper 配置：
   - 直接修改 `service-config.json`
   - 或复制 `service-config.local.example.json` 为 `service-config.local.json`，安装时传 `-ConfigPath .\service-config.local.json`
2. 确认 wrapper 配置里的 `configPath` 指向你真实使用的 OpenClaw `openclaw.json`
3. 安装服务：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

使用显式配置文件安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

仓库默认使用 `serviceAccountMode: credential`，并且现在只支持“当前登录用户”这一种 Windows Service 模型。请在目标 Windows 用户登录后安装，并在提示时输入这个同一用户的密码。这个工具仍然是 Windows Service 包装器，不是“跟随任意当前登录用户环境”的后台代理。

默认情况下，`install.ps1` 还会为当前 Windows 用户注册一个登录后自动出现的 `tray-controller.ps1` 启动项。服务本身仍然作为后台 Windows Service 开机启动，而托盘控制器只会在该用户登录桌面后出现。如果你只想保留服务、不需要托盘入口，可以在安装时传 `-SkipTray`。

4. 检查状态和健康：

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

5. 不再需要时卸载：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## 两层配置

- Wrapper 配置：`service-config.json` 或显式传入的 `-ConfigPath`。它控制服务名、端口、路径、WinSW 设置，以及要传给 OpenClaw 的配置文件路径。
- OpenClaw 配置：`configPath` 指向的文件，默认是 `%USERPROFILE%\.openclaw\openclaw.json`。这份文件由上游 OpenClaw CLI 自己消费。
- Windows Service 子进程的标准代理环境：可在 wrapper 配置里通过 `httpProxy`、`httpsProxy`、`allProxy`、`noProxy` 显式设置。

本仓库不提供 `openclaw.json` 示例，因为它的 schema 属于上游 OpenClaw。

安装成功后，wrapper 会把实际使用的 wrapper 配置路径写入 `.runtime/active-config.json`。之后的 `start.ps1`、`stop.ps1`、`restart.ps1`、`status.ps1`、`doctor.ps1`、`uninstall.ps1` 默认都会沿用这份 remembered config，除非你显式传入 `-ConfigPath`。

## 托盘控制器

- `tray-controller.ps1` 是会话级 companion，不是对 Windows Service 的替代。
- 服务可以在开机后、用户登录前就已经运行；托盘图标会在安装它的那个用户登录后出现。
- 托盘菜单提供 `Start`、`Stop`、`Restart`、`Refresh`、`Exit Tray`。
- wrapper 配置现在支持轻量 `tray` 对象，可设置托盘标题、通知策略、刷新频率和可选图标路径。
- 仓库内置默认托盘图标位于 `assets/tray/`，图标查找顺序为 `tray.icons.<state>`、`tray.icons.default`、内置资产、最后才回退到 Windows 系统图标。
- `Stop` 只会停止服务，不会把服务启动类型改成禁用。
- `Exit Tray` 只会关闭当前登录会话里的托盘图标，不会停止服务。
- 托盘里的服务控制动作会先请求 UAC 提权，再通过 `invoke-tray-action.ps1` 调用现有生命周期脚本。

## Wrapper 配置示例

- `service-config.local.example.json`：本地快速安装示例，使用当前 Windows 用户自己的状态目录
- `service-config.credential.example.json`：显式路径安装示例，仍然安装到当前 Windows 用户
- `service-config.proxy.example.json`：服务环境需要走代理时可直接复用的 overlay 示例
- `service-config.custom-port.example.json`：自定义服务名和端口示例

## 服务账号

- 默认模式是 `credential`
- `credential` 是支持的 Windows Service 模式。它会把服务安装到当前登录并执行 `install.ps1` 的那个 Windows 用户名下。
- `currentUser` 仍然可用，但只是一个已弃用的兼容别名；它最终也会收敛到同一个“当前登录用户”模型。
- `localSystem` 不再受支持，因为它很容易把服务身份、用户 profile 和托盘行为弄乱。
- 如果安装时显式传入凭据，用户名必须和当前登录的 Windows 用户一致：

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

## 仓库结构

- `src/`：共享 PowerShell 模块
- `templates/`：WinSW XML 模板
- `docs/`：架构、配置、运维、升级与卸载、故障排查文档
- `tests/`：Pester 测试
- `.github/workflows/`：CI 与发布流程

## 文档入口

当前稳定方案：

- [架构文档](./docs/architecture.zh-CN.md)
- [配置参考](./docs/configuration.zh-CN.md)
- [运维说明](./docs/operations.zh-CN.md)
- [升级与卸载](./docs/upgrade-and-uninstall.zh-CN.md)
- [故障排查](./docs/troubleshooting.zh-CN.md)

下一阶段设计：

- [V2 需求与边界基线](./docs/v2-requirements.zh-CN.md)
- [ADR：V2 默认宿主转向当前用户级后台 Agent](./docs/adr-v2-user-agent.zh-CN.md)
- [V2 架构蓝图](./docs/v2-architecture.zh-CN.md)
- [V2 迁移计划](./docs/v2-migration.zh-CN.md)

## 开发

- 运行测试：

```powershell
Invoke-Pester -Path .\tests
```

- 生成发布包：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-release.ps1 -Version 0.1.0
```

## 说明

- 这个仓库不包含 OpenClaw 上游源码
- WinSW 二进制不会直接提交进仓库，而是在安装时下载并做 SHA256 校验
- 停机逻辑默认使用“精确结束记录下来的服务进程树”，不再按端口扫描后强杀
- `status.ps1` 和 `doctor.ps1` 会显示 `configSource`、`sourcePath`、`rememberedPath`、服务身份信息，以及脱敏后的代理摘要，方便确认当前到底读的是哪份 wrapper 配置、服务又是以哪个 Windows 账户和哪组 wrapper 代理输入运行
- `run-gateway.ps1` 现在直接使用服务真实账户自己的 Windows 用户环境，不再在启动时改写 `USERPROFILE`、`APPDATA`、`TEMP` 之类的变量
- `channels.telegram.proxy` 仍然属于上游 OpenClaw 的模块级配置；wrapper 里的代理字段是服务级环境注入，两者相互独立
