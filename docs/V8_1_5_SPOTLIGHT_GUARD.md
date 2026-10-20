# Service/package v8.1.5 — v8.0.8 engine + automatic Spotlight indexing guard

Status: **development candidate; not qualified**.

## Purpose

v8.1.5 packages the Phase 4 v8.0.8 engine as the normal per-user login service and adds a separate root LaunchDaemon that manages Spotlight filesystem indexing while Traktor is running.

The real-time audio/MIDI engine does not contain Spotlight control code.

## Runtime layout

### Bridge

- LaunchAgent label: `com.guy.reloopbridge`
- starts when Guy logs in;
- supervisor: `~/Library/Application Support/ReloopBridge/reloop_bridge_service_v8_1_5.sh`;
- engine: `~/Library/Application Support/ReloopBridge/reloop_bridge_engine_v8_0_8`;
- engine source SHA-256: `4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`.

### Spotlight guard

- LaunchDaemon label: `com.guy.reloopbridge.spotlightguard`;
- installed root-owned under `/Library`;
- starts at boot and remains supervised by launchd;
- detects the process named `Traktor`;
- polls every two seconds;
- uses `mdutil -i off /` while Traktor is running;
- uses `mdutil -i on /` after Traktor stops **only if indexing was enabled before Traktor started**;
- if indexing was already disabled, it remains disabled afterward;
- persistent state under `/var/db/com.guy.reloopbridge` lets a restarted helper restore the previous state safely;
- it never kills `mds`, `fileproviderd`, iCloud processes, or browser/application processes.

This controls Spotlight **indexing activity**. It does not disable Spotlight search UI or erase/rebuild the Spotlight database.

## Safety / rollback

The installer:

1. validates and builds v8.0.8 before stopping the installed bridge;
2. preserves the current v8.1.3 LaunchAgent, v8.0.4 engine and v8.1.3 supervisor;
3. installs and verifies the Spotlight LaunchDaemon;
4. replaces the login bridge with v8.1.5;
5. automatically attempts to restore v8.1.3 if the installation fails after replacement begins.

Manual rollback:

`service/rollback_to_v8_1_3_from_v8_1_5.sh`

Rollback unloads the Spotlight guard. Its shutdown path restores Spotlight to the saved pre-Traktor state before the helper is removed.

## Qualification boundary

A successful install/build is not hardware qualification.

v8.0.8 has passed the short Hama functional test and subsequent long-run tests recorded under Phase 4, but its bounded USB recovery path remains separately qualified only when exercised and observed.
