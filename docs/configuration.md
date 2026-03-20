# Configuration Reference

## Core Fields

- `serviceName`: Windows service name and WinSW artifact base name
- `displayName`: Windows service display name
- `description`: service description text
- `bind`: value passed to `openclaw gateway run --bind`
- `port`: gateway listening port
- `stateDir`: OpenClaw state directory
- `configPath`: OpenClaw config file path
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

## Path Tokens

- `%USERPROFILE%`
- `%HOME%`
- `%LOCALAPPDATA%`
- `%TEMP%`
- `%TMP%`
- `%REPO_ROOT%`

## Example

```json
{
  "serviceName": "OpenClawService",
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
