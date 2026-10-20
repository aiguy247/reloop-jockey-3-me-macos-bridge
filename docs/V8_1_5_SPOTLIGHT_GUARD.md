# Service/package v8.1.5 — v8.0.8 engine + automatic Spotlight indexing guard

Status: **installed and live-confirmed on the original qualified Mac.**

## Purpose

v8.1.5 runs the Phase 4 v8.0.8 engine as the normal per-user login service and adds a separate root LaunchDaemon that manages Spotlight filesystem indexing while Traktor is running.

The real-time audio/MIDI engine does not contain Spotlight control code.

## Runtime layout

### Bridge

- LaunchAgent label: `com.guy.reloopbridge`
- starts when Guy logs in;
- supervisor: `~/Library/Application Support/ReloopBridge/reloop_bridge_service_v8_1_5.sh`;
- engine: `~/Library/Application Support/ReloopBridge/reloop_bridge_engine_v8_0_8`;
- engine source SHA-256: `4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`;
- qualified-Mac arm64 binary SHA-256: `66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`.

### Spotlight guard

- LaunchDaemon label: `com.guy.reloopbridge.spotlightguard`;
- installed root-owned under `/Library`;
- starts at boot and remains supervised by launchd;
- detects the process named `Traktor`;
- polls every two seconds;
- uses `mdutil -i off /` while Traktor is running;
- uses `mdutil -i on /` after Traktor stops **only if indexing was enabled before Traktor started**;
- if indexing was already disabled, it remains disabled afterward;
- persistent state under `/var/db/com.guy.reloopbridge` lets a restarted helper preserve/restore state;
- never kills `mds`, `fileproviderd`, iCloud processes or browser/application processes.

This controls Spotlight **filesystem indexing activity**. It does not disable the Spotlight search UI or erase/rebuild the Spotlight database.

## Live verification

On 20 October 2026 the installed helper was observed with:

- Traktor closed -> Spotlight indexing enabled;
- Traktor started -> helper detected Traktor, saved the pre-Traktor state as enabled, and `mdutil -s /` reported **Indexing disabled**;
- Traktor closed -> the previous indexing state was restored.

Guy subsequently repeated the start/stop test several times and reports it works correctly.

## Safety / rollback

The original-Mac installer:

1. validates and builds v8.0.8 before stopping the installed bridge;
2. preserves the existing v8.1.3 LaunchAgent, v8.0.4 engine and v8.1.3 supervisor;
3. installs and verifies the Spotlight LaunchDaemon;
4. replaces the login bridge with v8.1.5;
5. automatically attempts to restore v8.1.3 if installation fails after replacement begins.

Manual rollback:

`service/rollback_to_v8_1_3_from_v8_1_5.sh`

The rollback copy is stored under:

`~/Library/Application Support/ReloopBridge/rollback_v8_1_3`

## Portability boundary

This exact installer is the upgrade path used on the original Mac and expects that machine's existing v8.1.3 runtime for rollback.

It is published as qualification provenance and current-source documentation, **not as a universal fresh-machine installer**.

## Qualification boundary

The Spotlight helper itself is live-confirmed.

Normal v8.0.8/v8.1.5 operation is also live-tested in the final configuration.

The v8.0.8 bounded catastrophic USB recovery path remains a separate unexercised subfeature until a catastrophic zero-byte failure actually triggers it.
