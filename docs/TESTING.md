# Testing and qualification

## Evidence levels

1. **Structural** — source, scripts or mappings are internally valid.
2. **Runtime** — logs show the software path behaving correctly.
3. **Live hardware** — the physical controller/macOS behavior is confirmed directly.

Only level 3 qualifies controller behavior.

## Minimum engine build test

- Verify source SHA-256.
- Compile without errors.
- Confirm no unexpected source changes.
- Start the engine with the controller connected.
- Confirm the bridge reports 48 kHz operation.
- Confirm CoreMIDI endpoint `Reloop Jockey 3 ME (Bridge)` appears.

## Audio smoke test

- Traktor audio device is BlackHole 16ch at 48 kHz.
- Master Left/Right reaches the Reloop Master output.
- Monitor Left/Right reaches headphones in the expected orientation.
- No immediate underrun/drop counters increase during normal playback.

## MIDI smoke test

- Deck A/B transport controls respond.
- Non-master Play/Pause LEDs behave normally.
- Actual Tempo Master trash + Play/Pause LEDs flash with Beat Phase.
- Leaving master state restores normal Play/Pause LED state.

## v8.1.6 helper smoke test

With Traktor closed and Reduce Motion OFF:

1. confirm `com.guy.reloopbridge.reducemotionguard` is loaded;
2. start Traktor;
3. within a few seconds confirm Reduce Motion is ON;
4. confirm Spotlight indexing is disabled;
5. close Traktor;
6. confirm Reduce Motion returns to OFF;
7. confirm normal Spaces/desktop sliding motion returns without restarting Dock;
8. confirm Spotlight indexing returns to its saved pre-Traktor state.

Repeat with Reduce Motion already ON before Traktor; it should remain ON after Traktor exits.

## Mapping validation

Each public mapping file should contain exactly one expected Controller Manager device. `tools/tsi_audit.py` is read-only and can summarize a mapping.

A parser pass does not replace live testing.

## Long-run stability

For qualification-level engine changes, use a multi-hour playback session and preserve the shutdown counters/logs. Review BlackHole drops, playback underruns, USB errors/duration, catch-up events and CoreMIDI OUT drops.
