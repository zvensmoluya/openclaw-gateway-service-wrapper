# 配置参考

## 核心字段

- `serviceName`：Windows 服务名，同时也是 WinSW 产物的基础名
- `displayName`：服务显示名
- `description`：服务描述
- `bind`：传给 `openclaw gateway run --bind` 的值
- `port`：gateway 监听端口
- `stateDir`：OpenClaw 状态目录
- `configPath`：OpenClaw 配置文件路径
- `tempDir`：服务进程使用的临时目录
- `serviceAccountMode`：`currentUser` 或 `credential`
- `openclawCommand`：可选，显式指定 OpenClaw CLI 路径或命令名
- `allowForceBind`：控制是否追加 `--force`

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
- 服务账号模式：`currentUser`
- 是否强制抢占端口：`false`

`currentUser` 的含义是：按当前调用用户的 profile 解析路径，并在安装时提示输入这个用户的密码。

## 路径占位符

- `%USERPROFILE%`
- `%HOME%`
- `%LOCALAPPDATA%`
- `%TEMP%`
- `%TMP%`
- `%REPO_ROOT%`

## 示例

```json
{
  "serviceName": "OpenClawService",
  "bind": "loopback",
  "port": 18789,
  "stateDir": "%USERPROFILE%\\.openclaw",
  "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json",
  "tempDir": "%LOCALAPPDATA%\\Temp",
  "serviceAccountMode": "currentUser",
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
