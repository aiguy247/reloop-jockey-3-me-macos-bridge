# Current mapping specification

**Checkpoint:** 9 October 2026  
**Authoritative mapping artifacts:** five mapping-only Controller Manager exports; see `checksums/MAPPING_ONLY_SHA256SUMS.txt`

The exact TSI is source truth. This file is the human-readable behavior specification.

## Global

- Bridge In/Out: `Reloop Jockey 3 ME (Bridge)`.
- `Jockey 3 FX Presets` intentionally absent.
- Bridge engine **v8.0.4**; service/package **v8.1.3**.
- v8.0.4 retains the qualified v8.0.2 audio/USB path unchanged.

## A/B actual-Tempo-Master flashing — live-qualified

Deck A:
- Tempo Master IN `2293` → `Ch01.Note.A-1`
- actual-master OUT `2293` → `Ch16.Note.C0`
- Beat Phase OUT `513` → `Ch01.Note.A-1`
- Play/Pause IN/OUT `100` → `Ch01.Note.D1`

Deck B:
- Tempo Master IN `2293` → `Ch02.Note.A-1`
- actual-master OUT `2293` → `Ch16.Note.C#0`
- Beat Phase OUT `513` → `Ch02.Note.A-1`
- Play/Pause IN/OUT `100` → `Ch02.Note.D1`

Bridge behavior:
- only the actual Tempo Master deck's trash LED flashes;
- the same Beat Phase is mirrored to that deck's Play/Pause LED;
- ordinary Play/Pause LED output is suppressed only while that deck is master;
- cached ordinary Play/Pause state is restored when it ceases to be master;
- non-master Play/Pause LED behavior remains normal;
- AUTO/Cruise master changes follow actual Traktor state.

## Stereo Master Output ring meters

Deck A:
- FX Select 3 ring → **Master Output Left**
- OUT command `2694` → `Ch01.Note.G#1`

Deck B:
- FX Select Advanced ring → **Master Output Right**
- OUT command `2695` → `Ch02.Note.F1`
- two old command `365` OUT records remain present but unbound; preserve them unless intentionally cleaning the file.

## Deck A

- Tempo Adjust `Ch01.PitchBend`: Invert OFF; physical up = faster.
- Custom four-band EQ retained.
- PAN → Gain.
- Browser/view/load controls retained.
- FX1 → previous Favorite.
- FX2 → next Favorite.
- FX Select Advanced press `Ch01.Note.F1` → Recorder Record/Stop `2056`, Toggle.

## Deck B

- Tempo Adjust `Ch02.PitchBend`: Invert OFF; physical up = faster.
- Custom four-band EQ retained.
- PAN → Gain.
- FX Select 3 turn → browse.
- FX Select 3 press → Browser view.
- Right Beat/Grid → Load Selected + exit Browser view.
- FX1/FX2 → Layout/View cycle.
- FX Select Advanced press `Ch02.Note.F1` → Cruise Mode On `8194`, Toggle.
- FX Select 1 press → no Recorder input.
- XFA–XFD intentionally unused.

## Deck C / Sample C

- Physical GAIN/HIGH/MID/LOW disabled.
- PAN → Gain.
- FX1 → previous Favorite.
- FX2 → next Favorite.
- Remaining Remix functions preserved.

## Deck D / Sample D

- Physical GAIN/HIGH/MID/LOW disabled.
- PAN → Gain.
- FX Select 3 turn → browse.
- FX Select 3 press → Browser view.
- Right Beat/Grid `Ch04.Note.G#-1` → Direct Sync OFF + Load Selected + exit Browser view.
- PLAY `Ch04.Note.D1` → Deck Common Play/Pause.
- CUE `Ch04.Note.C#1` → Remix Play All Slots.
- Physical SYNC `Ch04.Note.B0` → Sync Toggle IN + Sync OUT.
- FX1/FX2 → Layout/View cycle.
- FX B3 `Ch04.Note.E-1` → Unload entire Deck D, no modifiers.

## Current mapping counts

- Deck A: **143 commands / 143 bindings**
- Deck B: **142 / 140**
- Sample C: **170 / 170**
- Mixer Section: **79 / 79**
- Sample D: **155 / 155**

The Deck B command/binding difference is intentional current-file state.
