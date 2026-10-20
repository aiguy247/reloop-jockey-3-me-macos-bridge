# Mapping update — Deck A/B FX4 and Browser/Load button swap — 2026-10-20

Status: **current user-exported mapping state, live-confirmed by Guy for accessibility/playing ergonomics.**

Guy swapped two physical button assignments on both Deck A and Deck B to make the controls easier to reach while DJing.

## Source exports

Deck A:

`deck a swap load and fx4 buttons Settings.tsi`

SHA-256:

`588fec71b8677988df3fa63ba33c844b3ff26b7feda3302a4cf7ded4dd521b1f`

Deck B:

`deck b swap load and fx4 buttons Settings.tsi`

SHA-256:

`a1aadfbf963b076a440dc6df2df16d746db90e1515bb85f18e772ba9304497d1`

## Structural result

Relative to the immediately previous current mapping files:

- Deck A remains **145 commands / 145 bindings**.
- Deck B remains **150 commands / 148 bindings**.
- No command records were added or removed.
- Exactly four MIDI binding records changed on each deck.
- All other command/binding records are preserved.

## Deck A

### FX Unit 4 On

Command ID `339`:

- IN row ID `104`
- OUT/LED row ID `107`

Previous MIDI binding:

`Ch01.Note.E-1`

Current MIDI binding:

`Ch01.Note.G#-1`

### Only Browser On

Command ID `3076`, IN row ID `224`

Previous MIDI binding:

`Ch01.Note.G#-1`

Current MIDI binding:

`Ch01.Note.E-1`

### Load Selected — Deck Common

Command ID `4209`, IN row ID `226`

Previous MIDI binding:

`Ch01.Note.G#-1`

Current MIDI binding:

`Ch01.Note.E-1`

## Deck B

### FX Unit 4 On

Command ID `339`:

- IN row ID `104`
- OUT/LED row ID `107`

Previous MIDI binding:

`Ch02.Note.E-1`

Current MIDI binding:

`Ch02.Note.G#-1`

### Only Browser On

Command ID `3076`, IN row ID `221`

Previous MIDI binding:

`Ch02.Note.G#-1`

Current MIDI binding:

`Ch02.Note.E-1`

### Load Selected — Deck Common

Command ID `4209`, IN row ID `222`

Previous MIDI binding:

`Ch02.Note.G#-1`

Current MIDI binding:

`Ch02.Note.E-1`

## Preserved recent mappings

These exports also retain the already accepted recent changes:

- Deck A/B RELOOP-button Low Kill input + LED OUT.
- Deck B XFA–XFD -> Deck D Remix slots 1–4 Slot Retrigger.
- Existing Deck B Play/Pause-related OUT rows at `Ch02.Note.F2` and `Ch02.Note.F#2`.

The purpose of this change is control accessibility/ergonomics. It does not alter the bridge engine or audio path.
