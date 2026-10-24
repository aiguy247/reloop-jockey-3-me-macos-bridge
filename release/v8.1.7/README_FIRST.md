# Reloop Bridge 8.1.7 Candidate 7

## Scope

Candidate 7 deliberately changes only the DJ-session automation layer.

Preserved:
- qualified v8.0.8 engine;
- v8.1.5 bridge-supervisor behavior;
- existing `com.guy.reloopbridge` bridge LaunchAgent model.

Changed:
- old polling Spotlight guard is replaced by an event-driven root helper;
- Reduce Motion is controlled by one event-driven user WatchGuard;
- Traktor lifecycle detection uses NSWorkspace launch/termination notifications.

## State rule

At a normal Traktor launch, both original states are persisted before either feature
is changed.

For each feature:
- if the current state already equals the DJ target, no write occurs;
- otherwise it is changed once and verified.

At Traktor termination:
- current state is compared with the saved original;
- if already equal, no write occurs;
- otherwise the original state is restored once and verified;
- saved state is deleted only after successful restoration.

## Recovery

WatchGuard performs one startup reconciliation.

If WatchGuard restarts while Traktor is running:
- it enforces a DJ state only when an original saved state already exists;
- it never invents a new pre-Traktor state.

If it restarts while Traktor is not running:
- any durable saved original state is restored.

The root Spotlight helper uses the same rule.

## Steady-state resource behavior

WatchGuard:
- no timer;
- no pgrep loop;
- no repeated preference probes;
- sleeps in the NSRunLoop awaiting NSWorkspace notifications.

Spotlight helper:
- no timer;
- no pgrep;
- no recurring mdutil;
- blocks in `accept()` on a Unix-domain socket.

The root socket validates the connecting process UID.

`mdutil` runs only during Spotlight prepare/apply/restore transitions.

Reduce Motion preference-service restarts are a bounded fallback only when an actual
state change fails to become effective directly. They are never run on a timer.

## Installation safety

All of these happen before the installed runtime is changed:
- exact qualified engine build procedure;
- exact engine output SHA verification;
- supervisor shell syntax check;
- WatchGuard compilation;
- Spotlight helper compilation;
- app bundle creation and code-sign verification;
- all launchd plist linting.

The installer also restores any valid durable Spotlight state before replacing an older
guard.

A Reduce Motion recovery state is preserved across the clean install so the new
WatchGuard can restore it from its actual Full Disk Access context.

## Rollback

`rollback_automation_only.sh` removes only the new automation components after first
verifying that any saved states have been restored. The qualified bridge is left alone.


## Candidate 7 preflight correction

Candidate 5 incorrectly assumed one exact local repository directory. Candidate 7 does
not depend on that path.

Engine preparation now uses this order:

1. If the exact previously-qualified v8.0.8 binary still exists at a known installed
   runtime path and matches its known SHA-256, preserve that exact binary before teardown.
2. Otherwise, discover the local bridge repository by the qualified build-script path.
3. Accept a repository only when the v8.0.4 base, v8.0.6 patch, and v8.0.8 source all
   match their exact qualified SHA-256 values.
4. Run that repository's existing qualified v8.0.8 build procedure.
5. Verify the result is an arm64 Mach-O executable and preserve that preflight result
   before any installed runtime is removed.

A freshly linked Mach-O whole-file SHA is not used as a mandatory reproducibility gate:
linker metadata such as LC_UUID can change while source and compile behavior remain the
same. The installer does still prefer the exact previously-qualified binary whenever it
is available.


## Candidate 7 targeted correction

Candidate 6 passed Spotlight and Full Disk Access checks but its reversible Reduce
Motion test failed.

Root cause: Candidate 6 changed the effective-state verification mechanism from the
already live-proven v8.1.6 implementation. The long-running WatchGuard process can
observe a cached AppKit Reduce Motion value.

Candidate 7 keeps the event-driven lifecycle architecture but restores the proven
v8.1.6 Reduce Motion transition mechanism:

- write `com.apple.universalaccess/reduceMotion` with CFPreferences;
- restart user `cfprefsd` and `universalaccessd` only when a state write is actually
  required;
- post `AXInterfaceReduceMotionStatusDidChange` twice with the proven settling delay;
- verify the effective state from a fresh child process;
- allow up to five seconds for effective-state verification.

This does not reintroduce the old 2-second Traktor polling loop. The refresh sequence
runs only on actual start/restore transitions or the installer's reversible test.
