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

## Service Account Model

- `credential`: the recommended and default mode. The service is installed under an explicit Windows account.
- `currentUser`: a deprecated compatibility alias. It means "install under the current Windows user's account after prompting for that user's password."
- Windows Service identity is always the service logon account. This wrapper does not support a mode that automatically follows the current interactive user session.

## Core Fields

- `serviceName`: Windows service name and WinSW artifact base name
- `displayName`: Windows service display name
- `description`: service description text
- `bind`: value passed to `openclaw gateway run --bind`
- `port`: gateway listening port
- `stateDir`: OpenClaw state directory
- `configPath`: OpenClaw config file path passed to the OpenClaw CLI
- `tempDir`: temp directory exported to the service process
- `serviceAccountMode`: `credential` or `currentUser` (deprecated compatibility alias)
- `openclawCommand`: optional explicit path or command name for the OpenClaw CLI
- `allowForceBind`: controls whether `--force` is appended

## Proxy Fields

- `httpProxy`: optional proxy URL exported as `HTTP_PROXY` / `http_proxy`
- `httpsProxy`: optional proxy URL exported as `HTTPS_PROXY` / `https_proxy`
- `allProxy`: optional proxy URL exported as `ALL_PROXY` / `all_proxy`
- `noProxy`: optional bypass list exported as `NO_PROXY` / `no_proxy`

Proxy semantics:

- If a proxy field is omitted, the wrapper leaves the current process environment unchanged for that variable.
- If a proxy field is a non-empty string, the wrapper exports that value into the OpenClaw service process before launching `openclaw`.
- If a proxy field is present as an empty string, the wrapper clears that proxy variable from the OpenClaw service process.

These proxy fields belong to the wrapper config, not upstream `openclaw.json`. They are intended to cover service-wide outbound networking such as `web_search`, `web_fetch`, and helper CLIs started by OpenClaw. Module-specific settings such as `channels.telegram.proxy` remain upstream OpenClaw settings and are separate from wrapper proxy injection.

## Tray Fields

- `tray.title`: optional tray display name; defaults to `displayName`
- `tray.notifications`: `all`, `errorsOnly`, or `off`
- `tray.refresh.fastSeconds`: background fast-refresh cadence when the tray is degraded or stale
- `tray.refresh.deepSeconds`: full refresh cadence
- `tray.refresh.menuSeconds`: max age before opening the menu requests a refresh
- `tray.icons.default`: optional default `.ico` path for the tray icon
- `tray.icons.healthy` / `degraded` / `unhealthy` / `stopped` / `error` / `loading` / `notInstalled`: optional state-specific `.ico` paths

Tray rules:

- `tray` is intentionally lightweight. Menu items and their order stay fixed.
- Icon paths may be absolute or relative to the wrapper repository root.
- Icon lookup order is `tray.icons.<state>` -> `tray.icons.default` -> bundled `assets/tray/*.ico` -> Windows system icon fallback.
- `tray.refresh.fastSeconds` must be between `15` and `300`.
- `tray.refresh.deepSeconds` must be between `60` and `900`.
- `tray.refresh.menuSeconds` must be between `5` and `60`.

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
- Service account mode: `credential`
- Force bind: `false`

`credential` means the installer resolves identity-aware paths against the selected Windows service account and prompts for credentials during installation when needed.

`currentUser` is a deprecated compatibility alias. It still prompts for the current Windows user's password and installs the service under that same user account, but it should not be interpreted as a separate runtime model.

## Example Wrapper Configs

These example files are overlays, not full manifests. They rely on repository defaults for fields that are not repeated.

- `service-config.local.example.json`
- `service-config.credential.example.json`
- `service-config.proxy.example.json`
- `service-config.custom-port.example.json`

## Proxy Overlay Example

```json
{
  "httpProxy": "http://127.0.0.1:7897",
  "httpsProxy": "http://127.0.0.1:7897",
  "noProxy": "localhost,127.0.0.1,::1"
}
```

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
  "tray": {
    "title": "OpenClaw Service",
    "notifications": "all",
    "refresh": {
      "fastSeconds": 30,
      "deepSeconds": 180,
      "menuSeconds": 10
    }
  },
  "serviceAccountMode": "credential",
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
