# openclaw-gateway-service-wrapper

`openclaw-gateway-service-wrapper` is a Windows service wrapper for the OpenClaw gateway. It is not the upstream OpenClaw project.

This repository focuses on the packaging layer only:

- WinSW download, checksum validation, and service definition rendering
- PowerShell lifecycle scripts for install, start, stop, restart, status, and diagnostics
- Release packaging, documentation, and tests
- Compatibility with the current defaults: `OpenClawService` on port `18789`

Chinese documentation is available in [README.zh-CN.md](./README.zh-CN.md).

## Quick Start

1. Edit `service-config.json` for your machine or service account.
2. Install the service:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

3. Check health:

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
powershell -ExecutionPolicy Bypass -File .\doctor.ps1
```

4. Remove the service when needed:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

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
- `tests/`: Pester coverage for config and template behavior
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
