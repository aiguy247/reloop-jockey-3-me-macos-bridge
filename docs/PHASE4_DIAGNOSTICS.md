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
