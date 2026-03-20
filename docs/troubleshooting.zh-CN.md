# 故障排查

## `status.ps1` 或 `doctor.ps1` 提示 remembered config 出错

- 先看输出里的 `configSource`、`sourcePath`、`rememberedPath`
- 如果 remembered 的 `sourcePath` 已经不存在，可以先显式传入正确配置：

```powershell
powershell -ExecutionPolicy Bypass -File .\doctor.ps1 -ConfigPath .\service-config.local.json
```

- 重新成功安装一次，刷新 `.runtime/active-config.json`

## `doctor.ps1` 提示 OpenClaw 配置文件缺失或 JSON 非法

- Wrapper 配置里的 `configPath` 必须指向一个真实存在的 OpenClaw `openclaw.json`
- 如果提示 `Gateway config file does not exist`，请先创建或恢复这份文件
- 如果提示 `Gateway config file is not valid JSON`，请先修复 JSON 语法
- 这个 wrapper 只检查“文件存在”和“JSON 语法有效”，不负责校验上游 OpenClaw 的 schema

## `doctor.ps1` 报找不到 `openclaw`

- 确保目标机器已经安装 OpenClaw CLI
- 如果它不在 `PATH` 里，就在 wrapper 配置里显式填写 `openclawCommand`

## 服务能启动但健康检查失败

- 查看 `logs/` 中的 WinSW 输出
- 检查 `configPath` 指向的 OpenClaw 配置
- 确认服务账号对 `stateDir` 和 `tempDir` 有写权限

## 端口已被占用

- 运行 `doctor.ps1` 看当前监听者
- 停掉冲突进程，或改用其他端口
- 除非你明确想让 OpenClaw 强行抢占端口，否则保持 `allowForceBind` 为 `false`

## 停止或重启太慢

- 检查 `.runtime/<serviceName>.state.json`，确认有记录 wrapper PID
- 重新执行 `stop.ps1`；停机逻辑只针对记录下来的精确进程树
- 如果还有旧版安装残留，重新用当前 wrapper 布局安装一次

## 凭据安装问题

- 确保提供的账号已经存在
- 确认该账号具备“作为服务登录”的权限
- 检查解析到该账号 profile 下的路径是否有效
