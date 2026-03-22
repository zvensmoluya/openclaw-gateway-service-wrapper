# openclaw-gateway-service-wrapper

`openclaw-gateway-service-wrapper` is a Windows service wrapper for the OpenClaw gateway. It is not the upstream OpenClaw project.

This repository focuses on the packaging layer only:

- WinSW download, checksum validation, and service definition rendering
- PowerShell lifecycle scripts for install, start, stop, restart, status, uninstall, and diagnostics
- Release packaging, documentation, and tests
- Compatibility with the current defaults: `OpenClawService` on port `18789`

Chinese documentation is available in [README.zh-CN.md](./README.zh-CN.md).

## Quick Start

1. Choose a wrapper config:
   - Edit `service-config.json` in place, or
   - Copy `service-config.local.example.json` to `service-config.local.json` and install with `-ConfigPath .\service-config.local.json`
2. Make sure the wrapper config's `configPath` points to your real OpenClaw `openclaw.json`.
3. Install the service:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Install with an explicit wrapper config:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

The repository default now uses `serviceAccountMode: credential`, so installation prompts for the Windows account that should own the service. This wrapper is a Windows Service package, not a "follow the currently logged-in user" agent. If you cannot or do not want to use a password-backed Windows user account for the service, use `serviceAccountMode: localSystem` with explicit absolute paths to the desired OpenClaw files.

By default, `install.ps1` also registers a per-user Startup shortcut for `tray-controller.ps1`. The service still starts with Windows as a background service, while the tray controller appears only after that user signs in. Use `-SkipTray` if you want the service without the tray companion.

4. Check health:

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

5. Remove the service when needed:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## Configuration Layers

- Wrapper config: `service-config.json` or an explicit `-ConfigPath`. This controls service name, ports, paths, WinSW settings, and which OpenClaw config file should be passed through.
- OpenClaw config: the file pointed to by `configPath` (default `%USERPROFILE%\.openclaw\openclaw.json`). This is consumed by the upstream OpenClaw CLI itself.
- Standard proxy env for the Windows Service child process: optionally set in the wrapper config via `httpProxy`, `httpsProxy`, `allProxy`, and `noProxy`.

This repository does not ship an `openclaw.json` example because that schema belongs to upstream OpenClaw.

After a successful install, the wrapper remembers the wrapper config path in `.runtime/active-config.json`. Later `start.ps1`, `stop.ps1`, `restart.ps1`, `status.ps1`, `doctor.ps1`, and `uninstall.ps1` commands reuse that remembered path unless you pass `-ConfigPath` explicitly.

## Tray Controller

- `tray-controller.ps1` is a session-level companion, not a replacement for the Windows Service.
- The service can start at boot even before anyone signs in; the tray icon appears after the installing user signs in.
- The tray menu provides `Start`, `Stop`, `Restart`, `Refresh`, and `Exit Tray`.
- Wrapper config can now include a lightweight `tray` object for tray title, notification policy, refresh cadence, and optional custom icon paths.
- Bundled tray icons are shipped in `assets/tray/`, and custom icon lookup prefers `tray.icons.<state>` then `tray.icons.default` before the bundled assets.
- `Stop` only stops the service for now. It does not change the service start mode.
- `Exit Tray` closes only the tray icon for the current sign-in session. It does not stop the service.
- Service control actions from the tray use UAC elevation and then call the existing lifecycle scripts through `invoke-tray-action.ps1`.

## Example Wrapper Configs

- `service-config.local.example.json`: current-user compatibility alias for local installs; still installs a credential-backed Windows Service
- `service-config.credential.example.json`: service-account install with machine-level paths
- `service-config.local-system.example.json`: LocalSystem install example for machines where the user account does not have a service-usable password
- `service-config.proxy.example.json`: proxy overlay example for service environments that cannot reach upstream endpoints directly
- `service-config.custom-port.example.json`: alternate service name and port

## Service Account Support

- Default mode is `credential`.
- `credential` is the recommended Windows Service mode. It installs the service under an explicit Windows account and prompts for credentials when they are not supplied on the command line.
- `currentUser` is still accepted as a deprecated compatibility alias. It means "prompt for the current Windows user's credential and install the service under that account." It does not mean "run inside the current interactive user session."
- `localSystem` installs the service as the built-in `LocalSystem` account without prompting for credentials. It must not be combined with `-Credential`. When you want that service to use files from a regular user profile, set `stateDir`, `configPath`, `tempDir`, and `openclawCommand` to absolute user-owned paths.
- To install under another account, pass a credential at install time:

```powershell
$credential = Get-Credential
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Credential $credential
```

## Repository Layout

- `src/`: shared PowerShell module
- `templates/`: WinSW XML template
- `docs/`: architecture, configuration, operations, upgrade, and troubleshooting guides
- `tests/`: Pester coverage for config, config resolution, diagnostics, and template behavior
- `.github/workflows/`: CI and release automation

## Documentation

- [Architecture](./docs/architecture.md)
- [Configuration Reference](./docs/configuration.md)
- [Operations Guide](./docs/operations.md)
- [Upgrade and Uninstall](./docs/upgrade-and-uninstall.md)
- [Troubleshooting](./docs/troubleshooting.md)

## Development

- Tests:

```powershell
Invoke-Pester -Path .\tests
```

- Build a release zip:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-release.ps1 -Version 0.1.0
```

## Notes

- The repository does not vendor the upstream OpenClaw source code.
- Third-party WinSW binaries are downloaded during install and verified by SHA256.
- The current implementation prefers precise process-tree shutdown over port-based kill logic.
- `status.ps1` and `doctor.ps1` report `configSource`, `sourcePath`, `rememberedPath`, service identity details, and a redacted proxy summary so operators can see which wrapper config, Windows account, and wrapper-supplied proxy inputs are actually active.
- `channels.telegram.proxy` stays upstream OpenClaw config and remains module-specific. Wrapper proxy fields are service-wide environment inputs for OpenClaw and its child processes.
