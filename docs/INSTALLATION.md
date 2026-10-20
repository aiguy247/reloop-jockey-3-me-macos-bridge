# Installation status

## Public repository scope

The current public baseline is **engine v8.0.8 + service/package v8.1.6 + mappings + documentation**.

GitHub Release v8.1.6 includes a ZIP upgrade package for the **original qualified Mac**.

It is not a universal fresh-machine installer.

## v8.1.6 upgrade package

The release package expects the original Mac's existing v8.1.5 environment and project repository path.

It deliberately keeps these already-qualified components unchanged:

- bridge engine v8.0.8;
- v8.1.5 bridge supervisor component;
- v8.1.5 root Spotlight guard.

It adds:

- `com.guy.reloopbridge.reducemotionguard`;
- production helper `~/Library/Application Support/ReloopBridge/reloop_reduce_motion_guard_v8_1_6`.

The installer automatically stops any remaining v8.1.6 test candidate and restores the existing v8.1.5 bridge under launchd before enabling the production helper.

## Full Disk Access requirement

The Reduce Motion helper changes the protected `com.apple.universalaccess` preference. On the qualified Sonoma system, the helper executable therefore needs a one-time Full Disk Access grant.

The installer compiles the helper to its final production path and tests permission **before** stopping the candidate or installed bridge service.

If permission is missing, it opens the Full Disk Access pane and exits safely. Add the exact path printed by the installer, enable it, and rerun the installer.

## Rollback

`service/rollback_to_v8_1_5_from_v8_1_6.sh` removes only the new v8.1.6 Reduce Motion helper/LaunchAgent.

It leaves the v8.0.8 engine and v8.1.5 Spotlight guard intact and ensures the v8.1.5 bridge LaunchAgent is loaded.

## Controlled manual source run

For engineering evaluation of the engine itself:

1. Build v8.0.8 using `docs/BUILD.md`.
2. Install/configure BlackHole 16ch separately.
3. Configure Traktor using `docs/TRAKTOR_SETUP.md`.
4. Connect the Reloop Jockey 3 ME.
5. Run the built engine in the foreground.

The foreground bridge engine itself does not require `sudo`.

## Future portable installer

A true fresh-machine installer should be a separate artifact. It should support installation when no previous bridge version exists, install BlackHole prerequisites clearly, install/uninstall both helpers safely, and receive its own qualification.
