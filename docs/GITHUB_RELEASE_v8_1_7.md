# Reloop Jockey 3 ME macOS Bridge v8.1.7

**Event-driven Traktor session controls for Spotlight and Reduce Motion, promoted from the physically qualified Candidate 7 without changing the qualified audio/MIDI bridge.**

## Highlights

- **Bridge engine v8.0.8 — unchanged**
- **Bridge supervisor v8.1.5 behavior — unchanged**
- **Service/package release v8.1.7**
- Replaces the old polling Spotlight guard with an **event-driven root helper**
- Replaces the polling Reduce Motion guard with one **event-driven NSWorkspace WatchGuard**
- No recurring `pgrep` loop for the new automation layer
- No recurring `mdutil -s` loop
- Saves both original macOS states before applying either DJ-session change
- Uses compare-before-write and compare-before-restore for both states
- Preserves recovery state until restoration is verified
- Keeps the physically qualified v8.0.8 engine binary unchanged

## Why this release exists

v8.1.6 successfully automated Reduce Motion, but its helper polled for Traktor every two seconds and the v8.1.5 Spotlight guard also polled. That added steady-state process churn to a Mac whose primary requirement is reliable real-time DJ audio.

v8.1.7 keeps the already-qualified bridge path intact and changes only the automation layer. Traktor lifecycle detection is now driven by macOS application launch/termination events. Spotlight work occurs only on lifecycle transitions. Reduce Motion work occurs only when its state actually needs to change or restore.

## State-transition rules

On Traktor start:

1. read and persist the original Reduce Motion state;
2. ask the root Spotlight helper to persist the original indexing state;
3. if either original state cannot be safely persisted, do not apply DJ-state writes;
4. if Spotlight is already disabled, do not write it again; otherwise disable it once and verify;
5. if Reduce Motion is already enabled, do not write it again; otherwise enable it once and verify.

On Traktor exit:

1. read the current state;
2. compare it with the saved original;
3. if it already matches, do nothing;
4. otherwise restore once and verify;
5. delete the saved recovery state only after successful restoration.

Helper restart recovery never invents a pre-Traktor state.

## Runtime architecture

### User WatchGuard

`com.guy.reloopbridge.watchguard`

The WatchGuard:

- subscribes to `NSWorkspaceDidLaunchApplicationNotification` and `NSWorkspaceDidTerminateApplicationNotification`;
- performs one startup reconciliation for recovery;
- manages Reduce Motion;
- communicates lifecycle transitions to the root Spotlight helper;
- sleeps in its run loop during steady state.

### Root Spotlight helper

`com.guy.reloopbridge.spotlightguard`

The Spotlight helper:

- blocks on an authenticated Unix-domain socket instead of polling;
- accepts requests only from the installing user's UID;
- runs `mdutil` only for save/apply/restore transitions;
- keeps durable recovery state under `/var/db/com.guy.reloopbridge`.

## Reduce Motion implementation

v8.1.7 deliberately keeps the effective-state mechanism that had already been live-proven in v8.1.6:

- write `com.apple.universalaccess/reduceMotion` through `CFPreferences`;
- refresh user `cfprefsd` and `universalaccessd` only when an actual state write is required;
- post `AXInterfaceReduceMotionStatusDidChange` twice after the proven settling delay;
- verify the effective state from a fresh child process;
- allow up to five seconds for effective-state confirmation.

The polling loop from v8.1.6 is not retained.

## Qualification

Candidate 7 completed installer QA before the live set:

- exact previously-qualified v8.0.8 engine SHA-256 verified;
- v8.1.5 bridge-supervisor behavior retained;
- Spotlight helper communication passed;
- real Spotlight disable/restore transition passed;
- Full Disk Access passed from the actual WatchGuard LaunchAgent context;
- reversible Reduce Motion change/restore passed;
- old automation jobs were absent;
- idle WatchGuard and Spotlight helper CPU measured effectively at 0.0% in the status snapshot.

The same Candidate 7 package was then used for an approximately **one-hour live DJ session on 23 October 2026**. Guy reported:

- normal DJ operation for the full session;
- **no crackling**;
- **no popping**;
- **no audio dropouts**;
- no observed bridge/control failure.

The session was intentionally controlled: Wi-Fi and Bluetooth were off and no other applications were run during the set.

## Exact qualified artifact

The v8.1.7 GitHub Release publishes the **exact Candidate 7 ZIP that was physically qualified**, byte-for-byte. It is renamed only at the release-asset filename level.

Qualified Candidate 7 ZIP SHA-256:

`8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d`

The executable/source package intentionally still reports `8.1.7-candidate7` internally. That identifier is retained so the released artifact remains identical to the one that was actually tested rather than rebuilding after qualification merely to change a version string.

## Unchanged components

v8.1.7 does **not** change:

- v8.0.8 audio/MIDI engine logic;
- v8.1.5 bridge-supervisor behavior;
- BlackHole -> Reloop routing;
- Traktor mappings;
- Tempo Master LED behavior;
- controller start/stop supervision.

## Release asset

`Reloop_Jockey_3_ME_Bridge_v8_1_7.zip`

SHA-256 is published alongside the ZIP by the release workflow.

## Documentation

See:

- `docs/RELEASE_NOTES_v8_1_7.md`
- `docs/QUALIFIED_RUNTIME_SETTINGS_v8_1_7.md`
- `docs/V8_1_7_EVENT_DRIVEN_GUARDS.md`
- `release/v8.1.7/CODE_REVIEW.md`

---

Independent project by **Guy R. Hood**.  
Licensed under the MIT License.  
Not affiliated with Reloop, Native Instruments, or the BlackHole project.
