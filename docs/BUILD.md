# Build from source

## Qualified build target

The current qualified engine source is:

`src/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m`

SHA-256:

`344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`

## Requirements

- macOS with Apple command-line developer tools providing `clang`;
- Foundation, CoreAudio, CoreMIDI, IOKit and IOUSBHost frameworks;
- BlackHole 16ch for the qualified Traktor audio route;
- Reloop Jockey 3 ME hardware for actual hardware testing.

The only live-qualified platform is documented in `COMPATIBILITY.md`.

## Compile

From the repository root:

```bash
/bin/mkdir -p build
/usr/bin/clang -fobjc-arc \
  -framework Foundation \
  -framework CoreAudio \
  -framework CoreMIDI \
  -framework IOKit \
  -framework IOUSBHost \
  src/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m \
  -o build/reloop_bridge_engine_v8_0_4
```

No `sudo` is required for compilation.

## Verify the source first

```bash
/usr/bin/shasum -a 256 src/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m
```

Compare the result with `checksums/SHA256SUMS.txt`.

A successful compile is structural evidence only. It is not hardware qualification.
