# Qualified bridge source

The exact qualified engine source is:

`reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m`

SHA-256 of the uncompressed source:

`344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`

The repository preserves the exact bytes as an `.xz` artifact, and the same source is also contained in `dist/Reloop_Controller_Bridge_v8_1_3.zip`.

Restore:

```bash
xz -dk reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m.xz
shasum -a 256 reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m
```

Expected checksum:

`344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`
