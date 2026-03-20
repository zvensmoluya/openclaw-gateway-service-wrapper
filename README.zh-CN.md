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

仓库默认现在使用 `serviceAccountMode: credential`，所以安装时会提示输入实际要运行服务的 Windows 账户凭据。这个工具是 Windows Service 包装器，不是“跟随当前登录用户环境”的后台代理。

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

本仓库不提供 `openclaw.json` 示例，因为它的 schema 属于上游 OpenClaw。

安装成功后，wrapper 会把实际使用的 wrapper 配置路径写入 `.runtime/active-config.json`。之后的 `start.ps1`、`stop.ps1`、`restart.ps1`、`status.ps1`、`doctor.ps1`、`uninstall.ps1` 默认都会沿用这份 remembered config，除非你显式传入 `-ConfigPath`。

## Wrapper 配置示例

- `service-config.local.example.json`：本地快速安装示例，使用已弃用但兼容的 `currentUser` 别名；底层仍然会安装成一个带凭据的 Windows Service
- `service-config.credential.example.json`：推荐的服务账号安装示例
- `service-config.custom-port.example.json`：自定义服务名和端口示例

## 服务账号

- 默认模式是 `credential`
- `credential` 是推荐的 Windows Service 模式。它要求显式的 Windows 服务账户；如果你不在命令行上传 `-Credential`，安装脚本会交互式提示输入
- `currentUser` 仍然可用，但只是一个已弃用的兼容别名。它的含义是“提示输入当前 Windows 用户的密码，并把服务安装到这个用户账户下”，不是“在当前交互用户会话里运行”
- 如果要显式指定要运行服务的账号，可以在安装时传入凭据：

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

- [架构文档](./docs/architecture.zh-CN.md)
- [配置参考](./docs/configuration.zh-CN.md)
- [运维说明](./docs/operations.zh-CN.md)
- [升级与卸载](./docs/upgrade-and-uninstall.zh-CN.md)
- [故障排查](./docs/troubleshooting.zh-CN.md)

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
- `status.ps1` 和 `doctor.ps1` 会显示 `configSource`、`sourcePath`、`rememberedPath` 以及服务身份信息，方便确认当前到底读的是哪份 wrapper 配置、服务又是以哪个 Windows 账户运行
