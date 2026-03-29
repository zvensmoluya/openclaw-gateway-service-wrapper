# Upgrade and Uninstall

## V2 Upgrade Flow

1. Pull the latest repository version or unpack a new release zip.
2. Review the wrapper config you actually use:
   - `service-config.json`, or
   - the explicit file you installed with, such as `service-config.local.json`
3. Re-run the install command:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-v2.ps1
```

If you installed with an explicit config, use the same path again:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-v2.ps1 -WrapperConfigPath .\service-config.local.json
```

The V2 install now waits for the new host to report `Running` with healthy status before considering the upgrade complete, and it performs legacy Service cleanup after the V2 path is healthy.

To clean up historical Service leftovers separately:

```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup-v2-legacy.ps1
```

## Uninstall V2

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-v2.ps1
```

To remove V2 data directories too:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall-v2.ps1 -Purge
```

## What Gets Preserved

- Repository scripts and docs
- Your wrapper config files such as `service-config.json` or `service-config.local.json`
- The upstream OpenClaw config under `%USERPROFILE%\.openclaw\openclaw.json`

## What Gets Removed with `-Purge`

- The installed V2 layout under `%LOCALAPPDATA%\OpenClaw\app\current\`
- V2 state and logs under `%LOCALAPPDATA%\OpenClaw\`

## Historical Service Removal

If an old `OpenClawService` install still exists, remove it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup-v2-legacy.ps1
```

That cleanup removes the old Windows Service install, WinSW artifacts under `tools/winsw/<serviceName>/`, remembered Service config metadata, old scheduled tasks, and old tray Startup shortcuts.
