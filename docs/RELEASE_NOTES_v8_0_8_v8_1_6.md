# Release notes — engine v8.0.8 / service package v8.1.6

**Release date:** 20 October 2026

## Baseline

- Bridge engine: **v8.0.8** — unchanged
- Bridge supervisor component: **v8.1.5** — unchanged
- Service/package: **v8.1.6**
- Spotlight guard component: **v8.1.5** — unchanged
- New Reduce Motion guard: **v8.1.6**
- Engine source SHA-256: `4fed39df7a9b2a792ceca42c68bf8d5c278e96505717888998411563b6e00537`
- Qualified-Mac arm64 engine SHA-256: `66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`

## What changed from v8.1.5

v8.1.6 adds automatic macOS **Reduce Motion** management around Traktor sessions.

The per-user helper:

1. detects `Traktor` using exact process-name matching;
2. reads and saves the effective pre-Traktor Reduce Motion state;
3. enables Reduce Motion when Traktor starts if necessary;
4. keeps Reduce Motion enabled while Traktor remains running;
5. restores the saved pre-Traktor state after Traktor exits;
6. keeps a state file so an unexpected helper restart can recover correctly.

The implementation writes the protected `com.apple.universalaccess` `reduceMotion` preference, refreshes `cfprefsd` and `universalaccessd`, then posts `AXInterfaceReduceMotionStatusDidChange` so already-running UI processes re-read the setting.

**Dock is not restarted.** This was an explicit design requirement after testing showed that restarting Dock can disturb Spaces/window arrangement.

## Full Disk Access

macOS protects the `com.apple.universalaccess` domain. The production helper therefore requires a one-time Full Disk Access grant for:

`~/Library/Application Support/ReloopBridge/reloop_reduce_motion_guard_v8_1_6`

The installer verifies this permission before stopping any running candidate or installed bridge service. Its permission check rewrites the current state to itself, so it does not intentionally flash Reduce Motion on/off.

## Live test evidence

Candidate v5, containing the same Reduce Motion control logic, was live-tested on the original qualified Mac on 20 October 2026.

Observed behavior:

- Reduce Motion OFF before Traktor;
- Traktor starts -> Reduce Motion becomes ON;
- Traktor exits -> Reduce Motion returns to OFF;
- desktop/Spaces motion immediately returns to normal after restore;
- no Dock restart is required;
- the existing automatic Spotlight guard continues to work independently.

Earlier candidates established several rejected approaches:

- `com.apple.Accessibility ReduceMotionEnabled` changed a stored value but not the effective setting;
- direct `com.apple.universalaccess` writes require Full Disk Access;
- a long-lived AppKit process can observe stale state, so verification uses a fresh child process;
- `NSWorkspace.runningApplications` did not reliably detect Traktor in this helper, so production uses `pgrep -x Traktor`;
- restoring only the preference without notifying UI listeners left Dock behavior stale;
- restarting Dock fixed that stale state but was rejected because it can disturb Spaces/windows.

## Unchanged components

v8.1.6 deliberately does **not** change:

- v8.0.8 audio/MIDI engine code;
- BlackHole -> Reloop routing;
- Tempo Master LED behavior;
- Traktor mappings;
- v8.1.5 bridge supervisor behavior;
- v8.1.5 root Spotlight helper behavior.

This minimizes the production delta to the newly qualified Reduce Motion guard.

## Remaining boundary

The v8.0.8 catastrophic zero-byte USB recovery path remains implemented but unexercised in a reproduced catastrophic event. v8.1.6 does not change that boundary.
