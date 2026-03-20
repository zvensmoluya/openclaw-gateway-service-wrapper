# Configuration Reference

## Configuration Layers

- Wrapper config: `service-config.json` or an explicit file passed with `-ConfigPath`
- OpenClaw config: the file referenced by the wrapper config's `configPath` field

The wrapper config is owned by this repository. The OpenClaw config file is owned by upstream OpenClaw. This repository does not ship an `openclaw.json` example because the upstream schema may change independently.

## Wrapper Config Resolution Rules

When a public script is invoked, the wrapper chooses the config source in this order:

1. Explicit `-ConfigPath`
2. Remembered config from `.runtime/active-config.json`
3. Repository default `service-config.json`

After a successful install, the wrapper writes `.runtime/active-config.json` with:

- `sourceConfigPath`
- `serviceName`
- `writtenAt`

If remembered config metadata exists but the remembered `sourceConfigPath` no longer exists, `install.ps1`, `start.ps1`, `stop.ps1`, `restart.ps1`, and `uninstall.ps1` fail instead of silently falling back to the repository default. `status.ps1` and `doctor.ps1` report the broken remembered path and exit with failure.

## Recommended Local Workflow

- Keep `service-config.json` as the repository-friendly default
- Copy `service-config.local.example.json` to `service-config.local.json`
- Install with:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

After that first successful install, later operational scripts can omit `-ConfigPath` and still follow the remembered config path.

## Core Fields

- `serviceName`: Windows service name and WinSW artifact base name
- `displayName`: Windows service display name
- `description`: service description text
- `bind`: value passed to `openclaw gateway run --bind`
- `port`: gateway listening port
- `stateDir`: OpenClaw state directory
- `configPath`: OpenClaw config file path passed to the OpenClaw CLI
- `tempDir`: temp directory exported to the service process
- `serviceAccountMode`: `currentUser` or `credential`
- `openclawCommand`: optional explicit path or command name for the OpenClaw CLI
- `allowForceBind`: controls whether `--force` is appended

## WinSW Fields

- `winswVersion`: pinned WinSW release version
- `winswDownloadUrl`: official asset URL
- `winswChecksum`: SHA256 for the release asset
- `logPolicy.mode`: WinSW log mode

## Defaults

- Service name: `OpenClawService`
- Port: `18789`
- State dir: `%USERPROFILE%\.openclaw`
- Config path: `%USERPROFILE%\.openclaw\openclaw.json`
- Temp dir: `%LOCALAPPDATA%\Temp`
- Service account mode: `currentUser`
- Force bind: `false`

`currentUser` means the installer resolves paths against the invoking user profile and prompts for that user's password during installation.

## Example Wrapper Configs

These example files are overlays, not full manifests. They rely on repository defaults for fields that are not repeated.

- `service-config.local.example.json`
- `service-config.credential.example.json`
- `service-config.custom-port.example.json`

## Path Tokens

- `%USERPROFILE%`
- `%HOME%`
- `%LOCALAPPDATA%`
- `%TEMP%`
- `%TMP%`
- `%REPO_ROOT%`

## Full Example

```json
{
  "serviceName": "OpenClawService",
  "displayName": "OpenClaw Service",
  "description": "Runs the OpenClaw gateway as a Windows Service.",
  "bind": "loopback",
  "port": 18789,
  "stateDir": "%USERPROFILE%\\.openclaw",
  "configPath": "%USERPROFILE%\\.openclaw\\openclaw.json",
  "tempDir": "%LOCALAPPDATA%\\Temp",
  "serviceAccountMode": "currentUser",
  "openclawCommand": "",
  "allowForceBind": false,
  "winswVersion": "2.12.0",
  "winswDownloadUrl": "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe",
  "winswChecksum": "05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA",
  "logPolicy": {
    "mode": "rotate"
  }
}
```
