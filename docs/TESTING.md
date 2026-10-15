# Testing and qualification

## Evidence levels

1. **Structural** — source, scripts or mappings are internally valid.
2. **Runtime** — logs show the software path behaving correctly.
3. **Live hardware** — the physical controller behaves correctly in Traktor.

Only level 3 qualifies controller behavior.

## Minimum build test

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
- Deck A actual Tempo Master: A trash + Play/Pause LEDs flash with Beat Phase.
- Deck B actual Tempo Master: behavior follows B.
- AUTO/Cruise master movement follows the actual Traktor master.
- Leaving master state restores the deck's normal Play/Pause LED state.

## Mapping validation

Each public mapping file should contain exactly one expected Controller Manager device. `tools/tsi_audit.py` is read-only and can summarize a mapping.

A parser pass does not replace live testing.

## Long-run stability

For qualification-level changes, use a multi-hour playback session and preserve the shutdown counters/logs. Review at least:

- BlackHole dropped frames;
- playback underruns;
- playback transfer errors;
- synchronous USB write duration;
- catch-up events;
- CoreMIDI OUT drops.

A recovered transport stall is still recorded as a stall. Do not turn it into a “no issue” result merely because buffering recovered.
