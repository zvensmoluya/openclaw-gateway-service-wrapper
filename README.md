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

This repository does not ship an `openclaw.json` example because that schema belongs to upstream OpenClaw.

After a successful install, the wrapper remembers the wrapper config path in `.runtime/active-config.json`. Later `start.ps1`, `stop.ps1`, `restart.ps1`, `status.ps1`, `doctor.ps1`, and `uninstall.ps1` commands reuse that remembered path unless you pass `-ConfigPath` explicitly.

## Example Wrapper Configs

- `service-config.local.example.json`: local-user install with an explicit CLI path
- `service-config.credential.example.json`: service-account install with machine-level paths
- `service-config.custom-port.example.json`: alternate service name and port

## Service Account Support

- Default mode is `currentUser`.
- In `currentUser` mode, `install.ps1` prompts for the current user's password so WinSW can install the service under that account.
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
- `status.ps1` and `doctor.ps1` report `configSource`, `sourcePath`, and `rememberedPath` so operators can see which wrapper config is actually active.
