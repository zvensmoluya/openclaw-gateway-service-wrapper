# V2 Architecture Blueprint

## Overview

V2 does not continue the Windows Service wrapper as the main growth path.  
Instead, it introduces a **user-level, windowless, single-instance** background host for OpenClaw.

V2 phase 1 fixes the following architectural defaults:

- Stack: `.NET 8 + C#`
- Control surfaces: `CLI + Tray`
- Tray technology: `WinForms`
- IPC: `Named Pipe`
- Default update strategy: `Observe Only`
- Default sign-out strategy: `Stop On Sign-out`
- Passwordless current-user support is required

Phase 1 defines and implements the user-level host only. It does not directly manage OpenClaw binary version switching, does not introduce a browser shell, and does not target concurrent multi-user runtime.

## Process Topology

V2 runtime consists of four main process roles:

- `OpenClaw.Agent.Host`: background host and sole lifecycle owner
- `OpenClaw.Agent.Tray`: tray control surface
- `OpenClaw.Agent.Cli`: command-line control surface
- `openclaw`: managed upstream child process

The relationships are fixed as follows:

- `Host` is the only process allowed to directly create, stop, and restart OpenClaw
- `Tray` and `Cli` never control OpenClaw directly; they always go through IPC
- Exiting `Tray` does not stop `Host`
- `Cli` is short-lived and holds no runtime ownership
- OpenClaw exists only as a child process supervised by `Host`

## Module Boundaries

### `OpenClaw.Agent.Core`

Responsibilities:

- Load and validate agent config
- Resolve OpenClaw launch arguments
- Maintain state model and exit-reason classification
- Perform health checks
- Write logs and state files
- Supervise the OpenClaw process

Constraints:

- No WinForms dependency
- No CLI dependency
- Does not own the message loop or tray surface

### `OpenClaw.Agent.Host`

Responsibilities:

- Start as a windowless background host
- Enforce single-instance behavior
- Expose the `Named Pipe` server
- Use `Core` to manage OpenClaw lifecycle
- Handle sign-in auto-start, host shutdown, and sign-out behavior

Constraints:

- `Host` is the sole lifecycle owner
- `Host` does not render tray UI
- `Host` must start after user sign-in without a visible console window

### `OpenClaw.Agent.Tray`

Responsibilities:

- Provide the notification-area icon and menu
- Read `Host` state through IPC
- Trigger `start`, `stop`, and `restart` through IPC
- Show basic notifications and quick actions

Constraints:

- `Tray` does not own OpenClaw lifecycle
- `Exit Tray` only exits the tray process

### `OpenClaw.Agent.Cli`

Responsibilities:

- Provide `start`, `stop`, `restart`, `status`, and `doctor`
- Output both human-readable text and JSON
- Request or query `Host` through IPC

Constraints:

- CLI never launches or kills OpenClaw directly
- If `Host` is not running yet, implementation must explicitly choose either "start Host" or "report a clear error" and document that behavior

## Lifecycle Ownership

The core phase 1 rule is: **control surfaces do not own lifecycle; Host owns lifecycle.**

Required behavior:

- `start` is executed by `Host` and records the trigger source
- `stop` is executed by `Host` and is recorded as an intentional user stop
- `restart` always runs a full stop/start sequence inside `Host`
- Tray exit or crash does not stop `Host` or OpenClaw
- If `Host` exits, it must write a clear final state for OpenClaw cleanup outcome

## State Model

### Primary Host States

Phase 1 fixes the host states to:

- `Stopped`
- `Starting`
- `Running`
- `Stopping`
- `Degraded`
- `Failed`

### Exit Reasons

Phase 1 must at least record:

- `UserStop`
- `UserRestart`
- `UnexpectedExit`
- `HostShutdown`
- `SessionSignOut`
- `HealthFailure`

These values exist for observability and control semantics. They do not imply full knowledge of upstream intent.

## Control Semantics

Phase 1 supports:

- `start`
- `stop`
- `restart`
- `status`
- `doctor`

Semantics:

- `start`: if already `Running`, return idempotent success or a clear message; do not launch a second instance
- `stop`: record the shutdown as an explicit user stop
- `restart`: must not collapse into "call start again"
- `status`: report state, health, issues, warnings, and paths
- `doctor`: report a more diagnostic view without reintroducing Service-specific concepts

## IPC Design

Phase 1 uses `Named Pipe`.

Reasons:

- The target is local current-user control only
- Browser-first control is not required
- It fits Windows-native host behavior naturally
- It avoids exposing the control protocol as local HTTP

Minimum command set:

- `ping`
- `start`
- `stop`
- `restart`
- `status`
- `doctor`

Minimum response shape:

- `success`
- `message`
- `state`
- `health`
- `issues`
- `warnings`
- `paths`

## Filesystem Layout

V2 should default to `%LocalAppData%\OpenClaw\`:

- `config\agent.json`
- `state\run-state.json`
- `state\host-state.json`
- `logs\agent.log`
- `logs\openclaw.stdout.log`
- `logs\openclaw.stderr.log`

Rules:

- Config, state, and logs are separated by responsibility
- `openclaw.json` remains an upstream config file and is not absorbed into the agent schema
- Any additional phase 1 files should continue following the same responsibility-based layout

## Auto-Start Model

Phase 1 defaults to current-user auto-start via:

- `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`

Reasons:

- Matches the user-level host model
- Does not depend on Service installation
- Does not require a password-backed account

Constraints:

- Background runtime must not require users to set a password
- Machine-level boot service should not be the default assumption

## Sign-out, Lock, And Sleep

Phase 1 makes these distinctions explicit:

- `Sign-out`: treated as session end and handled as `Stop On Sign-out`
- `Lock`: not treated as stop
- `Display sleep`: not treated as stop
- `System sleep`: not treated as explicit stop; recovery behavior is handled by host state restoration policy

## Tray Behavior

The phase 1 tray menu is fixed to:

- `Start`
- `Stop`
- `Restart`
- `Refresh`
- `Open Logs`
- `Exit Tray`

Required behavior:

- `Exit Tray` only exits the tray process
- `Refresh` updates visible state only and does not trigger lifecycle changes
- Tray icons must at least distinguish `running / degraded / stopped / failed / starting / stopping`

## Update Boundary

Phase 1 uses `Observe Only` for OpenClaw update behavior:

- The wrapper does not download, switch, or roll back OpenClaw versions
- The wrapper only observes, records, and cooperates with stop/start when needed
- The design must not assume upstream will provide a stable explicit "update requested" signal

This means:

- Update handling is reserved in the architecture but not solved fully in phase 1
- Any future version-management capability must be designed explicitly later rather than hidden inside phase 1

## Non-Goals

- Rebuilding WinSW, scheduled-task bridges, or service identity flow
- Requiring a browser-first control surface in phase 1
- Concurrent multi-user support
- Direct OpenClaw version management in phase 1
- Treating existing PowerShell scripts as the long-term primary runtime path

## Preconditions For Implementation

Before implementation starts, the following documents should exist:

- V2 requirements baseline
- V2 host ADR
- V2 architecture blueprint
- V2 migration plan

If those documents conflict, the ADR and this blueprint take precedence, and the documents should be updated before implementation rather than overridden ad hoc.
