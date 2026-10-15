# Reloop Jockey 3 ME macOS Bridge

A reverse-engineered macOS audio + bidirectional MIDI bridge and custom Traktor mapping for the **Reloop Jockey 3 ME**.

The project exists because the controller's original macOS driver path is no longer a practical fit for the Apple-Silicon setup used here. The bridge talks directly to the controller over USB, exposes a CoreMIDI endpoint to Traktor, and routes Traktor audio through BlackHole to the Jockey 3 ME at 48 kHz.

## Current qualified baseline

| Component | Qualified version |
|---|---|
| Bridge engine | **v8.0.4** |
| Service/package | **v8.1.3** |
| Audio/USB foundation | **v8.0.2-qualified path, unchanged in v8.0.4** |
| Traktor mapping | **Five mapping-only Controller Manager exports** |
| Mapping checksums | `checksums/MAPPING_ONLY_SHA256SUMS.txt` |
| Tested OS | **macOS Sonoma 14.8.9, Apple Silicon** |
| Controller firmware observed | **1.0.6** |

This baseline was live-tested with the actual controller. The v8.0.4 change adds actual-Tempo-Master Play/Pause LED flashing while keeping the previously qualified audio/USB path unchanged.

## What it does

- 48 kHz audio output to the Reloop Jockey 3 ME.
- Traktor Master L/R via BlackHole channels 1/2.
- Traktor Monitor L/R via BlackHole channels 4/3.
- Bidirectional CoreMIDI endpoint: `Reloop Jockey 3 ME (Bridge)`.
- Actual Tempo Master tracking for Deck A/B.
- Beat-phase flashing on the actual master's trash LED.
- Matching Beat-phase flashing on the actual master's Play/Pause LED.
- Normal Play/Pause LED behavior retained on the non-master deck.
- Cached Play/Pause LED state restored when master status moves away.
- Custom Traktor mapping for the owner's A/B/C/D workflow.

## Repository layout

```text
src/        exact qualified Objective-C bridge source
service/    launchd installer, status and uninstall scripts
mapping/    five qualified mapping-only Controller Manager exports
patches/    source-level bridge diffs
dist/       release/download notes; binary ZIPs live in GitHub Releases
tools/      mapping audit tooling
docs/       architecture, qualification and mapping documentation
checksums/  SHA-256 records for qualified artifacts
```

## Qualified Traktor mappings

The repository contains five mapping-only Controller Manager exports: Deck A, Deck B, Mixer, Sample C and Sample D.

A full Traktor settings export is intentionally **not** stored here. Personal/global Traktor preferences, audio settings, paths, playlists and unrelated controller mappings are excluded.

Exact per-file SHA-256 values are recorded in `checksums/MAPPING_ONLY_SHA256SUMS.txt`.

## Distribution strategy

Source, scripts, mapping files, checksums and reproducible documentation belong in Git history. Downloadable installation ZIPs belong in **GitHub Releases**, so replacing a binary build does not permanently grow the repository history.

The qualified v8.1.3 installer ZIP has SHA-256:

`5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908`

The Release asset will be added after the public-readiness audit.

## Qualification evidence

A later near-four-hour v8.0.4/v8.1.3 session recorded:

- **0 BlackHole frames dropped**;
- **0 playback underrun frames**;
- one recovered **119.3 ms USB write stall**;
- the recovery/catch-up mechanism completed without a software-path underrun.

A separate full scan of the Traktor-recorded master WAVs found **0 high-confidence digital glitches** and no detected fault around the estimated time of that USB stall. This does **not** prove the downstream USB/DAC/analog output was glitch-free; it only strengthens the evidence that Traktor's recorded master remained clean.

See [`docs/QUALIFICATION.md`](docs/QUALIFICATION.md) and [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md).

## Engineering approach

This project deliberately separates:

1. structural/source validation;
2. software runtime evidence;
3. live hardware qualification.

A mapping or bridge change is not considered qualified merely because it compiles or passes a binary audit. Live controller behavior is the final acceptance test.

The project history also records failed approaches and why they failed. Those failures materially changed the working method: physical controls are not inferred from MIDI addresses when live evidence exists, unrelated Traktor rows are not cloned without auditing modifiers and interaction semantics, and the current mapping-only Controller Manager exports outrank generated predecessors.

## Status

`main` is reserved for qualified baselines. Experimental diagnostics and future changes should be developed on separate branches and promoted only after live testing.

The repository is being organized privately first. A license will be chosen before making it public.
