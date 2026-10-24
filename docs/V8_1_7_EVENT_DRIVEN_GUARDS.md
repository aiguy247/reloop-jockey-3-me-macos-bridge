# v8.1.7 event-driven DJ guards

## Design objective

Reduce steady-state background activity while preserving the already-qualified bridge and the already-proven Reduce Motion write mechanism.

## Components

### `com.guy.reloopbridge.watchguard`

Per-user LaunchAgent. Responsibilities:

- observe Traktor launch/termination via NSWorkspace;
- own durable Reduce Motion recovery state;
- enforce the save-before-change barrier;
- send synchronous Spotlight transition commands;
- perform one startup reconciliation after helper restart.

### `com.guy.reloopbridge.spotlightguard`

Root LaunchDaemon. Responsibilities:

- own durable Spotlight recovery state;
- authenticate the local socket peer UID;
- compare current indexing state before changing it;
- run `mdutil` only when a transition requires it;
- block in the socket accept loop during steady state.

## State transition contract

No setting is written merely because Traktor exists. The code first reads state and compares it with the required target.

A restore is similarly conditional. Recovery state is cleared only after the original state is confirmed.

## Why the bridge was not redesigned

The v8.0.8 engine and v8.1.5 supervisor were already physically qualified. v8.1.7 intentionally avoids changing the bridge launch model, controller detection path, audio routing or MIDI behavior while changing the automation layer.

## Why the Reduce Motion write mechanism was retained

An earlier Candidate 6 attempt changed the effective-state verification method and failed its reversible transition test even though Full Disk Access was correct. Candidate 7 restored the v8.1.6 mechanism that had already been live-proven: fresh-process verification plus the specific preference-service refresh and accessibility notification sequence.

The improvement in v8.1.7 is therefore lifecycle detection and steady-state behavior, not a speculative rewrite of the working preference transition.
