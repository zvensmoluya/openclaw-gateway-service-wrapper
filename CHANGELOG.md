# Changelog

## Unreleased

## 0.2.0 - 2026-03-23

- Simplified the Windows Service wrapper to a single-user install model tied to the current signed-in Windows account.
- Removed `localSystem` support from wrapper configuration and validation to avoid mismatched service identity, user profile paths, and tray behavior.
- Stopped rewriting user profile environment variables in `run-gateway.ps1` so OpenClaw now runs under the service account's real Windows profile.
- Passed the explicit wrapper `ConfigPath` through tray startup registration to keep the tray controller aligned with non-default installs.
- Added a brief post-install health-check retry loop to reduce false warnings while OpenClaw is still starting.
- Updated English and Chinese documentation to reflect the current single-user service model and operational guidance.
- Expanded test coverage for tray shortcut wiring, gateway environment handling, single-user identity validation, and post-install health-check retries.

- Repository bootstrap for the open-source `openclaw-gateway-service-wrapper` project.
- Added a generated WinSW configuration pipeline, public lifecycle scripts, diagnostics, and release packaging.
- Added bilingual documentation, CI workflows, and Pester coverage.
- Fixed `install.ps1` failure handling so early expected failures do not surface as PowerShell `ErrorRecord` noise in CI.
- Fixed port listener detection so an unused port is not misreported as occupied.
- Added `serviceAccountMode: localSystem` for passwordless Windows setups, plus coverage for LocalSystem service validation paths.
- Hardened wrapper config resolution and remembered-config diagnostics so operational scripts fail closed on stale config metadata.
- Refined service identity reporting and validation, including clearer warnings around deprecated `currentUser` semantics.
- Aligned gateway runtime environment paths with the configured service identity.
- Added a tray controller companion for lightweight service management from the Windows notification area.
- Added wrapper-managed proxy environment support for Windows services, plus diagnostics for proxy source reporting.
- Added a Windows intentional-restart bridge using a wrapper-owned Scheduled Task so full-process gateway restarts can return through WinSW instead of stopping the service.
- Extended `status.ps1` and `doctor.ps1` to validate the restart bridge task and surface restart-task drift as an operator-visible issue.
- Added a tray launcher based on `wscript.exe` / `tray-controller-launcher.vbs` so the tray controller can be started without a visible PowerShell console window.
- Expanded Pester coverage for restart-task registration, restart-task diagnostics, tray startup wiring, proxy reporting, and LocalSystem install flows.
- Added lightweight wrapper-level tray customization for title, notification policy, refresh cadence, and icon paths.
- Added bundled default tray icon assets under `assets/tray/` and included them in release packaging.
- Reduced idle tray polling so healthy trays prefer scheduled deep refreshes and avoid unnecessary fast refresh churn.
- Extended tray coverage for display-name propagation, notification policy, icon fallback ordering, refresh deduping, and smoke execution defaults.
