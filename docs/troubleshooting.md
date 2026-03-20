# Troubleshooting

## `doctor.ps1` Reports Missing `openclaw`

- Ensure the OpenClaw CLI is installed on the machine.
- If it is not on `PATH`, set `openclawCommand` explicitly in `service-config.json`.

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
- Re-run `stop.ps1`; the new stop path targets the exact recorded process tree.
- If a legacy install is still active, reinstall with the new wrapper layout.

## Credential Install Problems

- Make sure the supplied account already exists on the machine.
- Confirm the account can log on as a service.
- Check that resolved paths under that profile are valid.
