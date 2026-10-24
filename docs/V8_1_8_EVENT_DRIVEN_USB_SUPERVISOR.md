# v8.1.8 event-driven USB supervisor

## Objective

Remove the final one-second controller-presence polling loop from the runtime path without modifying the physically qualified v8.0.8 audio/MIDI engine.

## Previous behavior

v8.1.5 used a shell loop that periodically executed `ioreg` and `grep` to determine whether the Reloop Jockey 3 ME was present.

## v8.1.8 behavior

The supervisor uses the controller identity already present in the qualified engine:

- vendor ID: `0x200c`
- product ID: `0x1019`

It registers IOKit matching notifications for controller arrival and termination.

Steady state:
- no `ioreg`;
- no `grep`;
- no one-second controller timer.

The supervisor sleeps waiting for IOKit events.

## Preserved engine lifecycle

- controller appears -> start exact v8.0.8 engine;
- controller disappears -> request clean engine shutdown;
- delayed SIGTERM remains the bounded fallback;
- unexpected engine exit while controller remains -> delayed restart;
- three rapid failures -> stop retrying until a physical removal/reconnect boundary.

## Sleep/wake

The supervisor also observes `NSWorkspaceDidWakeNotification` and performs one USB-state reconciliation after wake. This is an event-driven recovery check, not recurring polling.

## Qualification

Power cycling, physical USB cable removal/reconnection, sleep/wake, and Traktor/audio operation all passed on the physical setup.

See `docs/QUALIFIED_RUNTIME_SETTINGS_v8_1_8.md`.
