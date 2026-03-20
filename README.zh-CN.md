# openclaw-gateway-service-wrapper

`openclaw-gateway-service-wrapper` 是一个给 OpenClaw gateway 使用的 Windows 服务包装工具，并不是上游 OpenClaw 项目本体。

这个仓库只负责包装层：

- 下载并校验 WinSW，按配置生成服务定义
- 提供安装、启动、停止、重启、状态检查、诊断脚本
- 提供发布打包、文档和测试
- 默认兼容当前行为：服务名 `OpenClawService`，端口 `18789`

英文主页见 [README.md](./README.md)。

## 快速开始

1. 按你的机器或服务账号修改 `service-config.json`。
2. 安装服务：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

3. 检查状态和健康：

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

4. 不再需要时卸载：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## 服务账号

- 默认模式是 `currentUser`。
- 在 `currentUser` 模式下，`install.ps1` 会提示输入当前用户密码，再把服务安装到该账号下运行。
- 如果要用其他账号安装服务，可以在安装时传入凭据：

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

## 仓库结构

- `src/`：共享 PowerShell 模块
- `templates/`：WinSW XML 模板
- `docs/`：架构、配置、运维、升级卸载、故障排查文档
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

- 这个仓库不包含 OpenClaw 上游源码。
- WinSW 二进制不会直接提交进仓库，而是在安装时下载并做 SHA256 校验。
- 停机逻辑默认使用“精准结束记录下来的服务进程树”，不再按端口扫描后强杀。
