# openclaw-gateway-service-wrapper

`openclaw-gateway-service-wrapper` now ships two Windows hosting paths for the OpenClaw gateway:

- Default recommended path: the V2 current-user background Agent (`Host + CLI + Tray`)
- Compatibility fallback: the legacy Windows Service wrapper

It is not the upstream OpenClaw project.

This repository focuses on the packaging and host-control layer only:

- V2 user-level Agent packaging, install/uninstall, tray control, and migration from wrapper config
- WinSW download, checksum validation, and service definition rendering
- PowerShell lifecycle scripts for install, start, stop, restart, status, uninstall, and diagnostics
- Release packaging, documentation, and tests
- Compatibility with the current defaults: `OpenClawService` on port `18789`

Chinese documentation is available in [README.zh-CN.md](./README.zh-CN.md).

## Quick Start

Recommended V2 path:

1. Choose a wrapper config for migration:
   - Edit `service-config.json` in place, or
   - Copy `service-config.local.example.json` to `service-config.local.json`
2. Make sure the wrapper config's `configPath` points to your real OpenClaw `openclaw.json`.
3. Install the V2 Agent:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-v2.ps1
```

Install with an explicit wrapper config:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-v2.ps1 -WrapperConfigPath .\service-config.local.json
```

By default, `install-v2.ps1` now:

- copies the published `Host + CLI + Tray` layout under `%LOCALAPPDATA%\OpenClaw\app\current\`
- starts the V2 host and tray for the current session
- waits for `status --json` to report `Running` with `health.ok = true`
- cleans up the old Service path after the V2 install is healthy

4. Use the installed control surfaces:

```powershell
%LOCALAPPDATA%\OpenClaw\app\current\OpenClaw.Agent.Cli.exe status --json
%LOCALAPPDATA%\OpenClaw\app\current\OpenClaw.Agent.Cli.exe doctor --json
```

5. Remove the V2 Agent when needed:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-v2.ps1 -Purge
```

If you already switched to V2 and only want to remove historical Service leftovers:

```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup-v2-legacy.ps1
```

## Historical Service Path

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

The repository default uses `serviceAccountMode: credential`, and this wrapper now supports a single-user Windows Service model only. Install the wrapper while signed in as the Windows user who should own the service, then enter that same user's password when prompted.

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

- `service-config.local.example.json`: local install example that keeps state under the current Windows user
- `service-config.credential.example.json`: explicit-path install example for the current Windows user
- `service-config.proxy.example.json`: proxy overlay example for service environments that cannot reach upstream endpoints directly
- `service-config.custom-port.example.json`: alternate service name and port

## Service Account Support

- Default mode is `credential`.
- `credential` is the supported Windows Service mode. It installs the service under the same Windows account that is currently signed in and running `install.ps1`.
- `currentUser` is still accepted as a deprecated compatibility alias. It resolves to the same single-user install model as `credential`.
- `localSystem` is no longer supported because it led to mismatched runtime identity, user profile, and tray behavior.
- When you pass `-Credential`, the credential must match the currently signed-in Windows user:

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

Default recommended path:

- [V2 Requirements Baseline](./docs/v2-requirements.md)
- [ADR: V2 Default Host Moves To A User-Level Background Agent](./docs/adr-v2-user-agent.md)
- [V2 Architecture Blueprint](./docs/v2-architecture.md)
- [V2 Migration Plan](./docs/v2-migration.md)

Historical Service docs:

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
- `run-gateway.ps1` now relies on the service's real Windows user profile instead of rewriting user environment variables at launch time.
- `channels.telegram.proxy` stays upstream OpenClaw config and remains module-specific. Wrapper proxy fields are service-wide environment inputs for OpenClaw and its child processes.
