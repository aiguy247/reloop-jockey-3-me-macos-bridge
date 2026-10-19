# Phase 4 - diagnostic development

Status: **development candidate only; not qualified**.

The qualified baseline remains **engine v8.0.4 / service v8.1.3** on `main`.

## Scope

Phase 4 is limited to:

- separate development branch;
- improved USB/MIDI logging;
- better error-vs-timeout diagnostics;
- USB stall correlation;
- diagnostic PCM capture before USB submission;
- hub A/B testing;
- new candidate versions;
- nothing reaches `main` until qualified.

## First Phase 4 candidate

- Branch: `phase4-diagnostics`
- Engine candidate: **v8.0.6**
- Qualified parent source: `src/reloop_jockey3_bridge_v8_0_4_master_play_flash_48k.m`
- Diagnostic patch: `patches/phase4/ENGINE_DIFF_v8_0_4_to_v8_0_6.patch`
- Generated candidate source: `build/phase4-generated/reloop_jockey3_bridge_v8_0_6_phase4_diagnostics_48k.m`
- Parent behavior: qualified v8.0.4
- The old unverified v8.0.5/v8.1.4 handoff candidate is not reused as a release candidate.

The v8.0.6 candidate is generated from the exact qualified v8.0.4 source plus one checksum-locked patch. The build verifies the qualified source, patch and generated-source SHA-256 values before compiling.

The v8.0.6 candidate intentionally leaves the qualified audio routing, MIDI mapping behavior, USB retry decision and catch-up decision unchanged. Its new code is diagnostic instrumentation.

## What v8.0.6 records

### USB playback

For synchronous playback writes it keeps the existing duration and completion-gap counters, and adds:

- timeout count;
- other-error count;
- partial-transfer count;
- an event record for every operational write above 20 ms;
- correlation at the event with:
  - BlackHole callback age;
  - successful capture age;
  - successful MIDI-IN age;
  - USB interface 0 queue-probe age;
  - USB interface 1 queue-probe age;
  - recovery-queue probe age;
  - source ring depth;
  - USB attempt number and bytes transferred.

Slow-event records use a fixed-size single-producer/single-consumer queue. The real-time playback thread does not write diagnostic files. Queue overflow is counted explicitly.

### USB capture

For synchronous capture reads it adds:

- timeout count;
- other-error count;
- event records above 20 ms;
- correlation with the last successful playback, BlackHole callback and MIDI-IN completion.

### MIDI IN

The former combined error/timeout number is split into:

- expected completion timeouts;
- non-timeout completion errors;
- queue-submission failures.

Non-timeout completion errors are also put into a fixed-size event queue so multiple errors between status prints are not collapsed into one snapshot.

`kIOReturnTimeout` is the timeout classification. For synchronous IOUSBHost calls, an error is classified as that timeout only when the NSError domain is `IOUSBHostErrorDomain` and its code is `kIOReturnTimeout`.

Apple references:

- https://developer.apple.com/documentation/iousbhost/iousbhosterrordomain
- https://developer.apple.com/documentation/iokit/kioreturntimeout

## Pre-USB PCM capture

The candidate keeps a rolling 20-second copy of the four-channel Float32 source frames that the playback thread actually consumes immediately before conversion and USB packetization.

When an operational USB playback write exceeds 50 ms:

- a trigger is recorded without file I/O on the real-time thread;
- after another five seconds of source PCM have been consumed, the ordinary thread copies a ten-second window out of the rolling ring;
- the window contains five seconds before and five seconds after the event position in the consumed audio stream;
- it is saved as a four-channel, 48 kHz, Float32 WAV;
- a JSON sidecar records the event time, USB-write duration and capture point.

Output:

`~/Library/Logs/ReloopBridge/Phase4PCM`

This capture is deliberately **upstream of USB submission**. A clean capture can show that the PCM handed toward the USB path was clean; it cannot prove that the USB transfer, controller DAC or analog output was clean.

## macOS correlation

For a controlled diagnostic run, `tools/phase4/capture_usb_environment.sh` records the current Mac, power, USB topology, Reloop IORegistry entry, audio devices and service/process state. The foreground test harness also saves the candidate's complete console output under `~/Library/Logs/ReloopBridge/Phase4Runs` using the supplied run label.

Apple's current Audio System Trace template in Instruments is also useful for selected reproduction runs because it can correlate Core Audio jitter and overloads with thread scheduling, system calls, virtual-memory activity, system load and thermal state:

https://developer.apple.com/documentation/audiotoolbox/analyzing-audio-performance-with-instruments

Apple currently recommends Audio Workgroups for apps that create custom real-time audio threads. That is a relevant future scheduling experiment, but it is **not** part of v8.0.6. Changing scheduling while establishing the first diagnostic baseline would mix measurement changes with behavior changes.

https://developer.apple.com/documentation/audiotoolbox/understanding-audio-workgroups

## Hub A/B testing

Guy is currently using a Hama hub through a USB 3.2 Gen 1 connection and reports that it seems better than the previous UGREEN hub. That is an observation to test, not a conclusion about USB 3.2 versus USB 2.0/3.0.

The exact Hama and UGREEN hub SKUs/controller silicon have not been verified from the current evidence. Do not infer them from the port labels.

An older USB device negotiates its own supported USB speed behind a newer hub. A better result on the Hama could instead come from differences in hub controller silicon/firmware, signal integrity, power behavior, cable/topology, contention or host interaction. The test therefore records actual topology and power state rather than treating the printed USB generation as the cause.

First controlled comparison after the candidate passes a smoke test:

1. Keep the Mac, Mac port, controller cable, Traktor settings, sample rate and workload unchanged.
2. Capture an environment snapshot for each run.
3. Run **Hama -> UGREEN -> Hama** so an order/time effect is less likely to be mistaken for a hub effect.
4. Compare slow playback/capture events, real errors, timeouts, ring depth, catch-up events, dropped frames, underruns and any saved PCM windows.
5. Do not declare a hub winner from one short run.

## Qualification gates

1. Source checksum and macOS compile pass.
2. Foreground hardware smoke test passes.
3. Diagnostic counters and PCM trigger path behave as intended.
4. Controlled hub A/B evidence is collected.
5. Long-run test passes on the selected setup.
6. Only then consider promotion. `main` is not changed merely because the candidate compiles or runs.


## Phase 4 evidence collected on 19 October 2026

### Hama loaded-desktop run — v8.0.6

Observed user workload included Traktor plus multiple Chrome windows, ChatGPT, BBEdit, Notes, ExpressVPN open but disconnected, and two Terminal windows. This is therefore a loaded-desktop stress condition, not the controlled hub-comparison baseline.

Run duration was approximately 21 minutes 58 seconds. One operational shared USB stall occurred at T+150.881 s:

- playback synchronous write: 113.132 ms, 4096 bytes, success;
- capture synchronous read: 113.267 ms, 4096 bytes, success;
- BlackHole callback age at playback completion: 6.188 ms;
- playback/capture both recovered;
- BlackHole drops: 0;
- playback underrun frames: 0;
- user reported no audible or controller problem during the session.

A ten-second PCM diagnostic file was saved for that event, but every sample in all four channels was zero. That capture therefore cannot establish PCM integrity for active music at the stall. It is retained as evidence of silence at the pre-USB capture point around that event, not as proof of a broken capture mechanism.

Live USB topology showed the Reloop enumerating at 480 Mb/s USB High Speed behind a Genesys Logic USB 2.1 hub function. This does not identify the exact retail Hama model and does not by itself establish the cause of the stall.

### Hama PCM-verification run — v8.0.7

v8.0.7 adds only diagnostic verification on top of v8.0.6:

- SIGUSR1 can request one manual five-second-pre / five-second-post PCM snapshot;
- the snapshot metadata and console report nonzero-frame count and per-channel absolute peaks;
- previous PCM files are archived before a new run;
- Control-C logging preserves the engine shutdown summary;
- environment snapshots include additional power, thermal and memory-pressure evidence.

During a short music-playing verification run:

- manual snapshot: 480000 / 480000 frames nonzero;
- channel absolute peaks: 0.822040 / 0.788429 / 0.788429 / 0.822040;
- playback max synchronous write: 3.110 ms;
- playback completion max gap: 3.143 ms;
- BlackHole callback max gap: 10.965 ms;
- BlackHole frames dropped: 0;
- playback underrun frames: 0;
- playback USB errors/timeouts/partial transfers: 0;
- one startup capture read reached 82.483 ms and completed successfully;
- queue-heartbeat probes reached approximately 84 ms while actual playback remained normal.

This verifies that the pre-USB PCM capture path works with active Traktor audio. Therefore the all-zero v8.0.6 event file should be treated as an all-silent source window at that capture point, not as evidence that the PCM logger is generally broken.

The queue-heartbeat probes are GCD timers on the IOUSBHost interface service queues and the recovery queue. Their latency can increase independently of the dedicated real-time playback/capture threads. A large queue-probe gap alone is therefore not equivalent to a USB audio-transfer stall.
