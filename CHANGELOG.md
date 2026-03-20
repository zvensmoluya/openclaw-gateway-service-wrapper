# Changelog

## Unreleased

- Repository bootstrap for the open-source `openclaw-gateway-service-wrapper` project.
- Added a generated WinSW configuration pipeline, public lifecycle scripts, diagnostics, and release packaging.
- Added bilingual documentation, CI workflows, and Pester coverage.
- Fixed `install.ps1` failure handling so early expected failures do not surface as PowerShell `ErrorRecord` noise in CI.
- Fixed port listener detection so an unused port is not misreported as occupied.
- Added `serviceAccountMode: localSystem` for passwordless Windows setups, plus coverage for LocalSystem service validation paths.
