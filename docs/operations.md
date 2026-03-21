# Operations Guide

## Install

Install with the repository default config:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

By default, installation prompts for the Windows account that should own the service because `serviceAccountMode` now defaults to `credential`.

Install with an explicit wrapper config:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

Install with credentials:

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

If you intentionally use the deprecated `currentUser` alias, `install.ps1` prompts for the current Windows user's password and installs the service under that same account.

If you use `serviceAccountMode: localSystem`, do not pass `-Credential`. That combination is rejected before installation so the wrapper cannot accidentally install the service under the explicit credential instead of `LocalSystem`.

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
- `identity.configuredMode`: `credential` or `currentUser`
- `identity.expectedStartName`: the Windows account the wrapper expects
- `identity.actualStartName`: the Windows account the service is actually using
- `identity.installLayout`: `generated` or `legacyRoot`

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
- If `status.ps1` or `doctor.ps1` reports `LocalSystem` or `legacyRoot`, reinstall with explicit credentials rather than masking the issue with Git safety overrides.
