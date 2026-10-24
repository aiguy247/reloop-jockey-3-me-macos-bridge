# Release notes — v8.1.7 event-driven DJ guards

**Release date:** 24 October 2026

## Baseline

- Bridge engine: **v8.0.8 — unchanged**
- Bridge supervisor: **v8.1.5 behavior — unchanged**
- Service/package release: **v8.1.7**
- Traktor lifecycle watcher: **v8.1.7 Candidate 7 promoted unchanged**
- Spotlight event helper: **v8.1.7 Candidate 7 promoted unchanged**
- Qualified engine binary SHA-256: `66355176b2bc4193e4a749c72a56ab48771b71ed91d1cb8f638fd924961618a4`
- Qualified release ZIP SHA-256: `8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d`

## What changed from v8.1.6

v8.1.6's Reduce Motion helper and the older Spotlight guard both relied on recurring process/state polling. v8.1.7 changes only that automation layer.

### Traktor detection

The user WatchGuard now subscribes to macOS `NSWorkspace` application launch and termination notifications. It performs one startup reconciliation for recovery but has no recurring Traktor process-detection timer.

### Spotlight

The root Spotlight helper now blocks on an authenticated Unix-domain socket. It runs `mdutil` only when Traktor enters or leaves the DJ session state, or during startup recovery.

### Reduce Motion

The lifecycle detection is event-driven, but the actual Reduce Motion write/refresh mechanism remains the live-proven v8.1.6 implementation. This deliberately avoids changing two variables at once.

## State safety

The new WatchGuard has a save barrier: both original states must be safely persisted before either DJ-state write is attempted.

For both Spotlight and Reduce Motion:

- already at DJ target -> no write;
- different from DJ target -> one write + verification;
- already at saved original on exit -> no write;
- different from saved original -> one restore + verification;
- failed restore -> recovery state remains on disk.

A helper restart while Traktor is running never invents an original state.

## Installation qualification

The Candidate 7 installer passed:

- qualified-engine provenance check;
- helper compilation;
- app-bundle signing verification;
- launchd plist validation;
- launchd cleanup and installation;
- Spotlight socket reachability;
- real Spotlight disable/restore protocol test;
- Full Disk Access verification from the actual WatchGuard LaunchAgent;
- reversible Reduce Motion change/restore test;
- obsolete-helper absence checks;
- idle process/resource snapshot.

## Live qualification

On 23 October 2026, Candidate 7 was used for an approximately one-hour DJ session on the original qualified Mac. The reported result was fully clean: no crackling, no popping, no audio dropouts and no observed controller/bridge failure.

The test was deliberately low-noise: no other applications were run during the DJ session, and Wi-Fi and Bluetooth were off.

## Promotion rule

The tested Candidate 7 ZIP is released **unchanged**. The GitHub release is named v8.1.7, but the package keeps its internal `8.1.7-candidate7` identity. This is intentional: physical qualification applies to the exact artifact, so no post-test rebuild was made solely to change labels.

## Remaining boundary

The engine's catastrophic zero-byte USB recovery path remains implemented but has still not been qualified by reproducing that catastrophic failure. v8.1.7 does not change that engine path.
