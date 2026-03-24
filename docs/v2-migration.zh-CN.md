# V2 迁移计划

## 目标

V2 迁移不是一次性推翻当前方案，而是从当前稳定的 Windows Service wrapper **渐进迁移**到新的当前用户级后台 Agent。

迁移目标：

- 允许现有 Windows Service 方案继续作为短期 fallback
- 在不破坏现有可用环境的前提下引入新的用户级宿主
- 逐步把日常控制入口从 PowerShell + Service 语义迁移到 Agent + CLI + Tray 语义
- 在文档和实现都稳定后，再决定何时正式废弃旧 Service 主路径

## 迁移原则

- 先冻结设计，再实施代码
- 先引入新宿主，不直接移除旧方案
- 先迁控制能力，再迁操作习惯
- 先实现功能对等，再讨论彻底替代
- 整个迁移过程中，旧 Service 路径不得与新 V2 路径混合运行

## 短期并行策略

在过渡期内，仓库同时存在两条路径：

- 当前稳定方案：Windows Service wrapper
- 下一阶段方案：用户级后台 Agent 设计与后续实现

短期要求：

- 旧 Service 方案继续可用
- V2 文档与后续实现必须明确标识为“新路径”
- 不在同一台目标环境上默认同时启用旧 Service 和新 Agent 来管理同一个 OpenClaw 实例

## 迁移阶段

### 阶段 0：文档冻结

目标：

- 固化需求、ADR、架构蓝图和迁移计划
- 冻结 V2 第一阶段的高影响决策

完成标准：

- 实施者无需再决定默认宿主、IPC、控制面、更新边界、注销策略和无密码支持

### 阶段 1：建立最小用户级宿主

目标：

- 新增 `Host + CLI`
- 跑通 `start / stop / restart / status / doctor`
- 用当前用户级自启替代 Service 自启语义

要求：

- 仍不删除旧 Service 相关脚本
- 不直接接管 OpenClaw 更新

### 阶段 2：接入托盘控制面

目标：

- 新增 `Tray`
- 让托盘通过 IPC 与 `Host` 通信
- 实现日常桌面使用路径

要求：

- 托盘退出不影响后台宿主
- 不再依赖 UAC + Service 控制桥来完成日常操作

### 阶段 3：导入现有配置

目标：

- 从当前 wrapper 配置中导入 V2 仍然需要的字段
- 定义从旧配置到新 Agent 配置的映射

要求：

- 迁移器必须明确哪些字段继续保留，哪些字段被废弃
- 迁移器不应默默吞掉不兼容字段；应记录或提示

### 阶段 4：验证功能对等

目标：

- 确认新路径已覆盖主流日常使用场景
- 明确旧 Service fallback 还能承担的场景

要求：

- 只有在日常使用闭环稳定后，才开始讨论默认入口切换

### 阶段 5：切换默认推荐路径

目标：

- 文档默认入口切换到用户级 Agent
- 旧 Service 方案降级为兼容/回退说明

要求：

- 这一步必须在新路径稳定后进行
- 不在本阶段文档内默认承诺具体删除日期

## 配置迁移策略

### 继续保留的字段

从现有 wrapper 配置中，V2 应优先兼容以下概念：

- `configPath`
- `openclawCommand`
- `port`
- `bind`
- `httpProxy`
- `httpsProxy`
- `allProxy`
- `noProxy`
- `tray.*` 中仍与用户级控制面相关的字段

### 明确废弃的字段

V2 不再把以下概念作为主路径配置：

- `serviceName`
- `displayName`
- `serviceAccountMode`
- `winswVersion`
- `winswDownloadUrl`
- `winswChecksum`
- `failureActions`
- `resetFailure`
- `startMode`
- `delayedAutoStart`
- `restart task` 相关字段和衍生概念

### 配置导入要求

- 导入过程应以“提取仍有意义的字段”为主
- 被废弃字段应在迁移报告中明确列出
- 不要求继续兼容所有 Service 专属默认值

## 何时可以宣布 V2 取代旧方案

只有当下面条件同时满足时，才可以把 V2 视为默认推荐路径：

- 用户不再需要常驻 PowerShell 窗口运行 OpenClaw
- 当前用户无密码场景可正常运行和自启
- `start / stop / restart / status / doctor` 稳定可用
- Tray + CLI 已覆盖主要日常操作
- 旧 Service 路径不再是大多数单用户场景的必要前提
- OpenClaw 的异常退出、自退出和日常重启在新宿主中已有清晰状态与可接受表现

## 过渡期注意事项

- 旧 Service 方案仍然是正式 fallback，不应在文档里贬成“临时 hack”
- 新 V2 路径在完全稳定前，不应默认替换生产中的现有 Service 安装
- 对用户来说，迁移应该表现为“更贴近当前用户的后台宿主”，而不是“功能更多但语义更乱”

## 非目标

- 不在本迁移计划中定义具体代码类名或实现细节
- 不在本迁移计划中直接安排删除现有 PowerShell 路径
- 不在本迁移计划中承诺第一阶段解决 OpenClaw 全部更新问题
