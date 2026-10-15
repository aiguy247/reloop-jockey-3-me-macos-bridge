# Qualification and test evidence

## Qualification model

The project uses three evidence levels:

1. **Structural validation** — source/mapping structure is internally consistent.
2. **Runtime evidence** — logs show how the bridge behaved under load.
3. **Live hardware qualification** — the physical controller is tested in Traktor.

Live hardware is the final acceptance gate for controller behavior.

## v8.0.4 / v8.1.3 live qualification

The actual-Tempo-Master trash LED and Play/Pause LED behavior was tested on the physical Reloop Jockey 3 ME and reported working as intended.

The five mapping-only Controller Manager exports in `mapping/` were taken from that final qualified Traktor mapping state.

The v8.1.3 service wrapper was qualified only in the original local environment. Its local path/label assumptions mean it is not yet a reusable public installer.

## Near-four-hour session

A later session using v8.0.4 / v8.1.3 ran from 20:46:03 until physical controller removal at 00:31:37.

Key shutdown counters:

- BlackHole frames dropped: **0**
- Playback underrun frames: **0**
- CoreMIDI OUT dropped: **0**
- One clock catch-up event
- Maximum playback completion gap: **119.349 ms**
- Maximum synchronous USB write: **119.321 ms**

The 119.3 ms USB write was a real transport stall. Buffering/catch-up recovered without a software-path underrun. This is a successful recovery result, not proof that analog output was acoustically perfect during the event.

## Traktor master-recording analysis

The associated Traktor master recordings were scanned locally across **3:43:15.371** of stereo PCM:

- 642,977,792 stereo frames processed;
- zero read/decode errors;
- **0 high-confidence digital glitches**;
- two very short medium-confidence click-like review leads, neither established as a Traktor fault;
- no medium/high event within ±30 seconds of the filename-derived USB-stall position;
- no detectable discontinuity at Traktor's WAV split;
- no sustained digital clipping detected.

The recording point is upstream of BlackHole → bridge → USB → Reloop DAC, so it cannot prove downstream playback quality.
