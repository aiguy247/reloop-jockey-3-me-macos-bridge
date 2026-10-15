# Architecture

## Signal path

```text
Traktor Pro
   │
   │ audio: BlackHole 16ch @ 48 kHz
   ▼
Custom bridge engine
   │
   ├── Master L/R: BlackHole 1/2
   ├── Monitor L/R: BlackHole 4/3
   │
   ▼
macOS IOUSBHost
   │
   ▼
Reloop Jockey 3 ME USB audio interface
   │
   ├── Master analog output
   └── Headphone output
```

The same bridge exposes a bidirectional CoreMIDI endpoint named:

`Reloop Jockey 3 ME (Bridge)`

All five active Reloop Traktor Controller Manager devices use this endpoint for both input and output.

## Current engine

Qualified engine: **v8.0.4**

Original source SHA-256:

`344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`

The exact source is preserved losslessly in `src/` and also inside the qualified v8.1.3 distribution ZIP.

### Audio foundation

v8.0.4 intentionally retains the v8.0.2-qualified audio/USB path. The v8.0.3 → v8.0.4 change is confined to MIDI LED state handling, counters/comments and version strings.

Key audio behavior in the qualified path:

- direct USB initialization of the controller at 48 kHz;
- dedicated real-time playback and capture threads;
- synchronous 4096-byte USB playback writes;
- adaptive BlackHole clock correction;
- 32,768-frame audio ring buffer;
- fixed catch-up mode when a USB write exceeds 50 ms;
- one retry of the same audio block after a zero-byte playback transport failure.

## Tempo Master LED architecture

Traktor sends hidden actual-master state messages on Channel 16. The bridge consumes those messages, gates Deck A/B Beat Phase output to the deck that is actually Tempo Master, and mirrors the same phase to that deck's Play/Pause LED.

Ordinary Play/Pause LED states are cached. While a deck is actual master its ordinary Play LED output is suppressed; when it stops being master, the cached state is immediately restored.

This is a bridge-only feature. No additional TSI row is required for Play/Pause flashing.

## Service

Service/package v8.1.3 installs a per-user launchd service. It compiles the engine before replacing the running version, starts the bridge when the controller is detected, handles physical removal/reconnection, rotates logs, and backs off after three rapid failures until an unplug/replug.
