# Service/package v8.1.6 — automatic Reduce Motion guard

Status: **candidate behavior live-confirmed on the original qualified Mac; promoted to production packaging on 20 October 2026.**

## Purpose

Reduce Motion was part of the successful Traktor runtime configuration, but leaving it permanently enabled is undesirable for normal macOS use.

v8.1.6 automates that setting only around Traktor sessions.

## Runtime layout

Package v8.1.6 retains:

- engine v8.0.8;
- bridge LaunchAgent `com.guy.reloopbridge` using its unchanged v8.1.5 supervisor component;
- root Spotlight LaunchDaemon `com.guy.reloopbridge.spotlightguard` using its unchanged v8.1.5 helper.

It adds:

- per-user LaunchAgent: `com.guy.reloopbridge.reducemotionguard`;
- helper: `~/Library/Application Support/ReloopBridge/reloop_reduce_motion_guard_v8_1_6`;
- helper log: `~/Library/Logs/ReloopBridge/reduce_motion_guard_v8_1_6.log`;
- persistent pre-Traktor state: `~/Library/Application Support/ReloopBridge/reduce-motion-before-traktor-v8.1.6`.

## Behavior

On Traktor start:

- detect exact process name `Traktor` with `/usr/bin/pgrep -x Traktor`;
- record the effective Reduce Motion state if no state file exists;
- enable Reduce Motion when it is not already enabled;
- verify the effective state in a fresh child process.

While Traktor runs:

- poll every two seconds;
- keep Reduce Motion enabled if it is changed externally.

On Traktor exit:

- restore the exact saved pre-Traktor state;
- verify it in a fresh child process;
- remove the state file only after successful restore.

On helper restart with Traktor closed:

- recover/restore any retained state file before normal monitoring.

## macOS refresh mechanism

A raw preference write alone is insufficient for all already-running macOS UI processes.

The accepted implementation:

1. writes `com.apple.universalaccess` / `reduceMotion` through `CFPreferences`;
2. refreshes the user `cfprefsd` and `universalaccessd` processes;
3. posts distributed notification `AXInterfaceReduceMotionStatusDidChange` twice after short settling delays;
4. verifies the effective state from a fresh helper process.

This updates the setting without restarting Dock or Finder.

## Full Disk Access

The `com.apple.universalaccess` preference is protected on the qualified Sonoma system. The helper must therefore be granted Full Disk Access once.

The installer tests the final production executable path before it changes the running service state. If permission is missing, installation stops safely and opens the Full Disk Access pane.

## Live verification history

The accepted candidate v5 behavior was directly confirmed by Guy:

- start with Reduce Motion OFF;
- start Traktor -> Reduce Motion ON;
- quit Traktor -> Reduce Motion OFF;
- macOS desktop/Spaces motion returns immediately;
- no Dock restart or window/Spaces rearrangement.

The production source differs from accepted candidate v5 only in stable state/log paths and removal of candidate naming.
