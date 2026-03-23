# Upgrade and Uninstall

## Upgrade Flow

1. Pull the latest repository version or unpack a new release zip.
2. Review the wrapper config you actually use:
   - `service-config.json`, or
   - the explicit file you installed with, such as `service-config.local.json`
3. Re-run the install command:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

If you installed with an explicit config, use the same path again:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigPath .\service-config.local.json
```

If you need to replace an unhealthy previous install, use `-Force`.

If `status.ps1` or `doctor.ps1` reports that the service is still running as `LocalSystem` or still using the `legacyRoot` layout, rerun install while signed in as the intended Windows user so WinSW rewrites the service account correctly.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

After a successful install, `uninstall.ps1` can usually omit `-ConfigPath` because the wrapper remembers the last successful config path in `.runtime/active-config.json`.

To remove generated WinSW artifacts too:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeTools
```

## What Gets Preserved

- Repository scripts and docs
- Your wrapper config files such as `service-config.json` or `service-config.local.json`
- OpenClaw state under `stateDir`

## What Gets Removed with `-PurgeTools`

- Generated WinSW executable and XML under `tools/winsw/<serviceName>/`
- Runtime state and remembered config metadata under `.runtime/`
