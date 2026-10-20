# Known limitations and open diagnostic questions

## Catastrophic USB transport failure

Earlier Phase 4 testing reproduced a rare catastrophic bidirectional USB failure in which playback and capture both returned zero bytes after approximately 200 ms waits and the controller required a physical power cycle.

v8.0.8 adds a bounded warm-recovery path for that failure class.

The final accepted v8.0.8/v8.1.5 tests did **not** reproduce the catastrophic event, so the new recovery path was never exercised.

Therefore:

- normal v8.0.8 operation is live-tested;
- the catastrophic recovery algorithm is structurally implemented;
- its ability to recover the physical controller from that exact failure remains unproven.

## Earlier pops / UI glitches

Earlier stress tests produced audible pops, short interruptions and Traktor UI glitches, especially during macOS Spaces/window activity.

Some of those audible problems occurred with:

- zero BlackHole frame drops;
- zero playback underruns;
- zero USB transfer errors.

That means the measured bridge USB/buffer counters did not explain every audible symptom.

The final combined configuration — including Multi-Core Processing OFF, 384-sample buffer, Spotlight controls and Reduce Motion — no longer reproduces those symptoms in Guy's current testing.

Do not rewrite the historical evidence as if one individual change were proven causal.

## Mix Recorder

Mix Recorder is **not a current known limitation**.

It was an extra workload variable in earlier comparisons, but final testing with recording active, Chrome open and ChatGPT open was clean according to Guy.

## Spotlight helper

The v8.1.5 helper controls Spotlight filesystem indexing through `mdutil`.

It does not disable all macOS metadata/search-related services and deliberately does not kill `mds`, `fileproviderd`, iCloud services or unrelated applications.

## Broad Spotlight Privacy exclusions

The original qualified Mac uses broad exclusions under `~/Library` plus Traktor/project/recording paths.

Those settings reduce Spotlight coverage and are recorded as the test-Mac configuration, not as a universal requirement for every user.

## Analog-output proof

A clean Traktor recording cannot by itself prove clean Reloop analog output because the recorder is upstream of BlackHole -> bridge -> USB -> Reloop DAC.

The final acceptance includes Guy's direct listening/use observation, but laboratory end-to-end proof would require independently recording the physical Reloop analog output.

## Platform scope

The live-tested OS evidence is macOS Sonoma 14.8.9 on Apple Silicon with the hardware/configuration documented in `COMPATIBILITY.md`.

Other macOS releases, Intel Macs, other firmware revisions and other Jockey models may work, but are not claimed as qualified without hardware evidence.
