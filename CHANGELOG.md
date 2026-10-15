# Changelog

## v8.1.3 — qualified baseline

Bridge engine **v8.0.4**, service/package **v8.1.3**.

- Retains the v8.0.2-qualified audio/USB implementation.
- Retains actual-Tempo-Master trash LED Beat Phase gating.
- Mirrors actual-master Beat Phase to that deck's Play/Pause LED.
- Caches/suppresses ordinary Play LED output only while the deck is actual Tempo Master.
- Restores cached normal Play LED state when master status moves away.
- Includes the final user-exported Traktor mapping after stereo Master Output ring-meter edits.
- Live hardware qualification passed.

Earlier mapping failures, fixes and process lessons are documented in `docs/LESSONS_LEARNED.md`.
