# Qualified baseline — engine v8.0.4 / service v8.1.3

## Source of truth

The current Traktor mapping source of truth is the exact full Controller Mappings export produced after the final live-qualified changes on 9 October 2026.

Raw filename:

`Reloop_CURRENT_QUALIFIED_BASELINE_AB-playpause-flash_2026-10-09.tsi`

SHA-256:

`4d0dc9f346507f86a6b084560638b8c5b5fa71b4a2c1af702d6961552046840e`

The repository stores those exact bytes as `mapping/...tsi.xz`. Decompression restores the original file byte-for-byte.

## Bridge baseline

- Engine: **v8.0.4**
- Service/package: **v8.1.3**
- Engine source SHA-256: `344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`
- Distribution ZIP SHA-256: `5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908`

## Live-qualified visible behavior

When Deck A is actual Tempo Master:

- Deck A trash LED flashes with Beat Phase;
- Deck A Play/Pause LED flashes in the same rhythm;
- Deck B Play/Pause remains normal.

When Deck B is actual Tempo Master, the behavior is mirrored to B.

When AUTO/Cruise changes the actual Tempo Master, both master indicators follow automatically. When a deck ceases to be master, its normal Play/Pause LED state is restored.

## Mapping inventory

The authoritative export contains **13 Controller Manager devices**, including five active Reloop devices. The Reloop devices contain **689 commands / 687 bindings** in total.

One deliberate file peculiarity must be preserved: Deck B has two command `365` OUT records with no MIDI binding. They exist in the exact user export and are not to be normalized away without a specific reason.

## Change policy

Future mapping work must start from the exact current export, not from generated predecessors. Future bridge work must preserve the v8.0.2-qualified audio foundation unless an observed regression requires reopening it.
