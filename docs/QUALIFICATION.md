# Qualification and test evidence

## Qualification model

The project uses three evidence levels:

1. **Structural validation** — source/mapping/script structure is internally consistent.
2. **Runtime evidence** — logs show how the bridge/helper behaved.
3. **Live hardware qualification** — the physical controller and Traktor/macOS behavior are tested directly.

Live hardware is the final acceptance gate for controller behavior.

## v8.0.4 / v8.1.3 live qualification

The actual-Tempo-Master trash LED and Play/Pause LED behavior was tested on the physical Reloop Jockey 3 ME and reported working as intended.

The five mapping-only Controller Manager exports in `mapping/` were taken from that final qualified Traktor mapping state.

## v8.0.8 / v8.1.5 final live acceptance — 20 October 2026

Guy accepted engine v8.0.8 / service v8.1.5 as the running baseline after several live tests on the physical controller.

Final tested configuration included Traktor Pro 3.11.1.17, BlackHole 16ch at 48 kHz, 384-sample buffer, Multi-Core Processing OFF, the automatic Spotlight guard, and the documented current mappings.

Guy reported smooth normal mixing/recording with no UI glitches, pops/clicks, crackling or audio drops in the final configuration.

The Spotlight helper was directly observed detecting Traktor, disabling indexing and restoring the prior state after Traktor exited.

## v8.1.6 Reduce Motion acceptance — 20 October 2026

The Reduce Motion logic that became production v8.1.6 was live-tested as candidate v5 on the same Mac.

Accepted sequence:

1. Reduce Motion starts OFF.
2. Traktor starts.
3. Helper detects the exact `Traktor` process and saves `disabled` as the pre-Traktor state.
4. Reduce Motion becomes ON.
5. Traktor exits.
6. Helper restores Reduce Motion to OFF.
7. Desktop/Spaces motion returns immediately without restarting Dock.

The accepted implementation also verified:

- protected `com.apple.universalaccess` writes require Full Disk Access;
- effective state verification must use a fresh helper process to avoid stale AppKit cache reads;
- `pgrep -x Traktor` is the reliable process detector used in production;
- `AXInterfaceReduceMotionStatusDidChange` refreshes already-running listeners without the disruptive Dock restart tested earlier.

Production source changes from accepted candidate v5 are limited to stable state/log paths and removal of candidate naming.

## Causality boundary

Several runtime settings were changed during earlier diagnosis. The evidence supports the combined accepted configuration but does not prove that any one setting alone caused or fixed all earlier UI/audio symptoms.

The v8.0.8 bounded catastrophic USB-recovery path remains unexercised because the accepted tests did not reproduce the catastrophic zero-byte USB failure.
