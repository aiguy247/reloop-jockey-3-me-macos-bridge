# Engineering history

This is the short public engineering history. Detailed private checkpoints remain outside the repository.

## v8.0.2 audio foundation

The audio/USB path that became the protected baseline introduced the qualified buffering, real-time playback/capture thread structure, adaptive BlackHole clock handling and transport recovery behavior used by later versions.

After long-run qualification, subsequent LED work deliberately avoided changing that audio path.

## v8.0.3

Added actual-Tempo-Master gating for the Deck A/B Beat Phase trash LEDs.

## v8.0.4 / service v8.1.3

Extended the master-state behavior so the actual master's Play/Pause LED flashes with the same Beat Phase. Normal Play/Pause output is cached while the deck is master and restored when it stops being master.

The audio/USB implementation remained unchanged from the v8.0.2-qualified foundation.

## Mapping work

The mapping evolved through live controller testing. Several important corrections led to the working rules in `LESSONS_LEARNED.md`: do not infer physical controls from MIDI addresses when live evidence exists, do not copy mapping rows without auditing modifiers/interaction semantics, and treat the current live-exported Controller Manager files as source truth.

## Long-run evidence

A later near-four-hour session exposed one real 119.3 ms USB write stall. Buffering/catch-up recovered without a logged software-path underrun. That event remains part of the evidence rather than being hidden by the overall pass result.

## Current direction

The qualified bridge remains untouched on `main`. Future diagnostics should improve observability—especially distinguishing normal MIDI read timeouts from real errors and correlating USB endpoint stalls—without silently changing the qualified audio algorithm.
