# Troubleshooting

## `status.ps1` or `doctor.ps1` Reports a Remembered Config Path Error

- Check the reported `configSource`, `sourcePath`, and `rememberedPath`.
- If the remembered `sourcePath` no longer exists, rerun the command with an explicit config:

```powershell
powershell -ExecutionPolicy Bypass -File .\doctor.ps1 -ConfigPath .\service-config.local.json
```

- Reinstall successfully to refresh `.runtime/active-config.json`.

## `doctor.ps1` Reports Missing or Invalid OpenClaw Config

- The wrapper config's `configPath` must point to a real OpenClaw `openclaw.json`.
- If `doctor.ps1` reports `Gateway config file does not exist`, create or restore that file.
- If it reports `Gateway config file is not valid JSON`, fix the JSON syntax before retrying.
- This wrapper validates file existence and JSON syntax only. Upstream OpenClaw still owns the schema itself.

## `status.ps1` or `doctor.ps1` Reports `LocalSystem` or `legacyRoot`

- `LocalSystem`, `LocalService`, and `NetworkService` are built-in Windows service accounts. They are not interchangeable with your interactive user profile.
- `legacyRoot` means the installed service still points at the old root-level `OpenClawService.exe` / `.xml` layout, which may lack an explicit `<serviceaccount>` block.
- Reinstall the service while signed in as the intended Windows user and provide that same user's credential. Do not use `git safe.directory` or similar Git workarounds to mask the symptom.
- If you used `serviceAccountMode: currentUser`, treat it as a compatibility alias only. The service still needs the current Windows user's real credential and still runs as a Windows Service.

## `doctor.ps1` Reports Missing `openclaw`

- Ensure the OpenClaw CLI is installed on the machine.
- If it is not on `PATH`, set `openclawCommand` explicitly in the wrapper config.

## The Service Starts but Health Fails

- Check `logs/` for WinSW-side output.
- Check the OpenClaw config referenced by `configPath`.
- Verify the selected `stateDir` and `tempDir` are writable by the service account.

## `status.ps1` or `doctor.ps1` Reports a Missing or Mismatched Restart Task

- The wrapper expects an on-demand Scheduled Task at `\OpenClaw\<serviceName>-Restart`.
- Run `schtasks /Query /TN "\OpenClaw\<serviceName>-Restart"` to confirm the task exists.
- If the task is missing or points at a stale script path, reinstall the service so the wrapper can recreate the bridge.
- Check `logs/<serviceName>.restart-task.log` for the last intentional restart attempt.

## `web_search`, `web_fetch`, or Skill Install Fails Behind a Proxy

- Set wrapper-level proxy fields in `service-config.json` or your explicit wrapper config:
  - `httpProxy`
  - `httpsProxy`
  - `allProxy`
  - `noProxy`
- Reinstall or restart the service after changing wrapper proxy config so the service process gets the updated environment.
- Run `status.ps1` or `doctor.ps1` and check the redacted `proxy.*` report entries.
- Remember that `channels.telegram.proxy` is module-specific upstream OpenClaw config. Telegram working does not prove that wrapper-wide service networking already has proxy env configured.

## Port Already in Use

- Run `doctor.ps1` to inspect current listeners.
- Stop the conflicting process or pick another port.
- Keep `allowForceBind` disabled unless you intentionally want OpenClaw to force-take the port.

## Stop or Restart Takes Too Long

- Inspect `.runtime/<serviceName>.state.json` to confirm a wrapper PID was recorded.
- Re-run `stop.ps1`; the stop path targets the exact recorded process tree.
- If a legacy install is still active, reinstall with the current wrapper layout.

## Credential Install Problems

- Make sure you are signed in as the Windows user that should own the service.
- If you pass `-Credential`, keep the username on that same current Windows user.
- Confirm that user can log on as a service.
- Check that resolved paths under that profile are valid.
