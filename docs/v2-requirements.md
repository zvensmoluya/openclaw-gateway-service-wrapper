# V2 Requirements Baseline

## Background

This repository has grown into a relatively stable single-user Windows Service wrapper for the OpenClaw gateway. Real-world use has already validated many tricky edges around service identity, tray behavior, precise shutdown, remembered config, scheduled-task bridging, and the requirement to stay close to the currently signed-in Windows user.

The current design is still usable, but it also exposes a growing set of structural problems:

- The real product need is "background runtime in the current signed-in user context", not "machine-level host first"
- OpenClaw can restart itself and may evolve its own update and runtime behavior over time
- As the wrapper layer, we should not depend on deep assumptions about upstream internals
- The current Service model already needs substantial compensating logic to approximate user-level behavior

Before a V2 refactor starts, we need a clear baseline for actual requirements, boundaries, non-goals, and lifecycle scenarios. This document is intended to feed later ADRs, architecture work, and migration planning.

## Goals Of This Document

- Clarify the real problem this project must solve, independent of the current implementation
- Define ownership boundaries between upstream OpenClaw and this wrapper layer
- Capture the capabilities, scenarios, and non-goals required for V2
- Establish shared language for discussing a move from Windows Service hosting to a user-level background host

## Problem Statement

The original problem was not "how do we build a Windows Service", but rather:

- Run OpenClaw in the background on Windows without leaving a visible PowerShell window open
- Keep OpenClaw aligned with the current signed-in user's permissions, directories, config, and network environment
- Provide stable start, stop, restart, status, and diagnostic controls
- Support sign-in auto-start with a lightweight control surface
- Tolerate upstream restart, exit, and future update behavior without invasive coupling

## Core Principles

- User-first: default to the current signed-in user as the runtime boundary
- Upstream-first: do not block, rewrite, or over-assume OpenClaw's internal lifecycle semantics
- Wrapper restraint: the wrapper owns hosting, control, observability, and migration, not upstream business behavior
- Lifecycle-first: design around start, stop, restart, update, and recovery scenarios before deciding on UI shape
- Low-friction: normal daily use should not depend on Service installation, complex elevation bridges, or machine-level compensation logic

## Required Capabilities

### Runtime Model

- OpenClaw must be able to run in the current signed-in user context
- The default runtime shape should avoid a persistent visible PowerShell console window
- The runtime should naturally inherit the current user's directories, environment variables, proxy settings, and config paths
- Single-user Windows desktop usage remains the primary target; concurrent multi-user support is not a primary requirement

### Lifecycle Control

- Stable `start`, `stop`, `restart`, and `status` behavior is required
- User-initiated stop should be distinguishable from unexpected process exit
- The host must retain or rebuild state after tray restarts, control-surface restarts, or host restarts
- The design must leave room for upstream self-restart, self-exit, and future update behavior

### Observability And Diagnostics

- Logs must be recorded continuously and stored in a discoverable location
- A machine-readable runtime state file or equivalent state interface is required
- A lightweight diagnostic surface must remain available for current config, runtime identity, process state, and health details
- Control surfaces should be able to read status without directly owning process lifetime

### Auto-Start And Control Surface

- The system must support automatic startup after the current user signs in
- Auto-start should be user-centered and should not require a Windows Service by default
- The control surface may be tray, CLI, or a lightweight settings window, but it should not be the lifecycle owner
- Exiting the tray should not stop OpenClaw unless the user explicitly requests a stop

### Migration And Compatibility

- The current Windows Service path should remain available as a stable fallback in the short term
- The new model needs a migration path from existing config, paths, and operator expectations
- Migration should avoid breaking currently working OpenClaw environments

## Boundaries And Ownership

### Upstream OpenClaw Owns

- The schema and semantics of upstream config such as `openclaw.json`
- OpenClaw's internal business logic, runtime behavior, and command semantics
- How OpenClaw chooses to implement restart, update, and version evolution in the future
- Its internal process tree, file layout, and exit-code behavior

### Wrapper / Agent Owns

- A windowless, user-level background host
- Stable start, stop, restart, and status entry points
- Logging, runtime state, health checks, and basic diagnostics
- User sign-in auto-start and operator control surfaces such as tray or CLI
- Migration from the existing Service model to the new hosting model

### Wrapper / Agent Must Not Assume

- That OpenClaw will always use fixed exit codes for restart or update behavior
- That updates will always be in-place or always versioned
- That the upstream process topology will stay constant
- That OpenClaw will provide a permanent explicit signal for "restart requested" or "update requested"
- That full process control implies full knowledge of upstream lifecycle intent

## Key Scenarios

1. After the user signs in to Windows, the background host should start in that same user context and launch OpenClaw without a visible console window.
2. When the user explicitly stops OpenClaw, the host should record that as an intentional stop and avoid treating it as an automatic recovery event.
3. When the user explicitly restarts OpenClaw, the host should follow a clear shutdown and relaunch sequence instead of relying on ad hoc behavior.
4. When the tray or another control surface exits, the background host and OpenClaw should continue running, and a re-opened control surface should be able to recover state.
5. When OpenClaw exits, restarts itself, or replaces its own files, the host should prioritize compatibility and observability over brittle assumptions.
6. When OpenClaw crashes or repeatedly fails health checks, the host should surface clear state, notifications, and recovery behavior.
7. During sign-out, shutdown, or session transitions, host behavior should remain explicit and state should remain consistent.
8. During migration from the current Windows Service path, existing config and operator habits should remain usable, with the old path available as a fallback during transition.

## Non-Goals

- Concurrent multi-user runtime support is not a primary goal for the current phase
- Windows Service is not the default host model for V2
- Browser-first UI or web-shell packaging is not a requirement
- The wrapper should not invade upstream internals or take ownership of upstream version strategy
- Normal daily use should not require administrator privileges
- V2 phase 1 does not need to fully reproduce every operational detail of the current Service stack

## Design Constraints

- The new model must solve the original pain points of background windowless execution and user-context alignment first
- The new model should reduce dependence on Service installation, elevation bridges, scheduled-task bridges, and account-compensation logic
- Upstream unpredictability must be treated as normal, not exceptional
- Control surfaces, installers, and migration tools should serve the background host rather than define it

## Success Criteria

- Users no longer need a persistent visible PowerShell window to keep OpenClaw running
- OpenClaw runs by default in the current signed-in user's context and naturally inherits that environment
- Sign-in auto-start, manual start, manual stop, restart, and status are stable
- The background host continues running and keeping coherent state even if the control surface exits
- Self-restart, unexpected exit, and update-related upstream behavior no longer depend on Windows Service semantics
- The current Windows Service path can coexist as a temporary fallback during transition

## Open Questions

- What externally observable signals, if any, does OpenClaw provide now or plan to provide for intentional restart or update behavior
- On user sign-out, should OpenClaw stop, follow the session boundary, or participate in the next sign-in recovery flow
- In V2 phase 1, should recovery policy be automatic or primarily observability-first
- Should the new host manage OpenClaw binary versions directly, or assume updates are initiated independently by the user or upstream
- Which existing config fields must remain compatible during migration, and which should be explicitly retired

## Follow-Up Documents

This document should be followed by:

- An ADR describing why the default host moves from Windows Service to a user-level background host
- A V2 architecture blueprint covering processes, module boundaries, state model, and filesystem layout
- A migration plan for moving from the current Service path to the new hosting model
