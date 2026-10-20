# Changelog

## v8.1.6 — automatic Reduce Motion guard

Bridge engine **v8.0.8** unchanged; service/package **v8.1.6**.

- Retains the v8.1.5 bridge supervisor component and root Spotlight guard unchanged.
- Adds per-user LaunchAgent `com.guy.reloopbridge.reducemotionguard`.
- Saves the effective pre-Traktor Reduce Motion state.
- Enables Reduce Motion while `Traktor` is running.
- Restores the exact previous state after Traktor exits.
- Refreshes macOS accessibility listeners without restarting Dock or Finder.
- Uses fresh-process verification to avoid stale AppKit state reads.
- Requires a one-time Full Disk Access grant for the production helper on the qualified Sonoma Mac.
- Accepted candidate v5 behavior live-tested on the original qualified Mac.

## v8.1.5 — Spotlight guard / v8.0.8 engine baseline

Bridge engine **v8.0.8**, service/package **v8.1.5**.

- Adds the root `com.guy.reloopbridge.spotlightguard` LaunchDaemon.
- Disables Spotlight filesystem indexing while Traktor runs.
- Restores the previous indexing state afterward.
- Retains bridge control outside the real-time audio/MIDI engine.
- Adds Phase 4 diagnostics and bounded catastrophic USB recovery logic in engine v8.0.8.
- Normal operation and Spotlight behavior live-tested on the original Mac.

## v8.1.3 — qualified baseline

Bridge engine **v8.0.4**, service/package **v8.1.3**.

- Retains the v8.0.2-qualified audio/USB implementation.
- Retains actual-Tempo-Master trash LED Beat Phase gating.
- Mirrors actual-master Beat Phase to that deck's Play/Pause LED.
- Caches/suppresses ordinary Play LED output only while the deck is actual Tempo Master.
- Restores cached normal Play LED state when master status moves away.
- Includes five mapping-only Controller Manager exports from the final qualified Traktor mapping state after stereo Master Output ring-meter edits.
- Live hardware qualification passed.

Earlier mapping failures, fixes and process lessons are documented in `docs/LESSONS_LEARNED.md`.
