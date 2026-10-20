# Mapping update — Deck B XFA–XFD trigger Deck D Remix slots — 2026-10-20

Status: **live-confirmed current Deck B mapping state for the v8.1.5 baseline.**

Guy added four `Slot Retrigger` inputs to the Deck B Controller Manager device so Deck D Remix/Sample slots 1–4 can be triggered while Deck B remains selected on the physical controller.

## Source export

Source file supplied by Guy:

`deck b add slot retrigger to play deck d samples Settings.tsi`

SHA-256:

`d1871172d5a1b4a43b250476f925509e658378ff1815d31d0654ed86de7955ea`

Structural audit:

- one Controller Manager device: `Jockey 3 Deck B`;
- Generic MIDI;
- **150 command rows**;
- **148 binding rows**;
- two references to `Reloop Jockey 3 ME (Bridge)` (In-Port and Out-Port).

## Exact delta from the immediately previous Deck B Low Kill export

Previous Deck B export:

`deck b add low kill Settings.tsi`

SHA-256:

`1b4876018b12c18e1e0b21ee245045c46b64f21f31912b0bc20d4adb8e93d58a`

Binary Controller Manager comparison shows exactly **four command rows and four MIDI-binding rows added, with no command or binding rows removed**.

All four new rows use Traktor command ID **260** (`0x104`), shown in Traktor as **Slot Retrigger**, with Interaction Mode **Hold**.

The live-confirmed assignments are:

| Physical Deck B control | Target | MIDI binding in export |
|---|---|---|
| XFA | Deck D Remix slot 1 | `Ch02.Note.G0` |
| XFB | Deck D Remix slot 2 | `Ch02.Note.G#0` |
| XFC | Deck D Remix slot 3 | `Ch02.Note.A0` |
| XFD | Deck D Remix slot 4 | `Ch01.Note.A#0` |

The fourth binding is intentionally recorded exactly as exported: **channel 1** for XFD. Do not normalize it to channel 2 merely because the other three are channel 2; Guy reports the four-button behavior works correctly on the physical controller.

## Preserved Deck B state

The export retains the previously live-confirmed Deck B RELOOP-button Low Kill input/LED OUT mapping:

- command `304` IN -> `Ch02.Note.F#-1`;
- command `304` OUT -> `Ch02.Note.F#-1`.

It also retains the two intentional existing Play/Pause command `100` OUT bindings:

- `Ch02.Note.F2`;
- `Ch02.Note.F#2`.

The two known unbound Deck B command-365 OUT records also remain, hence 150 commands / 148 bindings.

## Live result

Guy reports all four XFA–XFD sample triggers work correctly and allow Deck D slots 1–4 to be played without switching the controller away from Deck B.

The supplied export is therefore the current Deck B mapping artifact for the v8.1.5 baseline.
