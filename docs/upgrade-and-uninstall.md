# Upgrade and Uninstall

## Upgrade Flow

1. Pull the latest repository version or unpack a new release zip.
2. Review `service-config.json`.
3. Re-run the install command:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

If you need to replace an unhealthy previous install, use `-Force`.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

To remove generated WinSW artifacts too:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## What Gets Preserved

- Repository scripts and docs
- `service-config.json`
- OpenClaw state under `stateDir`

## What Gets Removed with `-PurgeTools`

- Generated WinSW executable and XML under `tools/winsw/<serviceName>/`
- Runtime state file under `.runtime/`
