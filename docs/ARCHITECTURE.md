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

The bridge also exposes a bidirectional CoreMIDI endpoint:

`Reloop Jockey 3 ME (Bridge)`

The qualified five Reloop Controller Manager devices use this endpoint for input and output.

## Current engine

Qualified engine: **v8.0.4**

Source SHA-256:

`344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`

The exact source is preserved in `src/`.

### Audio foundation

v8.0.4 retains the v8.0.2-qualified audio/USB path. The v8.0.3 → v8.0.4 change is confined to MIDI LED state handling, counters/comments and version strings.

Key behavior:

- direct USB initialization at 48 kHz;
- dedicated real-time playback and capture threads;
- synchronous 4096-byte USB playback writes;
- adaptive BlackHole clock correction;
- 32,768-frame audio ring buffer;
- fixed catch-up mode when a USB write exceeds 50 ms;
- one retry of the same audio block after a zero-byte playback transport failure.

## Tempo Master LED architecture

Traktor sends hidden actual-master state messages on Channel 16. The bridge consumes those messages, gates Deck A/B Beat Phase output to the deck that is actually Tempo Master, and mirrors the same phase to that deck's Play/Pause LED.

Ordinary Play/Pause LED states are cached. While a deck is actual master its ordinary Play LED output is suppressed; when it stops being master, the cached state is restored.

## Mapping versus bridge

The included mappings contain both bridge-integration rows and project workflow choices.

The audio bridge does not depend on the user's Favorites, Recorder/Cruise, EQ or Deck C/D workflow choices. Those remain in the mapping files because they are part of the live-qualified configuration.

## Service wrapper

Service/package v8.1.3 used a per-user launchd service and was live-qualified in the original environment.

The exact scripts are retained under `service/` for provenance. They contain local path/identifier assumptions and are not the future general-purpose installer. See `service/README.md`.
