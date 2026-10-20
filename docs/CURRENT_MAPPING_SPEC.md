# Current mapping specification

**Checkpoint:** 20 October 2026  
**Authoritative artifacts:** five mapping-only Controller Manager exports; see `checksums/MAPPING_ONLY_SHA256SUMS.txt`

The five exported mapping files are source truth. This document is the human-readable behavior specification.

## Bridge integration

All five Reloop devices use:

`Reloop Jockey 3 ME (Bridge)`

for input/output in the live-tested setup.

### A/B actual-Tempo-Master flashing

Deck A:

- Tempo Master IN `2293` -> `Ch01.Note.A-1`
- actual-master OUT `2293` -> `Ch16.Note.C0`
- Beat Phase OUT `513` -> `Ch01.Note.A-1`
- Play/Pause IN/OUT `100` -> `Ch01.Note.D1`

Deck B:

- Tempo Master IN `2293` -> `Ch02.Note.A-1`
- actual-master OUT `2293` -> `Ch16.Note.C#0`
- Beat Phase OUT `513` -> `Ch02.Note.A-1`
- Play/Pause IN/OUT `100` -> `Ch02.Note.D1`

Bridge behavior:

- only the actual Tempo Master deck's trash LED flashes;
- the same Beat Phase is mirrored to that deck's Play/Pause LED;
- ordinary Play/Pause LED output is suppressed only while that deck is master;
- cached ordinary Play/Pause state is restored when it ceases to be master;
- AUTO/Cruise master changes follow actual Traktor state.

## Live-confirmed RELOOP-button Low Kill

Deck A:

- Mixer Low Kill command `304` IN -> `Ch01.Note.F#-1`
- Mixer Low Kill command `304` OUT -> `Ch01.Note.F#-1`

Deck B:

- Mixer Low Kill command `304` IN -> `Ch02.Note.F#-1`
- Mixer Low Kill command `304` OUT -> `Ch02.Note.F#-1`

Guy live-confirmed both the Low Kill action and the physical RELOOP-button LED output on both decks.

## Project workflow choices

These are part of the current mapping but are not requirements of the audio bridge.

### Stereo Master Output ring meters

Deck A:

- FX Select 3 ring -> **Master Output Left**
- OUT command `2694` -> `Ch01.Note.G#1`

Deck B:

- FX Select Advanced ring -> **Master Output Right**
- OUT command `2695` -> `Ch02.Note.F1`
- two command `365` OUT records remain unbound in the Deck B export.

### Deck A

- Tempo Adjust `Ch01.PitchBend`: Invert OFF; physical up = faster.
- Custom four-band EQ.
- PAN -> Gain.
- Browser/view/load controls retained.
- FX1 -> previous Favorite.
- FX2 -> next Favorite.
- FX Select Advanced press `Ch01.Note.F1` -> Recorder Record/Stop `2056`, Toggle.
- RELOOP -> Mixer Low Kill with matching LED OUT.

### Deck B

- Tempo Adjust `Ch02.PitchBend`: Invert OFF; physical up = faster.
- Custom four-band EQ.
- PAN -> Gain.
- FX Select 3 turn -> browse.
- FX Select 3 press -> Browser view.
- Right Beat/Grid -> Load Selected + exit Browser view.
- FX1/FX2 -> Layout/View cycle.
- FX Select Advanced press `Ch02.Note.F1` -> Cruise Mode On `8194`, Toggle.
- FX Select 1 press -> no Recorder input.
- RELOOP -> Mixer Low Kill with matching LED OUT.
- two intentional existing command `100` OUT bindings are retained at `Ch02.Note.F2` and `Ch02.Note.F#2`.
- XFA -> Deck D Remix slot 1, Slot Retrigger, Hold -> `Ch02.Note.G0`.
- XFB -> Deck D Remix slot 2, Slot Retrigger, Hold -> `Ch02.Note.G#0`.
- XFC -> Deck D Remix slot 3, Slot Retrigger, Hold -> `Ch02.Note.A0`.
- XFD -> Deck D Remix slot 4, Slot Retrigger, Hold -> `Ch01.Note.A#0`.

The XFD channel-1 binding is recorded exactly as exported and live-tested. Do not normalize it to channel 2.

### Deck C / Sample C

- Physical GAIN/HIGH/MID/LOW disabled.
- PAN -> Gain.
- FX1 -> previous Favorite.
- FX2 -> next Favorite.
- Remaining Remix functions preserved.

### Deck D / Sample D

- Physical GAIN/HIGH/MID/LOW disabled.
- PAN -> Gain.
- FX Select 3 turn -> browse.
- FX Select 3 press -> Browser view.
- Right Beat/Grid `Ch04.Note.G#-1` -> Direct Sync OFF + Load Selected + exit Browser view.
- PLAY `Ch04.Note.D1` -> Deck Common Play/Pause.
- CUE `Ch04.Note.C#1` -> Remix Play All Slots.
- Physical SYNC `Ch04.Note.B0` -> Sync Toggle IN + Sync OUT.
- FX1/FX2 -> Layout/View cycle.
- FX B3 `Ch04.Note.E-1` -> Unload entire Deck D, no modifiers.

## Current mapping counts

- Deck A: **145 commands / 145 bindings**
- Deck B: **150 / 148**
- Sample C: **170 / 170**
- Mixer Section: **79 / 79**
- Sample D: **155 / 155**

The Deck B two-row command/binding difference is intentional: two command-365 OUT records are unbound.

## Mapping audit trail

- Low Kill additions: `docs/MAPPING_UPDATE_2026-10-19_LOW_KILL.md`
- Deck B XFA–XFD sample triggers: `docs/MAPPING_UPDATE_2026-10-20_DECK_B_SAMPLE_RETRIGGER.md`
