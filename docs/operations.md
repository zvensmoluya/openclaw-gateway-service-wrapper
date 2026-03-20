# Operations Guide

## Install

Install with the repository default config:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Install with an explicit wrapper config:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

Install with credentials:

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

When `serviceAccountMode` stays at `currentUser`, `install.ps1` prompts for the current user's password automatically.

After a successful install, the wrapper remembers the wrapper config path in `.runtime/active-config.json`.

## Start, Stop, Restart

Once a config has been remembered, later operational scripts can omit `-ConfigPath`:

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1
powershell -ExecutionPolicy Bypass -File .\stop.ps1
powershell -ExecutionPolicy Bypass -File .\restart.ps1
```

To override the remembered config for a single command, pass `-ConfigPath` explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1 -ConfigPath .\service-config.local.json
```

## Status and Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

JSON output is available with `-Json` on `status.ps1` and `doctor.ps1`.

Both commands report:

- `configSource`: `explicit`, `remembered`, or `repoDefault`
- `sourcePath`: the wrapper config currently in use
- `rememberedPath`: the remembered wrapper config path, if any

`doctor.ps1` also validates that the OpenClaw config file referenced by `configPath` exists and contains valid JSON.

## Files Created at Runtime

- `tools/winsw/<serviceName>/`: generated WinSW executable and XML
- `.runtime/active-config.json`: remembered wrapper config metadata
- `.runtime/<serviceName>.state.json`: runtime state
- `logs/`: WinSW log files

## Operational Notes

- The wrapper expects a working `openclaw` CLI on the target machine.
- Health checks use `http://127.0.0.1:<port>/health`.
- Default stop behavior targets the recorded service process tree only.
- If a remembered config path goes stale, operational scripts fail fast until you pass `-ConfigPath` explicitly or reinstall successfully.
