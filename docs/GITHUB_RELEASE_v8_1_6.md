# Reloop Jockey 3 ME macOS Bridge v8.1.6

**Automatic Traktor-time Reduce Motion control, without restarting Dock, on top of the existing live-tested v8.0.8/v8.1.5 bridge baseline.**

## Highlights

- **Bridge engine v8.0.8 — unchanged**
- **Service/package v8.1.6**
- Existing **v8.1.5 Spotlight guard retained unchanged**
- New per-user **Reduce Motion guard v8.1.6**
- Saves the pre-Traktor Reduce Motion state
- Enables Reduce Motion while Traktor runs
- Restores the exact previous state when Traktor exits
- Uses exact `Traktor` process detection
- Refreshes already-running macOS UI listeners without restarting Dock/Finder
- Includes a release ZIP for the original qualified Mac

## Why this release exists

Reduce Motion was part of the stable DJ configuration, but leaving it enabled all the time changes normal macOS desktop motion.

v8.1.6 makes that setting session-scoped: Traktor gets the performance-oriented setting automatically, while normal macOS use gets the user's previous setting back afterward.

## Live-tested behavior

The accepted v8.1.6 candidate v5 was live-tested on the original qualified Mac on 20 October 2026:

- Reduce Motion OFF before Traktor
- Traktor start -> Reduce Motion ON
- Traktor exit -> Reduce Motion OFF again
- desktop/Spaces animation restored immediately
- no Dock restart
- no Spaces/window rearrangement from the helper
- existing automatic Spotlight behavior remained independent

## Important macOS permission

The helper changes the protected `com.apple.universalaccess` Reduce Motion preference and needs a one-time **Full Disk Access** grant for its final production executable path.

The installer checks this before stopping the current candidate/service. If permission is missing, it opens the correct System Settings pane and exits without replacing the running bridge.

## Production delta

To minimize risk, v8.1.6 does **not** replace working components unnecessarily.

Unchanged:

- v8.0.8 audio/MIDI engine
- v8.1.5 bridge supervisor component
- v8.1.5 root Spotlight guard
- Traktor mappings
- audio routing
- Tempo Master LED behavior

Added:

- `com.guy.reloopbridge.reducemotionguard`
- production Reduce Motion helper and status/rollback tooling

## Release asset

`Reloop_Jockey_3_ME_Bridge_v8_1_6.zip`

The package is the upgrade path for the **original qualified Mac**. It is not presented as a universal fresh-machine installer.

The release workflow publishes a SHA-256 sidecar for the ZIP.

## Documentation

See:

- `docs/V8_1_6_REDUCE_MOTION_GUARD.md`
- `docs/RELEASE_NOTES_v8_0_8_v8_1_6.md`
- `docs/QUALIFIED_RUNTIME_SETTINGS_v8_1_6.md`
- `docs/INSTALLATION.md`
- `service/README.md`

---

Independent project by **Guy R. Hood**.  
Licensed under the MIT License.  
Not affiliated with Reloop, Native Instruments, or the BlackHole project.
