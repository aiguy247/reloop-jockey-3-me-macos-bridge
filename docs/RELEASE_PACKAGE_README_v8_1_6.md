# Reloop Jockey 3 ME Bridge — v8.1.6 package

This package upgrades the **original qualified Mac** from service/package v8.1.5 to v8.1.6.

## What changes

v8.1.6 keeps the already-qualified components unchanged:

- bridge engine **v8.0.8**;
- bridge supervisor component **v8.1.5**;
- root Spotlight guard **v8.1.5**.

It adds one per-user LaunchAgent:

`com.guy.reloopbridge.reducemotionguard`

The new guard:

- detects the exact `Traktor` process;
- records the effective Reduce Motion state before Traktor;
- enables Reduce Motion while Traktor runs;
- restores the exact previous state after Traktor exits;
- refreshes macOS accessibility listeners without restarting Dock or Finder;
- never rearranges Spaces/windows by restarting Dock.

## Install

**Close Traktor first.**

From Terminal, in this unzipped package, run:

```bash
chmod +x install_v8_1_6.sh && ./install_v8_1_6.sh
```

The installer automatically stops any remaining v8.1.6 test candidate and restores the existing v8.1.5 bridge under launchd before enabling the production helper.

### One-time Full Disk Access

The production Reduce Motion helper uses the protected `com.apple.universalaccess` preference. macOS therefore requires Full Disk Access for the helper executable itself.

On the first run, if permission is not already present, the installer stops **before changing the running bridge** and opens Full Disk Access. Add/enable the exact path printed by the installer, then run the same installer again.

## Check status

```bash
chmod +x status_v8_1_6.sh && ./status_v8_1_6.sh
```

## Roll back to v8.1.5

Close Traktor, then run:

```bash
chmod +x rollback_to_v8_1_5.sh && ./rollback_to_v8_1_5.sh
```

Rollback removes only the v8.1.6 Reduce Motion helper/LaunchAgent. The v8.0.8 engine, v8.1.5 bridge component and v8.1.5 Spotlight guard remain intact.

macOS may retain an orphaned Full Disk Access entry for the removed helper. That entry is harmless and can be removed manually later if desired.

## Qualification scope

The accepted Reduce Motion behavior was live-tested on the original Mac in v8.1.6 candidate v5 on 20 October 2026. Production v8.1.6 promotes the same helper logic to stable paths and launchd supervision.

This package is **not a universal fresh-machine installer**. It expects the original qualified v8.1.5 environment and repository path used by this project.
