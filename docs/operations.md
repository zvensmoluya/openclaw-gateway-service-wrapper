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

Skip tray registration for the current Windows user:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -SkipTray
```

Install with credentials:

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

If you intentionally use the deprecated `currentUser` alias, `install.ps1` prompts for the current Windows user's password and installs the service under that same account.

If you use `serviceAccountMode: localSystem`, do not pass `-Credential`. That combination is rejected before installation so the wrapper cannot accidentally install the service under the explicit credential instead of `LocalSystem`.

After a successful install, the wrapper remembers the wrapper config path in `.runtime/active-config.json`.

Install also registers an on-demand Scheduled Task at `\OpenClaw\<serviceName>-Restart`. OpenClaw uses that task for intentional full-process Windows restarts, and the task bridges back into the WinSW-managed service lifecycle.

By default, install also creates a Startup shortcut for `tray-controller.ps1` in the current Windows user's Startup folder. The Windows Service and the tray controller are separate layers: the service is machine background infrastructure, while the tray icon is a per-sign-in control surface.

If the machine needs an outbound proxy for service traffic, set `httpProxy`, `httpsProxy`, `allProxy`, and/or `noProxy` in the wrapper config before installing or reinstalling the service. The wrapper exports those values to the OpenClaw child process at runtime.

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

## Tray Controller

After the installing user signs in, `tray-controller.ps1` appears in the Windows notification area without showing a console window.

The tray menu provides:

- `Start`
- `Stop`
- `Restart`
- `Refresh`
- `Exit Tray`

Behavior notes:

- Wrapper config can set `tray.title`, `tray.notifications`, `tray.refresh.*`, and optional `tray.icons.*` overrides.
- Healthy idle trays now avoid periodic fast refreshes and only schedule deep refreshes on the configured cadence. Fast refreshes are reserved for degraded or stale states, or when the tray menu is opened after the configured menu age.
- Bundled tray icons ship in `assets/tray/`.
- `Stop` only stops the service. It does not switch the service to `Disabled`.
- `Exit Tray` only closes the tray controller for the current sign-in session. It does not stop the service.
- Tray actions prompt for UAC elevation and then invoke `invoke-tray-action.ps1`, which in turn calls the existing `start.ps1`, `stop.ps1`, or `restart.ps1` scripts.

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
- `restartTask.fullTaskName`: the expected Scheduled Task bridge path
- `restartTask.matches`: whether the registered task action still matches the wrapper's expected helper script
- `proxy.httpProxy` / `proxy.httpsProxy` / `proxy.allProxy` / `proxy.noProxy`: redacted wrapper-side proxy inputs and whether each value came from wrapper config or the ambient environment

`doctor.ps1` also validates that the OpenClaw config file referenced by `configPath` exists and contains valid JSON.

## Files Created at Runtime

- `tools/winsw/<serviceName>/`: generated WinSW executable and XML
- Windows Scheduled Task `\OpenClaw\<serviceName>-Restart`: intentional restart bridge back into the service
- `.runtime/active-config.json`: remembered wrapper config metadata
- `.runtime/<serviceName>.state.json`: runtime state
- `logs/`: WinSW logs plus `<serviceName>.restart-task.log` for restart-bridge audit output

## Operational Notes

- The wrapper expects a working `openclaw` CLI on the target machine.
- Wrapper proxy fields are service-wide environment inputs. They are separate from upstream module-specific settings such as `channels.telegram.proxy`.
- Health checks use `http://127.0.0.1:<port>/health`.
- Default stop behavior targets the recorded service process tree only.
- If a remembered config path goes stale, operational scripts fail fast until you pass `-ConfigPath` explicitly or reinstall successfully.
- If `status.ps1` or `doctor.ps1` reports `LocalSystem` or `legacyRoot`, reinstall with explicit credentials rather than masking the issue with Git safety overrides.
