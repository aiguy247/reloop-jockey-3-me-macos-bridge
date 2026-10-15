# Reloop Jockey 3 ME Bridge Service v8.1.3

## Engine

- Engine: **v8.0.4**
- Audio/USB path: **v8.0.2-qualified path unchanged**
- Base integrated master-flash engine: **v8.0.3**
- Traktor mapping change required: **none**

## New behavior

The already-qualified actual-Tempo-Master Beat Phase gate is extended to the Play/Pause LEDs:

- actual Master Deck A:
  - Deck A trash LED flashes with Beat Phase
  - Deck A Play/Pause LED flashes with the same Beat Phase
- actual Master Deck B:
  - Deck B trash LED flashes with Beat Phase
  - Deck B Play/Pause LED flashes with the same Beat Phase
- non-master deck:
  - Play/Pause LED keeps its normal Traktor Play/Pause behavior
- when master status moves away from a deck:
  - its cached normal Play/Pause LED state is restored immediately
- all unrelated MIDI OUT passes through unchanged

No TSI import is required for this bridge-only test.

Source:

`dev/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m`

SHA-256:

`344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`
