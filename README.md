# Reloop Jockey 3 ME macOS Bridge

A reverse-engineered macOS audio + bidirectional MIDI bridge for the **Reloop Jockey 3 ME**, with qualified Traktor Controller Manager mappings.

The bridge talks directly to the controller over USB, exposes a CoreMIDI endpoint to Traktor, and routes Traktor audio through BlackHole to the Jockey 3 ME at 48 kHz.

## Current qualified baseline

| Component | Qualified version |
|---|---|
| Bridge engine | **v8.0.4** |
| Service/package used for qualification | **v8.1.3** |
| Audio/USB foundation | **v8.0.2-qualified path, unchanged in v8.0.4** |
| Traktor mapping | **Five mapping-only Controller Manager exports** |
| Mapping checksums | `checksums/MAPPING_ONLY_SHA256SUMS.txt` |
| Tested OS | **macOS Sonoma 14.8.9, Apple Silicon** |
| Controller firmware observed | **1.0.6** |

The physical controller was live-tested on this baseline. Qualification is intentionally limited to the environment above.

## What the bridge does

- Sends 48 kHz audio to the Reloop Jockey 3 ME.
- Routes Traktor Master L/R from BlackHole channels 1/2.
- Routes Traktor Monitor L/R from BlackHole channels 4/3.
- Exposes `Reloop Jockey 3 ME (Bridge)` as a bidirectional CoreMIDI endpoint.
- Tracks the actual Tempo Master for Deck A/B.
- Flashes the actual master's trash LED with Beat Phase.
- Mirrors that Beat Phase to the actual master's Play/Pause LED.
- Restores normal Play/Pause LED state when master status moves away.

## Mapping scope

The five files under `mapping/` are **mapping-only exports**. They do not contain global Traktor preferences, audio settings, playlists, personal paths, or unrelated controllers.

They do include the qualified project's workflow choices, such as Favorites browsing, Recorder/Cruise assignments and Deck C/D behavior. Those choices are **not required for the audio bridge itself** and should be treated as a qualified example configuration rather than a universal default.

See `docs/CURRENT_MAPPING_SPEC.md` and `docs/TRAKTOR_SETUP.md`.

## Repository layout

```text
src/        exact qualified Objective-C bridge source
service/    exact service scripts used for the private v8.1.3 qualification
mapping/    five qualified mapping-only Controller Manager exports
patches/    source-level bridge diffs
dist/       distribution status and artifact notes
tools/      mapping audit tooling
docs/       architecture, setup, qualification and engineering documentation
checksums/  SHA-256 records for qualified artifacts
```

## Installation scope

This repository is being published as **source + mappings + engineering documentation**, not as a general-purpose installer.

The scripts under `service/` are preserved because they are the exact service wrapper used during qualification. They contain local-project assumptions and are not presented as a reusable public installer.

For source build and controlled manual testing, see `docs/BUILD.md`, `docs/INSTALLATION.md` and `docs/TESTING.md`.

## Distribution strategy

Source, mapping files, documentation and checksums belong in Git history. Downloadable installation packages should be GitHub Release assets rather than accumulated binary ZIPs in Git history.

The exact v8.1.3 qualification ZIP has SHA-256:

`5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908`

That ZIP is **not being published as a general public installer** because its service wrapper contains machine/project-specific assumptions. No public installer package is currently planned.

## Qualification evidence

A near-four-hour v8.0.4/v8.1.3 session recorded:

- **0 BlackHole frames dropped**;
- **0 playback underrun frames**;
- one recovered **119.3 ms USB write stall**;
- recovery without a software-path underrun.

A separate scan of the Traktor-recorded master WAVs found **0 high-confidence digital glitches** and no detected fault around the estimated USB-stall time. Because the recording point is upstream of USB/DAC/analog output, this does not prove the analog output was glitch-free.

See `docs/QUALIFICATION.md` and `docs/KNOWN_LIMITATIONS.md`.

## Engineering rules

This project separates structural validation, runtime evidence and live hardware qualification. A build or mapping is not called qualified merely because it compiles or parses.

`main` is reserved for qualified baselines plus documentation about those baselines. Experimental bridge changes belong on separate branches and are promoted only after live testing.

## Public-readiness status

The repository remains private while the public-readiness checklist is completed. See `docs/PUBLIC_READINESS.md`.

Licensed under the **MIT License**. See `LICENSE`.
