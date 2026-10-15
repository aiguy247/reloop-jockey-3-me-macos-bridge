# Traktor setup

## Audio routing used by the qualified baseline

Traktor audio device:

`BlackHole 16ch`

Sample rate:

`48000 Hz`

Bridge channel interpretation:

| Traktor/BlackHole channel | Bridge destination |
|---|---|
| 1 | Reloop Master Left |
| 2 | Reloop Master Right |
| 4 | Reloop Headphones Left |
| 3 | Reloop Headphones Right |

The monitor pair is intentionally 4/3 in the qualified bridge path.

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

## Important mapping distinction

The bridge itself does not require every workflow choice in these five mappings.

The Deck A/B actual-Tempo-Master and Beat Phase OUT rows are part of the LED integration used by v8.0.4. Many other rows are project workflow preferences: browser behavior, Favorites navigation, Recorder/Cruise buttons, four-band EQ choices and Deck C/D assignments.

Do not assume those workflow choices are universal. Review `CURRENT_MAPPING_SPEC.md` before importing or adapting them.

## Source of truth

For future mapping changes, the five current individual Controller Manager exports are the starting artifacts. Do not reconstruct them from older generated mapping files.
