# Release notes — engine v8.0.8 / service v8.1.5

**Current baseline date:** 20 October 2026

## Current baseline

- Bridge engine: **v8.0.8**
- Service/package on the qualified Mac: **v8.1.5**
- Engine source SHA-256: `4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`
- Qualified-Mac arm64 binary SHA-256: `66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`
- Traktor mapping: five mapping-only Controller Manager exports, with updated Deck A/B mappings
- Tested OS: macOS Sonoma 14.8.9 on Apple Silicon
- Controller firmware observed: 1.0.6

## What changed from v8.0.4 / v8.1.3

### Engine

v8.0.8 retains the v8.0.4 audio routing and MIDI/Tempo-Master behavior and adds:

- separate short-latency diagnostics;
- clearer timeout/error accounting;
- bounded recovery logic for the catastrophic zero-byte USB transport failure class;
- diagnostic support used during Phase 4 testing.

The bounded catastrophic-recovery path remains **unexercised in a reproduced catastrophic event**. Do not claim that path is hardware-qualified merely because normal operation is qualified.

### Service

v8.1.5:

- starts the v8.0.8 bridge at login;
- adds the root `com.guy.reloopbridge.spotlightguard` LaunchDaemon;
- disables Spotlight filesystem indexing while Traktor runs;
- restores the pre-Traktor indexing state after Traktor exits;
- keeps Spotlight control outside the real-time audio/MIDI engine;
- preserves the previous v8.1.3 runtime on the original Mac for rollback.

The service scripts in this repository document the original qualified installation. They are not presented as a universal one-click installer for other Macs.

### Mappings

Deck A and B now include the live-confirmed physical RELOOP-button Low Kill input and LED output.

Deck B also adds four live-confirmed `Slot Retrigger` inputs so XFA–XFD trigger Deck D Remix slots 1–4 while Deck B remains selected.

See:

- `docs/CURRENT_MAPPING_SPEC.md`
- `docs/MAPPING_UPDATE_2026-10-19_LOW_KILL.md`
- `docs/MAPPING_UPDATE_2026-10-20_DECK_B_SAMPLE_RETRIGGER.md`

## Final live result

With the final configuration Guy reports multiple successful tests with:

- Multi-Core Processing off;
- 384-sample audio buffer;
- automatic Spotlight guard active;
- Reduce Motion enabled;
- Mix Recorder running;
- Chrome open;
- ChatGPT open;
- normal mixing and controller use.

Observed by Guy:

- smooth Traktor UI;
- no UI glitches;
- no pops/clicks/crackling;
- no sound drops;
- normal recording;
- working automatic Spotlight off/on behavior.

The evidence supports the current baseline as Guy's de facto running configuration.

It does **not** prove which individual setting fixed the earlier problem because several changes were combined, and it does not prove the v8.0.8 catastrophic USB recovery path until that path is actually exercised.
