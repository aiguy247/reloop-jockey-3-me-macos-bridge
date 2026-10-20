# Mapping update — A/B RELOOP button Low Kill — 2026-10-19

Status: **live-confirmed mapping update incorporated into the v8.1.5 current baseline.**

Guy manually added Mixer Low Kill to the physical RELOOP button on Deck A and Deck B in Traktor Controller Manager, including an OUT row intended to drive the same button LED, then exported each device separately.

## Exact user exports

### Deck A

Source file: `deck a add low kill Settings.tsi`

SHA-256: `338d0b50a6893205ec16fc974e3146327cc260514feed88f2a611400cff32f4b`

Structural audit:

- one Controller Manager device: `Jockey 3 Deck A`;
- Generic MIDI;
- 145 command rows;
- 145 binding rows;
- two references to `Reloop Jockey 3 ME (Bridge)` (In-Port and Out-Port).

Relative to the last qualified A/B Play/Pause-flash mapping checkpoint, the only Direction + Command ID + MIDI-binding additions are:

- IN: command `304` -> `Ch01.Note.F#-1`;
- OUT: command `304` -> `Ch01.Note.F#-1`.

No Direction + Command ID + MIDI-binding row was removed.

The user's intended meaning of command 304 here is Mixer Low Kill for Deck A. Guy subsequently live-confirmed both the Low Kill input and the matching physical RELOOP-button LED OUT after correcting an initially wrong Traktor MIDI OUT assignment.

CMAD identities:

- IN row ID 250: `6813ad96c436c53f3cb2530e4f5db5e0a2152f1dfa7dd4f1132c8277f20306b3`;
- OUT row ID 252: `223956e770e972391b90233f8b67368fe68cd92a427b2dc6c13944da0971b804`.

## Deck B

Source file: `deck b add low kill Settings.tsi`

SHA-256: `1b4876018b12c18e1e0b21ee245045c46b64f21f31912b0bc20d4adb8e93d58a`

Structural audit:

- one Controller Manager device: `Jockey 3 Deck B`;
- Generic MIDI;
- 146 command rows;
- 144 binding rows;
- two references to `Reloop Jockey 3 ME (Bridge)` (In-Port and Out-Port).

Relative to the last qualified A/B Play/Pause-flash mapping checkpoint, the Low Kill additions are:

- IN: command `304` -> `Ch02.Note.F#-1`;
- OUT: command `304` -> `Ch02.Note.F#-1`.

CMAD identities:

- IN row ID 248: `335b99ebb04b469505d7cdae55f548688ef144d75f86d2befae52228904dc312`;
- OUT row ID 250: `96089ee4f5e04d0634ea5a5f065016baa0ea9dd485e4044a0a69b63e22d96df8`.

The user's intended meaning of command 304 here is Mixer Low Kill for Deck B. Guy subsequently live-confirmed both the Low Kill input and the matching physical RELOOP-button LED OUT after correcting an initially wrong Traktor MIDI OUT assignment.

## Additional Deck B discrepancy to preserve

The Deck B export also contains two Direction + Command ID + MIDI-binding rows that were not present in the last qualified checkpoint:

- OUT command `100` -> `Ch02.Note.F2`;
- OUT command `100` -> `Ch02.Note.F#2`.

Command 100 is the existing Play/Pause command in the project mappings. Guy confirmed these two rows are intentional existing mappings and should be retained. Their exact historical purpose should not be rewritten as part of the Low Kill change without separate evidence. The two previously documented unbound Deck B command-365 OUT records remain present, which is why the Deck B export has 146 commands but 144 bindings.

## Qualification result

Guy live-confirmed the Deck A/B Low Kill input and physical RELOOP-button LED OUT behavior.

For the v8.1.5 baseline:

- the Deck A export in this document became the current `mapping/Jockey_3_Deck_A.tsi`;
- Deck B subsequently received four additional live-confirmed Slot Retrigger mappings, so the **newer** Deck B export documented in `MAPPING_UPDATE_2026-10-20_DECK_B_SAMPLE_RETRIGGER.md` is the current `mapping/Jockey_3_Deck_B.tsi`.
