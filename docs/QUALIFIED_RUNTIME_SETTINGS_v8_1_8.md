# Qualified runtime — v8.1.8

**Qualification date:** 24 October 2026

## Scope

v8.1.8 changes one subsystem only: controller-presence detection in the bridge supervisor.

Unchanged:
- bridge engine v8.0.8;
- exact qualified engine binary;
- audio/MIDI code;
- mappings;
- v8.1.7 WatchGuard;
- v8.1.7 Spotlight helper;
- Reduce Motion behavior;
- existing launchd identities.

Changed:
- v8.1.5 shell supervisor's one-second `ioreg | grep` controller polling;
- replaced by a compiled event-driven supervisor using IOKit/IOUSBHost matching notifications.

## Qualified identity

Engine SHA-256:

`66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`

Qualified Candidate 1 package SHA-256:

`853f29e6decfbb5291ae292ec9e43570ce0e146a48fee345999534024e9d837b`

USB identity:
- VID `0x200c`
- PID `0x1019`

## Qualified event paths

The following were tested on the physical controller and Mac:

1. Controller power OFF -> removal event -> engine stops cleanly.
2. Controller power ON -> arrival event -> engine starts.
3. Repeated controller power cycle -> PASS.
4. Physical controller USB cable unplugged from the hub -> removal event -> engine stops.
5. Physical controller USB cable reconnected to the hub -> arrival event -> engine restarts.
6. Repeated physical USB cycle -> PASS.
7. Sleep/wake with controller connected -> one `NSWorkspaceDidWakeNotification` reconciliation; existing engine preserved; no duplicate engine.
8. Steady-state supervisor resource snapshot -> no one-second USB polling.
9. Traktor/audio operation after the above tests -> user-reported perfect operation, with no crackling, popping, dropout, controller interruption, or observed engine restart.

## Wake result

The qualified wake path produced:

`USB state reconciliation (system-wake): controller connected.`

The supervisor PID and engine PID remained unchanged across the sleep/wake test.

## Event-order observation

During one physical USB-removal cycle, the engine exited cleanly milliseconds before the IOKit termination notification reached the supervisor. The supervisor temporarily counted that as rapid failure 1/3, then the subsequent physical-removal event cleared the failure state. No code change was made because the final state was correct and the behavior was harmless under the current state machine.

## Earlier invalid cycle

The first attempted removal test involved an engine process that had already failed during startup at `AudioDeviceStart` with OSStatus `268451843`. That process later took an extended time to exit. It is not treated as evidence about normal healthy-engine shutdown. Subsequent tests began from a confirmed healthy engine and passed.

## Result

**v8.1.8 Candidate 1 is the qualified development baseline.**

No GitHub Release is created at this checkpoint. The latest published release remains v8.1.7.
