# Traktor setup

## Current live-tested audio configuration

Traktor version observed:

`3.11.1.17`

Audio device:

`BlackHole 16ch`

Sample rate:

`48000 Hz`

Buffer:

`384 samples`

Traktor-reported overall latency on the qualified Mac:

approximately `8 ms`

Multi-Core Processing:

**OFF**

### Bridge channel interpretation

| Traktor/BlackHole channel | Bridge destination |
|---|---|
| 1 | Reloop Master Left |
| 2 | Reloop Master Right |
| 4 | Reloop Headphones Left |
| 3 | Reloop Headphones Right |

The monitor pair is intentionally 4/3.

## MIDI

The bridge exposes:

`Reloop Jockey 3 ME (Bridge)`

For the included Reloop Controller Manager devices, set both In-Port and Out-Port to that bridge endpoint.

## Included mapping files

The repository contains five individual Controller Manager exports:

- Deck A
- Deck B
- Mixer Section
- Sample C
- Sample D

They are mapping-only files. They do not contain global Traktor preferences.

Current Deck A/B workflow additions include the RELOOP-button Low Kill mapping and the Deck B XFA–XFD Deck D sample-slot triggers. See `CURRENT_MAPPING_SPEC.md`.

## Mix Recorder

Mix Recorder works in the final live-tested configuration.

Earlier Phase 4 tests treated recording as a possible workload confound. Later final tests ran recording successfully with Chrome and ChatGPT open and did not reproduce the earlier UI glitches, pops, crackling or audio drops.

Recording therefore is **not** listed as something that must be disabled.

The qualified Mac uses:

`~/Downloads/traktor-recordings`

as the recording-output location and excludes that directory from Spotlight indexing.

## macOS settings used in the successful configuration

- Touch Bar: Expanded Control Strip
- Automatic display brightness: OFF
- True Tone: ON
- Reduce Motion: ON
- Spotlight automatic guard: enabled through v8.1.5
- Spotlight Privacy exclusions: see `QUALIFIED_RUNTIME_SETTINGS_v8_1_5.md`

These are the tested settings for the original Mac. They are not all claimed to be individually necessary.

## Important mapping distinction

The bridge itself does not require every workflow choice in the five mappings.

The Deck A/B actual-Tempo-Master and Beat Phase OUT rows are part of the LED integration. Other rows are project workflow preferences such as browser behavior, Favorites navigation, Recorder/Cruise buttons, EQ choices and Deck C/D assignments.

Review `CURRENT_MAPPING_SPEC.md` before adapting them.

## Source of truth

For future mapping changes, the five current individual Controller Manager exports under `mapping/` are the starting artifacts. Do not reconstruct them from older generated mapping files.
