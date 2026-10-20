# Reloop Jockey 3 ME macOS Bridge

<table>
  <tr>
    <td>
      <img src="images/jockey-iii-me-dj-controller-top.jpg" width="450">
    </td>
    <td>
      <img src="images/jockey-iii-me-dj-controller-front.jpg" width="400"><br>
      <img src="images/jockey-iii-me-dj-controller-back.jpg" width="400">
    </td>
  </tr>
</table>

A reverse-engineered macOS audio + bidirectional MIDI bridge for the **Reloop Jockey 3 ME**, with live-tested Traktor Controller Manager mappings.

The bridge talks directly to the controller over USB, exposes a CoreMIDI endpoint to Traktor, and routes Traktor audio through BlackHole to the Jockey 3 ME at 48 kHz.

## Current live-tested baseline

| Component | Current version / setting |
|---|---|
| Bridge engine | **v8.0.8** |
| Service/package on the qualified Mac | **v8.1.5** |
| Traktor observed | **3.11.1.17** |
| Audio buffer | **384 samples** |
| Traktor Multi-Core Processing | **OFF** |
| Traktor mapping | **Five mapping-only Controller Manager exports** |
| Mapping checksums | `checksums/MAPPING_ONLY_SHA256SUMS.txt` |
| Tested OS | **macOS Sonoma 14.8.9, Apple Silicon** |
| Controller firmware observed | **1.0.6** |

Engine source SHA-256:

`4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`

The final configuration has been live-tested repeatedly on the physical controller. Guy reports smooth UI operation, normal mixing and recording, and no pops, crackling or audio dropouts in the final tests, including with Chrome and ChatGPT open.

See `docs/QUALIFIED_RUNTIME_SETTINGS_v8_1_5.md` and `docs/QUALIFICATION.md`.

## What the bridge does

- Sends 48 kHz audio to the Reloop Jockey 3 ME.
- Routes Traktor Master L/R from BlackHole channels 1/2.
- Routes Traktor Monitor L/R from BlackHole channels 4/3.
- Exposes `Reloop Jockey 3 ME (Bridge)` as a bidirectional CoreMIDI endpoint.
- Tracks the actual Tempo Master for Deck A/B.
- Flashes the actual master's trash LED with Beat Phase.
- Mirrors that Beat Phase to the actual master's Play/Pause LED.
- Restores normal Play/Pause LED state when master status moves away.
- v8.0.8 adds Phase 4 USB/MIDI diagnostics and a bounded recovery path for the catastrophic zero-byte USB failure class.

The bounded catastrophic-recovery path has **not yet been exercised in a reproduced catastrophic event**. Do not interpret the successful normal-operation qualification as proof of that specific recovery path.

## v8.1.5 Spotlight guard

The qualified Mac runs a separate root LaunchDaemon:

`com.guy.reloopbridge.spotlightguard`

It:

- detects when Traktor starts;
- remembers the previous Spotlight indexing state;
- disables filesystem indexing for the startup volume while Traktor runs;
- restores the previous state after Traktor exits;
- does not kill Spotlight, iCloud, FileProvider or application processes.

Guy verified the off/on transition repeatedly.

## Mapping scope

The five files under `mapping/` are **mapping-only exports**. They do not contain global Traktor preferences, audio settings, playlists, personal paths or unrelated controllers.

Current Deck A/B additions include:

- RELOOP button -> Mixer Low Kill, including matching LED OUT;
- Deck B XFA–XFD -> Deck D Remix slots 1–4 Slot Retrigger while Deck B remains selected.
- Deck A/B FX Unit 4 versus Browser/Load physical-button assignments swapped for improved playing accessibility.

The mappings also contain project workflow choices such as Favorites browsing, Recorder/Cruise assignments and Deck C/D behavior. Those choices are not requirements of the bridge itself.

See `docs/CURRENT_MAPPING_SPEC.md`.

## Repository layout

```text
src/        qualified and experimental Objective-C bridge source
service/    exact service/helper artifacts used on the original qualified Mac
mapping/    five current mapping-only Controller Manager exports
patches/    source-level bridge diffs
tools/      mapping and Phase 4 diagnostic tooling
docs/       setup, qualification, release and engineering documentation
checksums/  SHA-256 records
```

## Installation scope

This public repository is **source + mappings + engineering documentation**.

The current v8.1.5 service scripts record the exact installation used on the original test Mac, including rollback assumptions from its earlier v8.1.3 installation. They are **not presented as a universal one-click installer for arbitrary Macs**.

For source build and controlled testing, see:

- `docs/BUILD.md`
- `docs/INSTALLATION.md`
- `docs/TRAKTOR_SETUP.md`
- `docs/TESTING.md`

## Current release notes

See:

`docs/RELEASE_NOTES_v8_0_8_v8_1_5.md`

## Engineering rule

Structural validation, runtime evidence and live hardware qualification are kept separate. A successful compile or parser pass is not described as hardware qualification.

`main` is the current public baseline. Experimental work belongs on development branches until it has been accepted for promotion.

## Public status

The repository is public. The public-readiness record is in `docs/PUBLIC_READINESS.md`.

Licensed under the **MIT License**. See `LICENSE`.

![Reloop Jockey 3 ME](images/jockey-iii-me-dj-controller-front.jpg)
![Reloop Jockey 3 ME](images/jockey-iii-me-dj-controller-back.jpg)

