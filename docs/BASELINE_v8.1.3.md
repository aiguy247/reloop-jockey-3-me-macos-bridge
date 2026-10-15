# Qualified baseline — engine v8.0.4 / service v8.1.3

## Mapping source of truth

The public/reusable mapping baseline is five individual Controller Manager exports taken from the live-qualified Traktor configuration:

- `mapping/Jockey_3_Deck_A.tsi`
- `mapping/Jockey_3_Deck_B.tsi`
- `mapping/Jockey_3_Mixer_Sektion.tsi`
- `mapping/Jockey_3_Sample_C.tsi`
- `mapping/Jockey_3_Sample_D.tsi`

A full Traktor settings export is intentionally excluded because it contains global and user-specific settings unrelated to this controller project.

Per-file SHA-256 values are recorded in `checksums/MAPPING_ONLY_SHA256SUMS.txt`.

## Bridge baseline

- Engine: **v8.0.4**
- Service/package: **v8.1.3**
- Engine source SHA-256: `344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`
- Distribution ZIP SHA-256: `5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908`

The distribution ZIP is a GitHub Release asset, not a file kept in Git history.

## Live-qualified visible behavior

When Deck A is actual Tempo Master:

- Deck A trash LED flashes with Beat Phase;
- Deck A Play/Pause LED flashes in the same rhythm;
- Deck B Play/Pause remains normal.

When Deck B is actual Tempo Master, the behavior is mirrored to B.

When AUTO/Cruise changes the actual Tempo Master, both master indicators follow automatically. When a deck ceases to be master, its normal Play/Pause LED state is restored.

## Mapping inventory

The repository mapping baseline contains exactly five Reloop Controller Manager devices: Deck A, Deck B, Mixer, Sample C and Sample D.

The original full Traktor settings export is not part of the repository's rewritten reachable branch/tag history.

## Change policy

Future mapping work must start from the five exact current Controller Manager exports, not from generated predecessors. Future bridge work must preserve the v8.0.2-qualified audio foundation unless an observed regression requires reopening it.
