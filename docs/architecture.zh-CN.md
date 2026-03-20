# 架构文档

## 概要

这个仓库负责把 OpenClaw gateway 包装成 Windows 服务。上游 OpenClaw 代码仍然保持外部依赖，包装层只负责服务生命周期、进程控制、配置解析、诊断和发布打包。

## 组件边界

- `service-config.json`：用户可编辑的配置入口
- `src/OpenClawGatewayServiceWrapper.psm1`：共享逻辑，负责配置、WinSW 产物、诊断和精准停机
- `templates/winsw-service.xml.template`：WinSW 服务定义模板
- `install.ps1`、`start.ps1`、`stop.ps1`、`restart.ps1`、`status.ps1`、`doctor.ps1`、`uninstall.ps1`：对外命令
- `run-gateway.ps1`：由 WinSW 调起的服务入口
- `stop-gateway.ps1`：由 WinSW 在停机时调用的精准停机脚本

## 启停生命周期

1. `install.ps1` 读取配置，并按目标服务账号解析路径。
2. 下载固定版本 WinSW，校验 SHA256，渲染 XML，安装 Windows 服务。
3. WinSW 启动 `powershell.exe`，执行 `run-gateway.ps1`。
4. `run-gateway.ps1` 记录运行状态，设置 OpenClaw 运行环境变量，然后执行 `openclaw gateway run`。
5. 停止或重启时，WinSW 调用 `stop-gateway.ps1`。
6. `stop-gateway.ps1` 读取记录下来的包装进程 PID，只停止这棵精确的进程树；先尝试非强制结束，再做有超时上限的强制兜底。

## 配置模型与优先级

- 默认使用仓库根目录的 `service-config.json`。
- 所有公开脚本都支持 `-ConfigPath` 指向其他配置文件。
- 文件中的值覆盖模块内置默认值。
- 路径类字段支持 `%USERPROFILE%`、`%HOME%`、`%LOCALAPPDATA%`、`%TEMP%`、`%TMP%`、`%REPO_ROOT%`。
- 运行时环境变量由解析后的配置和实际服务身份共同决定。

## 依赖下载与校验

- WinSW 不直接提交到仓库。
- `install.ps1` 根据 `service-config.json` 中的固定版本下载官方 WinSW 资产。
- 只有 SHA256 与 `winswChecksum` 一致时，才会把二进制放到 `tools/winsw/<serviceName>/`。

## 服务账号与路径解析

- 默认模式是 `currentUser`。
- 在 `currentUser` 模式下，`install.ps1` 会提示输入当前用户凭据，再把服务装到该账号下。
- 安装时传入凭据会切换为 `credential`。
- `stateDir`、`configPath`、`tempDir` 这类路径会先按目标账号解析，再写入服务定义。
- 真正运行时，`run-gateway.ps1` 使用当前进程身份，这与安装时配置的服务账号保持一致。

## 失败恢复

- WinSW 配置了失败自动重启。
- 新实现移除了“按端口扫描再强杀”的默认策略，改成精准进程树停机。
- `allowForceBind` 默认关闭；只有显式开启时，`run-gateway.ps1` 才会给 `openclaw gateway run` 增加 `--force`。

## 发布构建流程

1. `build-release.ps1` 把源码、文档、模板和测试整理到 staging 目录。
2. 生成 `release-metadata.json`。
3. 生成 `SHA256SUMS.txt`。
4. 在 `dist/` 下打出发布 zip。
