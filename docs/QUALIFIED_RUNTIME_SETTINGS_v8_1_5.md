# Qualified runtime settings — v8.0.8 engine / v8.1.5 service

**Date:** 20 October 2026

This records the exact configuration Guy live-tested successfully on the original project Mac. It is evidence for this environment, not a claim that every setting is required on every Mac.

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

## Mix Recorder

Traktor Mix Recorder is **supported in the final tested configuration**.

Earlier Phase 4 A/B observations made recording a possible workload confound, but it was never proven to be the cause of the audible/UI problems.

In the final v8.1.5 configuration Guy tested with:

- Mix Recorder running;
- Google Chrome open;
- ChatGPT desktop app open;
- normal DJ mixing.

He reported:

- no UI glitches;
- no clicks or pops;
- no crackling;
- no audio dropouts.

Therefore, **do not document recording as a current known problem or as something that must be disabled**.

## macOS UI settings used in the successful configuration

- Touch Bar: **Expanded Control Strip**
- Automatic display brightness: **OFF**
- True Tone: **ON**
- Reduce Motion: **ON**

Guy reports enabling Reduce Motion materially helped the earlier UI-glitch behavior.

True Tone remained enabled during the successful tests. It is therefore **not a required disablement** for this baseline.

## Spotlight automatic control

Service/package v8.1.5 installs a separate root LaunchDaemon:

`com.guy.reloopbridge.spotlightguard`

Verified behavior:

1. when Traktor is not running, Spotlight indexing remains in its previous state;
2. when the `Traktor` process starts, the helper records the previous state and runs `mdutil -i off /`;
3. while Traktor is running, `mdutil -s /` reports indexing disabled;
4. when Traktor exits, the helper restores the saved previous state;
5. Guy repeated the start/stop test several times and reports it works correctly.

The helper does not kill `mds`, `fileproviderd`, iCloud services or application processes.

## Spotlight Privacy exclusions on the qualified Mac

Guy confirmed the following final exclusion set.

Broad user-Library exclusions:

- `~/Library/Application Support`
- `~/Library/Caches`
- `~/Library/Containers`
- `~/Library/Logs`
- `~/Library/Safari`

OpenAI shared containers:

- `~/Library/Group Containers/2DC432GLL2.com.openai.codex.notifications`
- `~/Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService`

Traktor/project/output locations:

- `~/Documents/Native Instruments`
- `~/Documents/A-GuyCodeProjects/Traktor-dev`
- `~/Downloads/traktor-recordings`

These are the original test-Mac choices. In particular, excluding broad Library folders is **not presented as a universal recommendation** because it reduces Spotlight coverage for those folders.

Shell-history files were deliberately not included as performance exclusions because their write volume is negligible relative to the workloads being investigated.

## Cloud/sync processes

A process snapshot found no standalone Google Drive, Dropbox, OneDrive, Box, pCloud or Mega client running.

macOS/iCloud services such as `fileproviderd` were left alone. v8.1.5 does not automatically terminate system sync services or unrelated applications.

## Hardware/topology used for the final successful tests

- Mac: **MacBookPro17,1**
- Apple Silicon: **M1**
- Memory: **16 GB**
- macOS: **Sonoma 14.8.9**, build **23J631**
- Reloop Jockey 3 ME firmware observed: **1.0.6**
- Final preferred/tested hub: **Hama**
- Reloop USB link: **480 Mb/s USB High Speed**
- Hama USB 2 path observed through Genesys Logic **05e3:0610**, version **6.56**

The Hama result is environment-specific evidence, not a universal claim that the hub model is required or superior on every system.
