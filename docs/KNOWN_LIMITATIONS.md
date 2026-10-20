# Known limitations and open diagnostic questions

## Catastrophic USB transport failure

Earlier Phase 4 testing reproduced a rare catastrophic bidirectional USB failure in which playback and capture both returned zero bytes after approximately 200 ms waits and the controller required a physical power cycle.

v8.0.8 adds a bounded warm-recovery path for that failure class.

The accepted v8.0.8/v8.1.5/v8.1.6 normal-operation tests did **not** reproduce the catastrophic event, so the new recovery path remains unexercised on hardware.

## Earlier pops / UI glitches

Earlier stress tests produced audible pops, short interruptions and Traktor UI glitches, especially during macOS Spaces/window activity.

The final combined configuration no longer reproduces those symptoms in Guy's current testing. Do not rewrite the historical evidence as if one individual change were proven causal.

## Mix Recorder

Mix Recorder is **not a current known limitation**. Final testing with recording active and other applications open was clean according to Guy.

## Spotlight helper

The retained v8.1.5 helper controls Spotlight filesystem indexing through `mdutil`. It deliberately does not kill `mds`, `fileproviderd`, iCloud services or unrelated applications.

## Reduce Motion helper

The v8.1.6 helper requires a one-time Full Disk Access grant on the qualified Sonoma system.

Its accepted refresh path restarts the user preference/accessibility daemons `cfprefsd` and `universalaccessd`, then broadcasts `AXInterfaceReduceMotionStatusDidChange`.

It does **not** restart Dock or Finder. A Dock restart was explicitly rejected after testing showed it can disturb Spaces/window arrangement.

The helper is live-qualified only on the documented Sonoma 14.8.9 original Mac. Other macOS releases may handle the protected preference or notification differently.

## Broad Spotlight Privacy exclusions

The original qualified Mac uses broad exclusions under `~/Library` plus Traktor/project/recording paths. Those settings reduce Spotlight coverage and are recorded as the test-Mac configuration, not as a universal requirement.

## Analog-output proof

A clean Traktor recording cannot by itself prove clean Reloop analog output because the recorder is upstream of BlackHole -> bridge -> USB -> Reloop DAC.

## Platform scope

The live-tested OS evidence is macOS Sonoma 14.8.9 on Apple Silicon with the documented hardware/configuration. Other macOS releases, Intel Macs, firmware revisions and Jockey models are not claimed as qualified without hardware evidence.
