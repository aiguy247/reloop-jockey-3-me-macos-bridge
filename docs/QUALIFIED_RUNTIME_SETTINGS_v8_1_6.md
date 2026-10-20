# Qualified runtime settings — v8.0.8 engine / v8.1.6 service package

**Date:** 20 October 2026

This records the current original-Mac runtime model after acceptance of the v8.1.6 Reduce Motion automation.

## Core Traktor / audio settings

- Traktor Pro observed: **3.11.1.17**
- Audio device: **BlackHole 16ch**
- Sample rate: **48 kHz**
- Audio buffer: **384 samples**
- Traktor-reported overall latency: approximately **8 ms**
- **Multi-Core Processing: OFF**

Bridge routing:

- BlackHole 1/2 -> Reloop Master L/R
- BlackHole 4/3 -> Reloop headphones L/R

CoreMIDI endpoint:

`Reloop Jockey 3 ME (Bridge)`

## macOS UI settings

- Touch Bar: **Expanded Control Strip**
- Automatic display brightness: **OFF**
- True Tone: **ON**
- Reduce Motion: **automatically ON while Traktor runs; previous state restored afterward**

v8.1.6 replaces the old operational requirement to leave Reduce Motion permanently ON.

## Automatic controls

### Spotlight

The unchanged v8.1.5 root helper `com.guy.reloopbridge.spotlightguard`:

- records the previous Spotlight indexing state when Traktor starts;
- disables filesystem indexing while Traktor runs;
- restores the saved state after Traktor exits.

### Reduce Motion

The new v8.1.6 user helper `com.guy.reloopbridge.reducemotionguard`:

- records the effective pre-Traktor Reduce Motion state;
- enables Reduce Motion while Traktor runs;
- restores the saved state after Traktor exits;
- refreshes UI listeners through the accessibility status-change notification;
- does not restart Dock or Finder.

The helper requires a one-time Full Disk Access grant on the qualified Sonoma system.

## Hardware/topology

- Mac: **MacBookPro17,1**
- Apple Silicon: **M1**
- Memory: **16 GB**
- macOS: **Sonoma 14.8.9**, build **23J631**
- Reloop Jockey 3 ME firmware observed: **1.0.6**
- Final preferred/tested hub: **Hama**
- Reloop USB link: **480 Mb/s USB High Speed**

## Qualification boundary

The automatic Reduce Motion behavior was live-confirmed in candidate v5 before production packaging. The engine, bridge supervisor, Spotlight guard and mappings are unchanged from the prior accepted baseline.

The v8.0.8 catastrophic zero-byte USB recovery path remains separately unexercised in a reproduced catastrophic event.
