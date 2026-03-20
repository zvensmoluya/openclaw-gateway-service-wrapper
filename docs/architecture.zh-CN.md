# 架构说明

## 概览

这个仓库把 OpenClaw gateway 包装成 Windows 服务。上游 OpenClaw 代码保持外部依赖状态。Wrapper 负责服务生命周期、进程控制、配置解析、诊断和发布打包。

## 组件边界

- `service-config.json`：用户可编辑的 wrapper 配置入口
- `src/OpenClawGatewayServiceWrapper.psm1`：共享逻辑，包括配置加载、remembered config 解析、WinSW 产物处理、诊断和进程树停止
- `templates/winsw-service.xml.template`：WinSW 定义模板
- `install.ps1`、`start.ps1`、`stop.ps1`、`restart.ps1`、`status.ps1`、`doctor.ps1`、`uninstall.ps1`：对外命令
- `run-gateway.ps1`：由 WinSW 调起的服务入口
- `stop-gateway.ps1`：由 WinSW 在停止服务时调用的精准停机辅助脚本

## 启动和停止生命周期

1. `install.ps1` 加载配置，并按选定的服务身份解析路径
2. 下载固定版本的 WinSW，校验 SHA256，渲染服务 XML，然后安装 Windows 服务
3. 安装和启动都成功后，wrapper 把实际使用的 wrapper 配置路径写入 `.runtime/active-config.json`
4. WinSW 启动 `powershell.exe`，执行 `run-gateway.ps1`
5. `run-gateway.ps1` 写入运行状态，导出 OpenClaw 环境变量，然后执行 `openclaw gateway run`
6. 停止或重启时，WinSW 调用 `stop-gateway.ps1`
7. `stop-gateway.ps1` 读取记录下来的 wrapper PID，只停止那棵精确的进程树，先尝试非强制，再做有限度的强制兜底

## 配置模型与优先级

- 仓库默认配置是根目录的 `service-config.json`
- 所有公开脚本都支持 `-ConfigPath` 指向其他 wrapper 配置
- 安装成功后，wrapper 会把最后一次成功的配置路径写入 `.runtime/active-config.json`
- 公开脚本按下面的顺序选择 wrapper 配置：显式 `-ConfigPath`、remembered config、仓库默认配置
- 如果 remembered config 指向的文件已经不存在，运维脚本会失败，不会静默回退到仓库默认配置
- 配置文件中的值会覆盖共享模块里的仓库默认值
- 路径类配置支持 `%USERPROFILE%`、`%HOME%`、`%LOCALAPPDATA%`、`%TEMP%`、`%TMP%`、`%REPO_ROOT%`
- 运行时环境变量由解析后的配置和当前服务身份推导

## 依赖下载与校验

- WinSW 二进制不会提交进仓库
- `install.ps1` 根据 wrapper 配置中固定版本的 WinSW 地址下载官方资产
- 只有当 `winswChecksum` 校验通过后，才会把二进制复制到 `tools/winsw/<serviceName>/`

## 服务身份与路径解析

- 默认模式是 `currentUser`
- 在 `currentUser` 模式下，`install.ps1` 会提示输入当前用户凭据，好让 WinSW 以该账号安装服务
- 安装时显式提供凭据会把有效模式切换为 `credential`
- 像 `stateDir`、`configPath`、`tempDir` 这样的身份相关路径，会在安装前按选定账号解析
- 运行时，`run-gateway.ps1` 使用当前进程身份；安装成功后，这个身份应当与配置的服务账号一致

## 故障恢复

- WinSW 配置了失败后自动重启动作
- Wrapper 删除了以前“按端口扫描并强杀”的停机方式，改成只结束精确记录下来的进程树
- `allowForceBind` 默认关闭；如果开启，`run-gateway.ps1` 会给 `openclaw gateway run` 追加 `--force`
- `doctor.ps1` 额外检查 `configPath` 指向的 OpenClaw 配置文件是否存在且 JSON 语法有效

## 发布构建流程

1. `build-release.ps1` 把仓库源码、文档、模板、测试和示例配置复制到 staging 目录
2. 生成 `release-metadata.json`
3. 生成 `SHA256SUMS.txt`
4. 打包 release zip 到 `dist/`
