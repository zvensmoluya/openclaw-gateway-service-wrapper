# 配置参考

## 配置分层

- Wrapper 配置：`service-config.json` 或显式传入的 `-ConfigPath`
- OpenClaw 配置：wrapper 配置里 `configPath` 指向的文件

Wrapper 配置由本仓库负责，OpenClaw 配置由上游 OpenClaw 负责。本仓库不提供 `openclaw.json` 示例，因为上游 schema 可能独立演进。

## Wrapper 配置解析规则

公开脚本会按下面的优先级选择 wrapper 配置：

1. 显式传入的 `-ConfigPath`
2. `.runtime/active-config.json` 里 remembered 的配置
3. 仓库根目录的 `service-config.json`

安装成功后，wrapper 会写入 `.runtime/active-config.json`，固定字段为：

- `sourceConfigPath`
- `serviceName`
- `writtenAt`

如果 remembered config 元数据存在，但 `sourceConfigPath` 指向的文件已经不存在：

- `install.ps1`、`start.ps1`、`stop.ps1`、`restart.ps1`、`uninstall.ps1` 会直接失败
- `status.ps1` 和 `doctor.ps1` 会报告 remembered path 出错，并返回失败

不会再静默回退到仓库默认配置。

## 服务身份模型

- `credential`：推荐且默认的模式。服务会安装到一个显式的 Windows 账户下。
- `currentUser`：已弃用但兼容的别名。它的含义只是“安装时提示输入当前 Windows 用户的密码，并把服务安装到这个用户账户下”。
- Windows Service 的真实运行身份永远由服务登录账户决定，不会自动跟随当前交互登录用户。

## 推荐的本地工作流

- 保留 `service-config.json` 作为仓库默认值
- 复制 `service-config.local.example.json` 为 `service-config.local.json`
- 首次安装时执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

之后常用运维脚本就可以省略 `-ConfigPath`，因为 wrapper 已经记住了这份配置。

## 核心字段

- `serviceName`：Windows 服务名，同时也是 WinSW 产物的基础名
- `displayName`：服务显示名
- `description`：服务描述
- `bind`：传给 `openclaw gateway run --bind` 的值
- `port`：gateway 监听端口
- `stateDir`：OpenClaw 状态目录
- `configPath`：传给 OpenClaw CLI 的配置文件路径
- `tempDir`：服务进程使用的临时目录
- `serviceAccountMode`：`credential` 或 `currentUser`（已弃用兼容别名）
- `openclawCommand`：可选，显式指定 OpenClaw CLI 路径或命令名
- `allowForceBind`：控制是否追加 `--force`

## 代理字段

- `httpProxy`：可选代理地址，会导出为 `HTTP_PROXY` / `http_proxy`
- `httpsProxy`：可选代理地址，会导出为 `HTTPS_PROXY` / `https_proxy`
- `allProxy`：可选代理地址，会导出为 `ALL_PROXY` / `all_proxy`
- `noProxy`：可选绕过列表，会导出为 `NO_PROXY` / `no_proxy`

代理字段语义：

- 如果某个字段缺失，wrapper 不会改动当前进程里对应的环境变量。
- 如果某个字段是非空字符串，wrapper 会在启动 `openclaw` 前把它注入到服务子进程环境。
- 如果某个字段显式写成空字符串，wrapper 会在启动 `openclaw` 前清除对应代理变量。

这些代理字段属于 wrapper 配置，不属于上游 `openclaw.json`。它们用于覆盖 Windows Service 场景下的统一出站网络，例如 `web_search`、`web_fetch` 和 OpenClaw 拉起的辅助 CLI。像 `channels.telegram.proxy` 这样的模块级配置仍然归上游 OpenClaw 自己管理。

## WinSW 相关字段

- `winswVersion`：固定的 WinSW 版本
- `winswDownloadUrl`：官方下载地址
- `winswChecksum`：下载资产的 SHA256
- `logPolicy.mode`：WinSW 日志模式

## 默认值

- 服务名：`OpenClawService`
- 端口：`18789`
- 状态目录：`%USERPROFILE%\.openclaw`
- 配置路径：`%USERPROFILE%\.openclaw\openclaw.json`
- 临时目录：`%LOCALAPPDATA%\Temp`
- 服务账号模式：`credential`
- 是否强制抢占端口：`false`

`credential` 的含义是：安装脚本按选定的 Windows 服务账户解析身份相关路径，并在需要时提示输入凭据。

`currentUser` 是已弃用兼容别名。它仍然会提示输入当前 Windows 用户的密码，并把服务安装到同一个账户下，但不代表一种独立的运行时模型。

## 示例配置文件

这些示例文件是 overlay，不是完整清单。没有重复写出的字段会继续使用仓库默认值。

- `service-config.local.example.json`
- `service-config.credential.example.json`
- `service-config.proxy.example.json`
- `service-config.custom-port.example.json`

## 代理 Overlay 示例

```json
{
  "httpProxy": "http://127.0.0.1:7897",
  "httpsProxy": "http://127.0.0.1:7897",
  "noProxy": "localhost,127.0.0.1,::1"
}
```

## 路径占位符

- `%USERPROFILE%`
- `%HOME%`
- `%LOCALAPPDATA%`
- `%TEMP%`
- `%TMP%`
- `%REPO_ROOT%`

## 完整示例

```json
{
  "serviceName": "OpenClawService",
  "displayName": "OpenClaw Service",
  "description": "Runs the OpenClaw gateway as a Windows Service.",
  "bind": "loopback",
  "port": 18789,
  "stateDir": "%USERPROFILE%\\.openclaw",
  "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json",
  "tempDir": "%LOCALAPPDATA%\\Temp",
  "serviceAccountMode": "credential",
  "openclawCommand": "",
  "allowForceBind": false,
  "winswVersion": "2.12.0",
  "winswDownloadUrl": "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe",
  "winswChecksum": "05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA",
  "logPolicy": {
    "mode": "rotate"
  }
}
```
