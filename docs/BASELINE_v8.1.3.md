# Qualified baseline — engine v8.0.4 / service v8.1.3

## Mapping source of truth

The mapping baseline is five individual Controller Manager exports taken from the live-qualified Traktor configuration:

- `mapping/Jockey_3_Deck_A.tsi`
- `mapping/Jockey_3_Deck_B.tsi`
- `mapping/Jockey_3_Mixer_Sektion.tsi`
- `mapping/Jockey_3_Sample_C.tsi`
- `mapping/Jockey_3_Sample_D.tsi`

A full Traktor settings export is intentionally excluded.

Per-file SHA-256 values are recorded in `checksums/MAPPING_ONLY_SHA256SUMS.txt`.

## Bridge baseline

- Engine: **v8.0.4**
- Service/package used for qualification: **v8.1.3**
- Engine source SHA-256: `344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`
- Private qualification ZIP SHA-256: `5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908`

The v8.1.3 ZIP is not committed to Git and is not being presented as the general public installer because its service wrapper contains local assumptions.

## Live-qualified visible behavior

When Deck A is actual Tempo Master:

- Deck A trash LED flashes with Beat Phase;
- Deck A Play/Pause LED flashes in the same rhythm;
- Deck B Play/Pause remains normal.

When Deck B is actual Tempo Master, the behavior mirrors to B.

AUTO/Cruise master changes follow actual Traktor state. When a deck ceases to be master, its normal Play/Pause LED state is restored.

## Mapping inventory

The repository contains exactly five Reloop Controller Manager devices: Deck A, Deck B, Mixer, Sample C and Sample D.

These files also contain workflow-specific choices that are not required by the audio bridge. See `TRAKTOR_SETUP.md`.

## Change policy

Future mapping work starts from the five current Controller Manager exports. Future bridge work preserves the v8.0.2-qualified audio foundation unless evidence requires reopening it.

A future portable service package is a new qualification item; changing the wrapper and then calling it the same qualified package would be inaccurate.
