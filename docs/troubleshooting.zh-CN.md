# 故障排查

## `doctor.ps1` 报找不到 `openclaw`

- 先确认机器上已经安装 OpenClaw CLI。
- 如果它不在 `PATH` 里，就在 `service-config.json` 里显式填写 `openclawCommand`。

## 服务能启动但健康检查失败

- 先看 `logs/` 里的 WinSW 日志。
- 检查 `configPath` 指向的 OpenClaw 配置是否正确。
- 确认服务账号对 `stateDir` 和 `tempDir` 有读写权限。

## 端口被占用

- 运行 `doctor.ps1` 看当前监听者。
- 停掉冲突进程，或者改端口。
- 除非你明确要让 OpenClaw 强制抢占端口，否则不要打开 `allowForceBind`。

## 停止或重启很慢

- 查看 `.runtime/<serviceName>.state.json`，确认包装进程 PID 是否被记录。
- 重新执行 `stop.ps1`；新实现会精准结束记录下来的进程树。
- 如果机器上仍然是旧布局安装，建议用新脚本重新安装一次。

## 凭据安装失败

- 确认传入的账号在本机真实存在。
- 确认该账号具备服务登录权限。
- 检查按该账号解析出来的目录路径是否有效。
