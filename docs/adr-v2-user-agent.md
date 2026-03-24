# ADR: V2 Default Host Moves To A User-Level Background Agent

## Status

Accepted

## Date

2026-03-24

## Context

The current stable path in this repository is a single-user Windows Service wrapper. It solved several real problems:

- OpenClaw can run in the background without a permanently visible PowerShell window
- The wrapper already provides install, start, stop, restart, status, diagnostics, and tray control
- By constraining service identity around the current signed-in user, it already reduced some `LocalSystem`, path drift, and tray mismatch issues

However, the design now shows increasing host-model mismatch:

- The real product need is closer to "a windowless background host in the current signed-in user's context" than "machine-level service first"
- The Service path already needs substantial compensating logic such as a tray companion, UAC control bridge, scheduled-task restart bridge, and strict service identity rules
- OpenClaw is upstream, so we should not depend on its future restart, update, or process behavior remaining stable
- The current Service path also requires the user to set a password for service installation, which conflicts with the expected shape of a user-level background tool

Given these facts, continuing to treat Windows Service as the default path no longer provides the best long-term tradeoff.

## Decision

V2 will no longer use Windows Service as the default host.  
The default V2 host is a **user-level background agent**.

V2 phase 1 locks the following defaults:

- Primary stack: `.NET 8 + C#`
- Control surfaces: `CLI + Tray`
- Tray technology: `WinForms`
- Host model: windowless, single-instance, user-level background agent
- IPC: `Named Pipe`
- Update strategy: `Observe Only`
- Sign-out strategy: `Stop On Sign-out`
- User constraint: the design must support a current Windows user without a password

The goal of V2 is not to replace OpenClaw itself. It is to redefine the wrapper layer as:

- a user-level host
- a lifecycle control surface
- a status, logging, health, and diagnostics layer
- a migration path away from the current Service-based host model

## Why The Original Service Path Was Reasonable

Choosing Windows Service originally was not a bad decision:

- "background runtime" naturally suggests Service on Windows
- Service appears more formal and stable for long-running behavior
- WinSW + PowerShell provided a practical way to ship install, control, and operational tooling quickly

More importantly, the Service path taught us the actual product boundaries:

- OpenClaw needs background windowless execution
- OpenClaw needs alignment with the current signed-in user's permissions and environment
- The dominant target is a single-user Windows desktop, not a machine-level multi-user service host
- Most long-term complexity comes from host-model mismatch, not from OpenClaw control itself

## Why Service Is No Longer The Default

As requirements became clearer, Windows Service as the default host now creates structural friction:

- User-context semantics and Service semantics are naturally different
- Tray, CLI, and Service lifecycle now require multiple bridging layers
- Sign-out, elevation, scheduled-task bridging, service credentials, and remembered config are operational costs created by the host model rather than by OpenClaw itself
- "Needs background runtime" does not mean "must be a Service"
- "Needs current-user permissions" conflicts directly with "requires password-backed service installation"

Because of that, adding more complexity to the Service-first path is no longer the best long-term direction.

## Alternatives Rejected

### Keep Windows Service As The Default Path

Rejected because:

- It does not match the user-level runtime boundary
- It keeps expanding password, elevation, tray bridge, and update coordination complexity
- It keeps the architecture centered on a system host instead of a user host

### Node.js / Electron / Tauri As The Mainline

Rejected because:

- The primary problem is host integration and lifecycle control, not browser-first UI
- Browser shells are not the right first-phase focus
- Electron/Tauri would turn a host-model problem into a UI-stack problem
- .NET fits Windows tray, auto-start, single-instance control, and process supervision more naturally

### Rust As The Mainline

Rejected because:

- Rust is possible, but not the best match for the dominant constraints here
- The primary problem is a Windows user-level host with tray and lifecycle stability, not extreme performance or low-level systems work
- Compared with .NET, it offers less natural first-phase productivity for this Windows-focused host model

## Consequences

After this ADR, the repository direction becomes:

- Keep the current Windows Service path as a short-term fallback
- Freeze V2 design decisions in documentation before implementation
- Treat the future primary implementation path as a `.NET` user-level background agent

Positive effects:

- The architecture aligns with real product needs
- Background execution no longer depends on Service installation by default
- Passwordless current-user support becomes a design constraint instead of an afterthought
- Tray and CLI return to being control surfaces instead of lifecycle compensation layers

Costs accepted:

- A new user-level host path must be implemented
- The transition period must support both current Service fallback and new design docs
- State model, IPC, and migration behavior must be redefined cleanly

## Follow-Up

This ADR should be followed by:

1. A V2 architecture blueprint
2. A V2 migration plan
3. Implementation milestones based on the frozen documentation decisions
4. User-level Agent implementation without breaking the current Service fallback path
