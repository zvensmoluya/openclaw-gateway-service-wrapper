# Operations Guide

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Install with credentials:

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

When `serviceAccountMode` stays at `currentUser`, `install.ps1` prompts for the current user's password automatically.

## Start and Stop

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1
powershell -ExecutionPolicy Bypass -File .\stop.ps1
powershell -ExecutionPolicy Bypass -File .\restart.ps1
```

## Status and Diagnostics

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

JSON output is available with `-Json` on `status.ps1` and `doctor.ps1`.

## Files Created at Runtime

- `tools/winsw/<serviceName>/`: generated WinSW executable and XML
- `.runtime/<serviceName>.state.json`: runtime state
- `logs/`: WinSW log files

## Operational Notes

- The wrapper expects a working `openclaw` CLI on the target machine.
- Health checks use `http://127.0.0.1:<port>/health`.
- Default stop behavior targets the recorded service process tree only.
