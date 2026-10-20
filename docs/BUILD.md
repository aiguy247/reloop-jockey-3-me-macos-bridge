# Build from source

## Current baseline build target

The current engine source is:

`src/phase4/reloop_jockey3_bridge_v8_0_8_phase4_recovery_diagnostics_48k.m`

SHA-256:

`4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`

The qualified-Mac arm64 build produced:

`66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`

## Requirements

- macOS with Apple command-line developer tools providing `clang`;
- Foundation, CoreAudio, CoreMIDI, IOKit and IOUSBHost frameworks;
- BlackHole 16ch for the tested Traktor route;
- Reloop Jockey 3 ME hardware for actual hardware testing.

The live-tested platform is documented in `COMPATIBILITY.md`.

## Recommended repository build

From the repository root:

```bash
/bin/bash tools/phase4/build_diagnostic_v8_0_8.sh
```

The script verifies the qualified parent/source checksums before compiling.

Expected output binary:

`build/reloop_bridge_engine_v8_0_8_phase4_recovery_diagnostics`

No `sudo` is required for compilation.

## Direct compile

The equivalent compiler framework set is:

```bash
/bin/mkdir -p build
/usr/bin/clang -fobjc-arc \
  -framework Foundation \
  -framework CoreAudio \
  -framework CoreMIDI \
  -framework IOKit \
  -framework IOUSBHost \
  src/phase4/reloop_jockey3_bridge_v8_0_8_phase4_recovery_diagnostics_48k.m \
  -o build/reloop_bridge_engine_v8_0_8
```

## Qualification boundary

A successful compile proves only that the source builds in that environment. It is not hardware qualification.

The current live-hardware evidence is documented in `QUALIFICATION.md`.
