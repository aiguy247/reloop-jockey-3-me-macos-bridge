# Reloop Jockey 3 ME macOS Bridge v8.1.5

**Live-tested macOS bridge for the Reloop Jockey 3 ME — bidirectional MIDI, 48 kHz audio routing, Tempo Master LED behavior, controller mappings, diagnostics, and automatic Spotlight control for Traktor.**

This release is the current public baseline used on the original project Mac.

## Highlights

- **Bridge engine v8.0.8**
- **Service/package v8.1.5**
- 48 kHz BlackHole -> Reloop Master/headphone routing
- Bidirectional CoreMIDI endpoint: `Reloop Jockey 3 ME (Bridge)`
- Actual Traktor Tempo Master tracking for Deck A/B
- Beat Phase flashing on the active master's trash and Play/Pause LEDs
- Deck A/B RELOOP-button Low Kill with LED output
- Deck B XFA–XFD triggers Deck D Remix slots 1–4 while Deck B remains selected
- Final Deck A/B FX4 versus Browser/Load button swap for better playing ergonomics
- Automatic Spotlight filesystem-indexing pause while Traktor runs
- Phase 4 USB/MIDI diagnostics and bounded transport-recovery logic

## Final live-tested configuration

Tested on:

- **Mac:** MacBookPro17,1 — Apple M1, 16 GB
- **macOS:** Sonoma 14.8.9, build 23J631
- **Traktor Pro:** 3.11.1.17
- **Controller:** Reloop Jockey 3 ME
- **Controller firmware observed:** 1.0.6
- **Audio device:** BlackHole 16ch
- **Sample rate:** 48 kHz
- **Buffer:** 384 samples
- **Traktor Multi-Core Processing:** OFF
- **Hub used for the final baseline:** Hama, Reloop at USB High Speed / 480 Mb/s

macOS settings used during the final successful tests:

- Touch Bar: Expanded Control Strip
- Automatic display brightness: OFF
- True Tone: ON
- Reduce Motion: ON

## Final test result

After several live tests on the physical controller, the final configuration was accepted as the de facto running baseline.

Normal mixing and controller use were smooth, including with:

- Traktor Mix Recorder running
- Google Chrome open
- ChatGPT desktop app open

Observed result:

- no UI glitches
- no pops or clicks
- no crackling
- no audio dropouts
- normal recording
- correct automatic Spotlight off/on behavior

The earlier recording-on/off comparison is therefore preserved only as a historical workload confound. **Mix Recorder is not a current known problem and does not need to be disabled.**

## Spotlight guard

v8.1.5 adds a separate root LaunchDaemon:

`com.guy.reloopbridge.spotlightguard`

When Traktor starts, it:

1. records the previous Spotlight indexing state;
2. disables filesystem indexing for the startup volume;
3. leaves the real-time audio/MIDI engine separate from Spotlight control.

When Traktor exits, the helper restores the previous Spotlight indexing state.

This behavior was tested repeatedly on the original Mac.

The helper deliberately does **not** kill `mds`, `fileproviderd`, iCloud services, browsers, or unrelated applications.

## Current controller mapping changes

### Deck A / Deck B Low Kill

The physical RELOOP button now controls Mixer Low Kill on Deck A and Deck B, including matching LED output.

### Deck B sample access

While Deck B remains selected:

- XFA -> Deck D Remix slot 1
- XFB -> Deck D Remix slot 2
- XFC -> Deck D Remix slot 3
- XFD -> Deck D Remix slot 4

All four use Traktor Slot Retrigger / Hold behavior.

### FX4 / Browser-Load accessibility swap

On both Deck A and Deck B:

- **FX Unit 4 On + LED** moved from `E-1` to `G#-1`
- **Only Browser On + Load Selected — Deck Common** moved from `G#-1` to `E-1`

This is a mapping-only ergonomics change. It does not change the bridge engine or audio path.

## Audio routing

| BlackHole channel | Reloop destination |
|---|---|
| 1 | Master Left |
| 2 | Master Right |
| 4 | Headphones Left |
| 3 | Headphones Right |

The 4/3 headphone order is intentional.

## What is included in the repository

- Objective-C bridge source
- v8.1.5 service and Spotlight-helper source
- five current mapping-only Traktor Controller Manager exports
- SHA-256 records
- build and diagnostic tooling
- detailed setup, mapping, qualification and engineering documentation

GitHub automatically provides source-code ZIP and TAR archives for this tagged release.

## Important scope note

This repository records the exact working system used on the original project Mac.

The v8.1.5 service installer is the **qualified upgrade path for that Mac**, including rollback to its prior v8.1.3 installation. It is not presented as a universal one-click fresh installer for arbitrary Macs.

Other Macs, macOS versions, controller firmware revisions and Jockey models may work, but they are not claimed as live-qualified without hardware evidence.

## Remaining technical boundary

v8.0.8 contains bounded recovery logic for the rare catastrophic zero-byte USB transport failure reproduced earlier in Phase 4.

The final accepted tests did **not** reproduce that catastrophic event, so that specific recovery path remains **implemented but unexercised on hardware**.

Normal v8.0.8 / v8.1.5 operation is live-tested.

## Documentation

For the technical record, see:

- `docs/QUALIFIED_RUNTIME_SETTINGS_v8_1_5.md`
- `docs/RELEASE_NOTES_v8_0_8_v8_1_5.md`
- `docs/CURRENT_MAPPING_SPEC.md`
- `docs/QUALIFICATION.md`
- `docs/KNOWN_LIMITATIONS.md`
- `docs/V8_1_5_SPOTLIGHT_GUARD.md`

---

Independent project by **Guy R. Hood**.  
Licensed under the MIT License.  
Not affiliated with Reloop, Native Instruments, or the BlackHole project.
