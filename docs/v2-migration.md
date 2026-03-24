# V2 Migration Plan

## Goal

V2 migration is not a one-shot rewrite. It is a **gradual migration** from the current stable Windows Service wrapper to a new user-level background Agent.

Migration goals:

- Keep the current Windows Service path as a short-term fallback
- Introduce the new user-level host without breaking working environments
- Gradually move daily control from PowerShell + Service semantics to Agent + CLI + Tray semantics
- Decide later when the old Service-first path can be formally retired

## Migration Principles

- Freeze design before code implementation
- Introduce the new host before removing the old one
- Migrate control capability first, operator habits second
- Reach functional parity before discussing full replacement
- During migration, the old Service path and new V2 path must not co-manage the same OpenClaw instance

## Short-Term Parallel Strategy

During transition, the repository contains two paths:

- Current stable path: Windows Service wrapper
- Next-stage path: user-level background Agent design and future implementation

Short-term requirements:

- The old Service path remains usable
- V2 documentation and future implementation must be clearly marked as the new path
- The same target environment should not enable both old Service and new Agent by default for the same OpenClaw instance

## Migration Stages

### Stage 0: Freeze Documentation

Goal:

- Lock requirements, ADR, architecture blueprint, and migration plan
- Freeze high-impact V2 phase 1 decisions

Done when:

- Implementers no longer need to decide the default host, IPC, control surfaces, update boundary, sign-out policy, or passwordless-user support

### Stage 1: Build The Minimal User-Level Host

Goal:

- Introduce `Host + CLI`
- Make `start / stop / restart / status / doctor` work
- Use current-user auto-start instead of Service-first auto-start semantics

Requirements:

- Existing Service scripts are not deleted yet
- OpenClaw update management is still out of scope

### Stage 2: Add The Tray Control Surface

Goal:

- Introduce `Tray`
- Have tray communicate with `Host` over IPC
- Provide the normal desktop usage path

Requirements:

- Exiting the tray must not stop the background host
- Daily operations should no longer depend on UAC + Service control bridges

### Stage 3: Import Existing Configuration

Goal:

- Import the still-relevant fields from the current wrapper config
- Define a mapping from old wrapper config to new agent config

Requirements:

- The migrator must clearly state which fields are retained and which are retired
- The migrator must not silently swallow incompatible fields; it should log or surface them

### Stage 4: Validate Functional Parity

Goal:

- Confirm that the new path covers mainstream day-to-day scenarios
- Clarify which scenarios still rely on the old Service fallback

Requirements:

- Default-path switching should not even be discussed until the common daily loop is stable

### Stage 5: Switch The Default Recommended Path

Goal:

- Move documentation default guidance to the user-level Agent
- Downgrade the old Service path to compatibility/fallback guidance

Requirements:

- This only happens after the new path is proven stable
- This migration plan does not commit to a concrete deletion date

## Config Migration Strategy

### Fields To Retain

From the current wrapper config, V2 should preferentially preserve:

- `configPath`
- `openclawCommand`
- `port`
- `bind`
- `httpProxy`
- `httpsProxy`
- `allProxy`
- `noProxy`
- `tray.*` values that still make sense for a user-level control surface

### Fields To Retire

V2 no longer treats the following as main-path config concepts:

- `serviceName`
- `displayName`
- `serviceAccountMode`
- `winswVersion`
- `winswDownloadUrl`
- `winswChecksum`
- `failureActions`
- `resetFailure`
- `startMode`
- `delayedAutoStart`
- restart-task related fields and derived concepts

### Import Requirements

- Import is primarily a field-extraction process for concepts that still matter
- Retired fields should be listed clearly in migration output
- V2 does not need to preserve every Service-specific default

## When V2 Can Replace The Old Default

V2 should only become the default recommended path when all of the following are true:

- Users no longer need a persistent visible PowerShell window to run OpenClaw
- Passwordless current-user scenarios work for runtime and auto-start
- `start / stop / restart / status / doctor` are stable
- Tray + CLI cover the primary daily operations loop
- The old Service path is no longer required for most single-user scenarios
- Unexpected exit, self-exit, and routine restart behavior have clear status reporting and acceptable behavior in the new host

## Transition Notes

- The old Service path remains an official fallback and should not be described as a temporary hack
- Until the new V2 path is fully stable, it should not automatically replace production Service installations
- To operators, migration should feel like "a more natural user-level background host", not "more features with more confusing semantics"

## Non-Goals

- This migration plan does not define concrete class names or implementation symbols
- This migration plan does not schedule immediate deletion of the PowerShell path
- This migration plan does not promise full OpenClaw update handling in phase 1
