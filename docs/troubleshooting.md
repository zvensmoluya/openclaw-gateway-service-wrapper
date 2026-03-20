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

## `doctor.ps1` Reports Missing `openclaw`

- Ensure the OpenClaw CLI is installed on the machine.
- If it is not on `PATH`, set `openclawCommand` explicitly in the wrapper config.

## The Service Starts but Health Fails

- Check `logs/` for WinSW-side output.
- Check the OpenClaw config referenced by `configPath`.
- Verify the selected `stateDir` and `tempDir` are writable by the service account.

## Port Already in Use

- Run `doctor.ps1` to inspect current listeners.
- Stop the conflicting process or pick another port.
- Keep `allowForceBind` disabled unless you intentionally want OpenClaw to force-take the port.

## Stop or Restart Takes Too Long

- Inspect `.runtime/<serviceName>.state.json` to confirm a wrapper PID was recorded.
- Re-run `stop.ps1`; the stop path targets the exact recorded process tree.
- If a legacy install is still active, reinstall with the current wrapper layout.

## Credential Install Problems

- Make sure the supplied account already exists on the machine.
- Confirm the account can log on as a service.
- Check that resolved paths under that profile are valid.
