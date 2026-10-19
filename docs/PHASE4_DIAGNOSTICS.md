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


### Hama stress run — v8.0.7

Run label: `hama-stress-1`.

The user did some active DJing at the beginning, changed normal desktop application state during the run, then left the bridge/Traktor running while continuing normal work. This is a stress-condition run, not a controlled DJ-only qualification run.

Duration: approximately 3216 seconds (53 minutes 36 seconds).

One operational shared USB stall occurred at T+1043.506 s:

- playback synchronous write: 123.509 ms;
- playback completion gap: 123.542 ms;
- playback transfer: 4096 bytes, success, first attempt;
- capture synchronous read at the same event time: 116.760 ms;
- capture transfer: 4096 bytes, success;
- BlackHole callback age at playback completion: 0.504 ms;
- source ring depth reached approximately 153 ms;
- catch-up recovery ran for 41 seconds at a maximum temporary correction of 3000 ppm;
- no playback timeout, USB error or partial transfer occurred.

The automatic pre-USB PCM snapshot for this event contained active audio across all 480000 frames. Absolute peaks were 0.902928 / 0.937344 / 0.937344 / 0.902928. Offline waveform analysis of the uploaded ten-second Float32 WAV found no zero/silence gap, clipping, NaN/Inf samples, repeated adjacent frames, or abnormal sample transition at the event center. The center frame-to-frame maximum absolute delta was 0.013289, approximately the 50th percentile of all frame-to-frame deltas in the capture; the largest delta anywhere in the file was 0.527098. This supports source-PCM continuity across the stall position. It does not prove wall-clock continuity after USB submission, controller DAC continuity, or analog-output continuity.

End-of-run totals:

- BlackHole frames dropped: 0;
- playback underrun frames: 0;
- playback USB operational >50 ms events: 1;
- capture operational >50 ms events: 2, including the startup capture event;
- playback USB errors/timeouts/partial transfers: 0;
- capture USB timeouts/other errors: 0;
- diagnostic/PCM queue drops: 0;
- maximum ring depth: 7344 frames (153.0 ms);
- final ring depth: 1328 frames (27.7 ms).

The post-test system snapshot showed macOS 14.8.9 on AC power, no recorded thermal/performance warning, 38% system-wide memory free, and approximately 88 GiB free on the root filesystem. These observations do not prove that there was no transient scheduling or memory-pressure event at T+1043.506 s.

The Reloop remained enumerated as USB High Speed (480 Mb/s) through the Genesys Logic USB 2.1 hub function.

Interpretation after this run: the Hama setup can reproduce the same class of simultaneous playback/capture USB delay seen previously. The event occurred while BlackHole continued callback activity and while active pre-USB PCM was present. This makes a source-audio starvation explanation less likely, but it does not yet distinguish among hub behavior, host-controller/USB-stack scheduling, controller behavior, or another shared USB-path cause.


### UGREEN USB 2.0 stress run — v8.0.7

Run label: `ugreen-usb2-stress-1`.

The user stopped this run early because repeated audible pops and short sound cutouts were heard through the controller headphones. VLC had not yet been started. Traktor Mix Recorder was running during this test, which was not true of the preceding Hama stress run; this is therefore an important workload confound for direct hub-only attribution.

Approximate duration: 1484 seconds (24 minutes 44 seconds).

Playback slow-transfer events:

- T+723.869 s: 116.544 ms playback write and 116.753 ms capture read;
- T+1320.291 s: 122.052 ms playback write and 116.500 ms capture read;
- T+1321.825 s: 25.108 ms playback write and 25.424 ms capture read;
- T+1321.926 s: 101.211 ms playback write and 101.372 ms capture read;
- T+1382.121 s: 122.308 ms playback write and 114.481 ms capture read.

All transfers completed successfully. No USB timeout, other error, or partial transfer was reported. Four playback events exceeded 50 ms; five exceeded 20 ms. The events at approximately 22:00–22:02 form a tight cluster, followed by another >120 ms event approximately one minute later.

End-of-run totals:

- playback completion max gap: 122.317 ms;
- playback operational >20 ms events: 5;
- playback operational >50 ms events: 4;
- capture operational >20 ms events: 6;
- capture operational >50 ms events: 5, including startup;
- clock catch-up events: 2;
- catch-up active seconds: 175;
- BlackHole frames dropped: 0;
- playback underrun frames: 0;
- BlackHole callback maximum gap: 11.846 ms;
- maximum source ring depth: 13008 frames (271.0 ms);
- final source ring depth: 1056 frames (22.0 ms);
- diagnostic/PCM queue drops: 0.

Four automatic ten-second pre-USB PCM snapshots were saved for the >50 ms playback stalls and each reported all 480000 frames nonzero. Offline waveform analysis is still required before making continuity claims for those four source windows.

The UGREEN USB 2.0 path enumerated the Reloop at USB High Speed (480 Mb/s) behind a Genesys Logic USB 2.0 hub function with VID:PID 05e3:0608, version 60.70. The preceding Hama path used a different Genesys Logic USB 2.1 hub function, VID:PID 05e3:0610, version 6.56. This is a verified topology difference, not evidence by itself that the hub implementation caused the stalls.

Post-test state showed AC power, no recorded thermal/performance warning, 32% system-wide memory free, and approximately 89 GiB root-filesystem free.

Interpretation after this run: under this stress workload, UGREEN USB 2.0 produced substantially more shared playback/capture USB delays than the preceding Hama stress run and the user heard audible pops/cutouts. However, Traktor recording was an extra workload variable, so the current evidence is strong enough to reject UGREEN USB 2.0 as the preferred setup for now, but not sufficient to quantify a pure hub-only causal effect. A same-workload UGREEN USB 3.0-port test and a Hama run with Traktor recording enabled are the next useful comparisons.


### Traktor recording analysis from UGREEN USB 2.0 stress run

The user recorded a 20:17.877 stereo 48 kHz / 16-bit WAV in Traktor during the UGREEN USB 2.0 stress run. A local native-C analyzer scanned the full 233,832,492-byte file.

Global findings:

- peak absolute sample: 0.999969482;
- samples at or above full scale: 0;
- a 139.016-second exact-zero/repeated-frame run begins at recording time 17:58.861 and continues to the end of the file; this is a long silent tail and must not be treated as evidence of the earlier USB stalls;
- the largest 50 adjacent-frame jumps did not cluster around the approximate recording-relative times of the logged USB-stall events;
- the heuristic 10 ms RMS-drop list contains many musical-content candidates and is not by itself proof of digital dropouts.

Approximate time alignment, using the recording filename time (18:10:07) and the bridge run ending near 18:28:14 at T+1484, places the logged playback USB events roughly at recording times 5:27, 15:23–15:25, and 16:25. No top-50 sample discontinuity is reported at those approximate positions. Because the recording start and bridge monotonic clock were not explicitly synchronized and the Traktor recorder source mode was not independently captured, this is supporting evidence only, not final proof that Traktor's recorded source path was clean at every audible pop.


### UGREEN USB 3.0 physical-port stress run — v8.0.7

Run label: `ugreen-usb3-stress-1`.

The user stopped this run after hearing crackling/popping and short audio breaks. During the run the user identified a repeatable stressor: three-finger swiping between macOS desktops/spaces appeared to provoke substantially more audible popping/breaks. This observation is user-reported and does not by itself identify Chrome, memory pressure, WindowServer, GPU compositing, or another specific subsystem as the cause.

The run lasted approximately 342 seconds (5 minutes 42 seconds).

Operational USB events:

- startup playback write: 27.442 ms;
- startup capture read: 103.530 ms;
- T+341.355 s playback write: 113.618 ms, success;
- T+341.356 s capture read: 113.763 ms, success.

At the 113 ms event, BlackHole callback age was approximately 6.6–6.8 ms. End-of-run totals:

- BlackHole frames dropped: 0;
- playback underrun frames: 0;
- BlackHole callback maximum gap: 11.772 ms, no >20 ms callbacks;
- playback operational >20 ms events: 2 including startup;
- playback operational >50 ms events: 1;
- capture operational >20 ms events: 2;
- capture operational >50 ms events: 2 including startup;
- playback USB timeouts/errors/partial transfers: 0;
- queue probe maxima approximately 77 ms;
- maximum ring depth: 8080 frames (168.3 ms).

The Reloop remained USB High Speed / 480 Mb/s and system_profiler showed it behind the same Genesys Logic USB 2.0 hub function (VID:PID 05e3:0608, version 60.70) observed in the prior UGREEN USB 2.0 physical-port test. No separate USB3 hub function was exposed for the Reloop path. Therefore, for this USB-2 device, changing between the tested UGREEN USB 2.0 and USB 3.0 physical sockets did not produce evidence of a distinct USB-2 companion-hub path.

Post-test system state showed AC power, no recorded thermal/performance warning, 34% system-wide memory free, and approximately 91 GiB root-filesystem free.

Interpretation: the UGREEN USB 3.0 physical-port test reproduces the same shared playback/capture blocking pattern and does not provide evidence that this physical socket is materially better for the Reloop. The user's desktop-swipe observation creates a useful repeatable stress action for immediate A/B testing against the Hama without changing the rest of the workload.


### Hama Spaces-swipe stress run — v8.0.7

Run label: `hama-swipe-stress-1`.

The user stopped the run after approximately 151 seconds after audible popping began while DJing and repeatedly switching macOS Spaces/desktops with three-finger swipes. The user reported the Hama subjectively seemed less severe than the UGREEN runs, but was not clean. The Mac fan was audibly active/hot by this point in the work session.

Logged transport evidence:

- startup capture read: 83.727 ms;
- T+3.763 s playback write: 114.988 ms, success;
- T+3.763 s capture read: 115.111 ms, success;
- BlackHole age at the shared event: approximately 7.4–7.5 ms;
- playback operational >20 ms events: 1;
- playback operational >50 ms events: 1;
- capture operational >20 ms events: 2 including startup;
- capture operational >50 ms events: 2 including startup;
- playback USB timeouts/errors/partial transfers: 0;
- BlackHole frames dropped: 0;
- playback underrun frames: 0;
- BlackHole callback max gap: 11.879 ms;
- maximum ring depth: 8160 frames (170.0 ms);
- queue-probe maxima: if0 65.870 ms, if1 55.915 ms, recovery 53.804 ms.

The shared 115 ms event occurred at T+3.763 s, before the later user-reported Spaces-swipe popping. No additional >20 ms playback write was logged during the remainder of the run despite the later audible pops. Therefore the current >20 ms playback-write diagnostics do not explain every audible pop under Spaces-switching stress.

Post-test state reported 37% system-wide memory free and no recorded macOS thermal or performance warning. This does not support a claim of memory exhaustion or recorded thermal throttling, although it also does not measure instantaneous CPU/GPU/WindowServer saturation and does not contradict the user's report that the fan was running hard.

Topology remained different from UGREEN: Hama exposed a Genesys Logic USB2.1 hub function VID:PID 05e3:0610 version 6.56; the Reloop enumerated at 480 Mb/s. UGREEN exposed 05e3:0608 version 60.70.

Current operational conclusion: Hama remains the preferred hub of the two based on the combined longer-run and user-observed evidence, but it does not eliminate the fault. Spaces switching is now a repeatable stress action worth instrumenting more directly. Hub identity alone is not sufficient to explain all audible popping.


## Hama near-live restart test and v8.0.8 response — 2026-10-19

### Hama near-live v8.0.7 result

Run label: `hama-near-live-1`.

User-observed sequence:

- After a Mac restart, audible crackling/popping was still present initially while switching among windows/Spaces.
- After several minutes of DJing, the audible behavior appeared to settle; subsequent window/Space switching no longer obviously produced the same crackling during that period.
- Later, opening an HTML file launched Google Chrome. The user reports that **starting Chrome was the immediate trigger for the catastrophic failure**. This records the observed trigger; it does not identify the mechanism as memory, CPU, GPU, disk, WindowServer, USB host scheduling, or Chrome touching USB.
- Traktor itself remained running.
- The foreground v8.0.7 bridge stopped after its transport failure and the runner restored qualified v8.1.3.
- The Reloop remained frozen/unusable after v8.1.3 was restored. The user power-cycled only the Reloop; it then reconnected to Traktor and the controller could again stop/control playback.

Logged transport evidence at the catastrophic event:

- Immediately beforehand, normal playback writes were approximately 3.3 ms.
- First playback failure at T+860.208 s: 0/4096 bytes after 201.340 ms.
- Same-block retry at T+860.418 s: 0/4096 bytes after 208.252 ms.
- Capture failed in the same interval: 0-byte failures after 201.371 ms and 208.180 ms.
- v8.0.7 therefore exhausted its one-retry policy and deliberately marked playback fatal; this was not an unhandled process crash.
- BlackHole remained healthy through the run: zero dropped frames, zero playback underrun frames, callback maximum gap 10.817 ms.
- Post-test snapshot reported 71% system-wide memory free, zero swap-ins/outs for that boot, zero throttled pages, and no recorded thermal/performance warning. That evidence does not support a memory-exhaustion explanation for the event.

This is materially different from the earlier 100–123 ms successful stalls: the near-live event produced actual zero-byte USB I/O failures in both playback and capture and left the controller requiring a physical power cycle before the restored qualified service could use it again.

### v8.0.8 diagnostic/recovery candidate

Source:

`src/phase4/reloop_jockey3_bridge_v8_0_8_phase4_recovery_diagnostics_48k.m`

SHA-256:

`4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`

Status: **development candidate only; not qualified. Mac build gate PASSED on Guy's Apple-Silicon Mac on 2026-10-19.**

v8.0.8 keeps the v8.0.7 normal synchronous playback/capture architecture and adds two focused changes.

1. **Bounded synchronous transport recovery**
   - A single zero-byte playback failure still retries the exact same 4096-byte block once.
   - If the second attempt also returns zero bytes, playback requests one recovery instead of immediately terminating.
   - Recovery runs off the real-time playback/capture threads.
   - It pauses new synchronous requests, fences MIDI resubmission, asynchronously aborts playback/capture/MIDI pipes, waits for pending requests to drain, clears all three pipe stalls, and reasserts the vendor streaming status bit.
   - On a successful warm recovery it trims stale queued source audio, restarts MIDI drain, resumes capture/playback, and deliberately does **not** replay the stale failed playback block.
   - If the bounded recovery fails, the candidate still terminates and the foreground runner restores qualified v8.1.3. It does not silently loop recovery indefinitely.
   - No automatic USB-device `resetWithError:` is used. Apple documents that a device reset terminates the current IOUSBHostDevice and child services and requires creation of new framework clients, so that is a separate escalation design, not treated as a drop-in pipe recovery.

2. **Shorter-latency event diagnostics for Spaces/window-switch popping**
   - Playback and capture event snapshots now begin above 6 ms instead of only above 20 ms.
   - Playback write and completion-gap summaries add 4/6/8 ms buckets while retaining 10/20/50 ms counters and the existing >50 ms PCM trigger.
   - Capture summaries add 4/6/8 ms buckets while retaining the existing >20/>50 operational counters.
   - No diagnostic file I/O is added to the real-time threads.

The environment snapshot helper now also records a process snapshot and the previous two minutes of macOS unified-log entries containing USB-related messages. Standard macOS IORegistry/system_profiler data can show the hub topology, device state exposed by IOKit, speed, power data, and host-side USB messages. It does **not** provide known direct telemetry from inside the Genesys Logic hub controller itself; any deeper hub-internal visibility would require a vendor/debug interface that has not been established for these hubs.

### Next validation order

1. Build-gate v8.0.8 on Guy's Mac. Do not treat source/static review as a successful build.
2. Short Hama functional check: audio routing, controller/MIDI, Tempo Master LED behavior, Traktor recording.
3. Short controlled Spaces/window-switch reproduction attempt to see whether the new 6 ms events/buckets correlate with audible pops.
4. If the short checks are sound, run the realistic long Hama qualification-style session: recording on; normal DJing followed by Cruise/continuous playback; avoid deliberate Spaces switching; Wi-Fi/Bluetooth according to the chosen live-use baseline.
5. A future catastrophic zero-byte event is specifically useful: determine whether v8.0.8 warm recovery revives the existing controller session. If it cannot, the next recovery design must consider full device re-enumeration/reopen rather than pretending pipe clear/restart is sufficient.


### v8.0.8 Mac build gate — PASS

Guy ran the repository build gate on the project Mac after fast-forwarding `phase4-diagnostics`.

Result:

- build: **PASS**;
- source SHA-256: `4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`;
- output: Mach-O 64-bit executable arm64;
- built binary SHA-256: `66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`.

This satisfies the compile/build gate only. It does not qualify v8.0.8 behavior on hardware.
