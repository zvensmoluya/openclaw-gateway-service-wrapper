# OpenClaw Agent V2

This folder contains the V2 current-user agent implementation that is now the repository's default recommended path.

Key pieces:

- `src/OpenClaw.Agent.Host`: the background host and named-pipe server
- `src/OpenClaw.Agent.Cli`: the command-line control surface
- `src/OpenClaw.Agent.Tray`: the WinForms tray control surface
- `src/OpenClaw.Agent.Core`: config, process lifecycle, health, state, and autostart
- `tests/OpenClaw.Agent.Tests`: unit and integration tests

Build locally:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-v2.ps1
```

That publishes a stable layout under `dist\v2\win-x64\current\`.

Install locally:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-v2.ps1
```

Remove the installed layout:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-v2.ps1 -Purge
```
