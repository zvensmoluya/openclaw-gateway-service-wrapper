# Architecture

## Summary

This repository wraps the OpenClaw gateway in a Windows service package. The upstream OpenClaw code stays external. The wrapper owns service lifecycle, process control, configuration resolution, diagnostics, and release packaging.

## Component Boundaries

- `service-config.json`: user-editable configuration source
- `src/OpenClawGatewayServiceWrapper.psm1`: shared logic for config loading, WinSW artifact handling, diagnostics, and process-tree shutdown
- `templates/winsw-service.xml.template`: WinSW definition template
- `install.ps1`, `start.ps1`, `stop.ps1`, `restart.ps1`, `status.ps1`, `doctor.ps1`, `uninstall.ps1`: public operator commands
- `run-gateway.ps1`: service host entrypoint invoked by WinSW
- `stop-gateway.ps1`: targeted stop helper invoked by WinSW during service shutdown

## Startup and Shutdown Lifecycle

1. `install.ps1` loads config and resolves paths for the selected service identity.
2. It downloads a pinned WinSW binary, validates SHA256, renders a service XML file, and installs the Windows service.
3. WinSW starts `powershell.exe`, which runs `run-gateway.ps1`.
4. `run-gateway.ps1` writes runtime state, exports the OpenClaw environment variables, and runs `openclaw gateway run`.
5. During stop or restart, WinSW calls `stop-gateway.ps1`.
6. `stop-gateway.ps1` reads the recorded wrapper PID and stops only that exact process tree, first without force and then with a bounded forced fallback.

## Configuration Model and Precedence

- The repository default is `service-config.json` at the repo root.
- Operators can pass `-ConfigPath` to public scripts to target another config file.
- Config file values override repository defaults from the shared module.
- Path-like config values support `%USERPROFILE%`, `%HOME%`, `%LOCALAPPDATA%`, `%TEMP%`, `%TMP%`, and `%REPO_ROOT%`.
- Runtime environment variables are derived from the resolved config and current service identity.

## Dependency Download and Validation

- WinSW is not committed to the repository.
- `install.ps1` downloads the pinned WinSW release asset defined in `service-config.json`.
- The SHA256 from `winswChecksum` must match before the binary is copied into `tools/winsw/<serviceName>/`.

## Service Identity and Path Resolution

- Default mode is `currentUser`.
- In `currentUser` mode, `install.ps1` prompts for the current user's credential so WinSW can install the service under that account.
- Install-time credentials switch the effective mode to `credential`.
- Identity-aware paths such as `stateDir`, `configPath`, and `tempDir` are resolved against the selected account before install.
- At runtime, `run-gateway.ps1` uses the current process identity, which matches the configured service account after installation.

## Failure Recovery

- WinSW is configured with restart-on-failure actions.
- The wrapper removes the previous port-scan kill behavior and replaces it with exact process-tree shutdown.
- `allowForceBind` is disabled by default; if enabled, `run-gateway.ps1` appends `--force` to `openclaw gateway run`.

## Release Build Flow

1. `build-release.ps1` stages repository sources, docs, templates, and tests.
2. It generates `release-metadata.json`.
3. It writes `SHA256SUMS.txt`.
4. It packages a release zip into `dist/`.
