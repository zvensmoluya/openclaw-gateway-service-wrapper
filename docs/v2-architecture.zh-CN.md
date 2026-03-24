# V2 架构蓝图

## 概览

V2 的目标不是继续扩展 Windows Service wrapper，而是建立一个**当前用户级、无窗口、单实例**的后台宿主来承接 OpenClaw。

V2 第一阶段固定采用以下架构约束：

- 技术栈：`.NET 8 + C#`
- 控制面：`CLI + Tray`
- 托盘：`WinForms`
- IPC：`Named Pipe`
- 默认更新策略：`Observe Only`
- 默认注销策略：`Stop On Sign-out`
- 必须支持当前 Windows 用户没有密码的场景

V2 第一阶段只定义并实现用户级宿主能力，不直接管理 OpenClaw 二进制版本切换，不引入浏览器壳，也不以多用户并发为目标。

## 进程关系

V2 运行时由四个主要进程角色组成：

- `OpenClaw.Agent.Host`：后台宿主，唯一生命周期所有者
- `OpenClaw.Agent.Tray`：托盘控制面
- `OpenClaw.Agent.Cli`：命令行控制面
- `openclaw`：上游被管理子进程

关系约束如下：

- `Host` 是唯一有权直接创建、停止和重启 OpenClaw 的进程
- `Tray` 和 `Cli` 都不能直接控制 OpenClaw 进程，只能通过 IPC 请求 `Host`
- `Tray` 退出不会停止 `Host`
- `Cli` 是短生命周期工具，不持有任何运行态
- `OpenClaw` 只作为 `Host` 的子进程存在

## 模块拆分

### `OpenClaw.Agent.Core`

职责：

- 加载和校验 Agent 配置
- 解析 OpenClaw 启动参数
- 维护状态模型与退出原因分类
- 健康检查
- 日志和状态文件写入
- 对 OpenClaw 进程进行监督

约束：

- 不依赖 WinForms
- 不依赖命令行入口
- 不直接承担进程消息循环或托盘展示

### `OpenClaw.Agent.Host`

职责：

- 作为无窗口后台宿主启动
- 保持单实例
- 持有 `Named Pipe` 服务端
- 调用 `Core` 管理 OpenClaw 生命周期
- 处理登录后自启、宿主退出和注销语义

约束：

- `Host` 是唯一生命周期所有者
- `Host` 不直接承担托盘 UI
- `Host` 必须能在当前用户登录后无控制台窗口启动

### `OpenClaw.Agent.Tray`

职责：

- 提供通知区图标和菜单
- 通过 IPC 读取 `Host` 状态
- 通过 IPC 触发 `start`、`stop`、`restart`
- 展示基本通知和快捷入口

约束：

- `Tray` 不拥有 OpenClaw 生命周期
- `Exit Tray` 只退出托盘，不停止 `Host`

### `OpenClaw.Agent.Cli`

职责：

- 提供 `start`、`stop`、`restart`、`status`、`doctor`
- 输出人类可读文本和 JSON
- 通过 IPC 请求或查询 `Host`

约束：

- CLI 不直接拉起或终止 OpenClaw
- 如果 `Host` 尚未运行，CLI 可以触发启动 `Host` 或报告明确错误，实施时二选一，但必须在实现设计里固定一种行为

## 生命周期所有权

V2 第一阶段的关键原则是：**控制面不拥有生命周期，Host 才拥有生命周期。**

必须满足：

- `start` 由 `Host` 执行，并记录启动来源
- `stop` 由 `Host` 执行，并记录为显式用户停止
- `restart` 必须由 `Host` 执行完整 stop/start 序列
- `Tray` 关闭或崩溃时，`Host` 和 OpenClaw 继续运行
- `Host` 自身退出时，必须明确记录 OpenClaw 的收尾结果

## 状态模型

### 主状态

V2 第一阶段固定使用以下宿主状态：

- `Stopped`
- `Starting`
- `Running`
- `Stopping`
- `Degraded`
- `Failed`

### 退出原因

第一阶段要求至少能记录这些退出原因：

- `UserStop`
- `UserRestart`
- `UnexpectedExit`
- `HostShutdown`
- `SessionSignOut`
- `HealthFailure`

这些字段的作用是观测和控制语义，不代表包装层已经完全理解上游内部意图。

## 控制语义

V2 第一阶段固定支持：

- `start`
- `stop`
- `restart`
- `status`
- `doctor`

语义要求：

- `start`：如果已经处于 `Running`，返回幂等成功或明确提示，不重复拉起第二个实例
- `stop`：必须把本次关闭记录成显式用户停止
- `restart`：不能退化成简单再执行一遍 `start`
- `status`：返回当前状态、健康、问题、警告、路径信息
- `doctor`：返回更偏诊断视角的信息，但仍不引入 Service 专属概念

## IPC 设计

V2 第一阶段固定使用 `Named Pipe`。

原因：

- 只面向本机当前用户场景
- 不需要浏览器控制面
- Windows 原生宿主场景更自然
- 不需要把控制协议暴露成 HTTP 服务

最小命令集合：

- `ping`
- `start`
- `stop`
- `restart`
- `status`
- `doctor`

最小响应内容：

- `success`
- `message`
- `state`
- `health`
- `issues`
- `warnings`
- `paths`

## 文件布局

V2 默认以当前用户目录为根，建议固定在 `%LocalAppData%\OpenClaw\`：

- `config\agent.json`
- `state\run-state.json`
- `state\host-state.json`
- `logs\agent.log`
- `logs\openclaw.stdout.log`
- `logs\openclaw.stderr.log`

要求：

- 配置、状态、日志分目录管理
- `openclaw.json` 仍视为上游配置，不并入 agent schema
- 实施时如果需要额外文件，应继续遵循“按职责分目录”的规则

## 自启模型

V2 第一阶段默认使用当前用户级自启：

- `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`

原因：

- 贴合当前用户级宿主模型
- 不依赖 Service 安装
- 不要求用户密码

约束：

- 不为了后台运行额外要求用户设置密码
- 不把系统级开机服务当作默认前提

## 注销、锁屏、睡眠

V2 第一阶段对这些场景做明确区分：

- `注销`：视为会话结束，执行 `Stop On Sign-out`
- `锁屏`：不等同于停止
- `息屏`：不等同于停止
- `睡眠`：不等同于显式停止；恢复后的具体处理由 Host 状态恢复策略决定

## Tray 行为

第一阶段托盘菜单固定包含：

- `Start`
- `Stop`
- `Restart`
- `Refresh`
- `Open Logs`
- `Exit Tray`

语义要求：

- `Exit Tray` 仅退出托盘
- `Refresh` 只刷新当前视图，不触发生命周期动作
- Tray 图标至少区分 `running / degraded / stopped / failed / starting / stopping`

## 更新边界

V2 第一阶段对 OpenClaw 更新采取 `Observe Only`：

- 包装层不负责下载、切换、回滚 OpenClaw 版本
- 包装层只负责观测、记录和在必要时配合停启
- 不假设上游会提供固定的“我要更新”信号

这意味着：

- 更新问题在架构上被预留，但不在第一阶段彻底解决
- 任何版本管理能力都要在未来另行设计，而不是偷偷塞进第一阶段

## 非目标

- 不复刻 WinSW、计划任务桥和服务身份模型
- 不以浏览器控制面为第一阶段前提
- 不要求多用户并发
- 不在第一阶段直接管理 OpenClaw 版本更新
- 不要求保留所有现有 PowerShell 脚本作为长期主路径

## 实施前提

在代码实施开始前，应先具备以下文档：

- V2 需求与边界基线
- V2 默认宿主 ADR
- V2 架构蓝图
- V2 迁移计划

如果这些文档之间有冲突，以 ADR 和本蓝图为准，并在实施前先更新文档而不是临时口头决定。
