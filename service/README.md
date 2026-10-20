# Service scripts — qualification provenance

This directory contains historical service artifacts plus the current v8.1.6 Reduce Motion helper/upgrade tooling used for the original qualified Mac.

They are **qualification provenance**, not a universal public installer.

## Current original-Mac runtime

Current service/package:

**v8.1.6**

Current engine:

**v8.0.8**

Existing bridge LaunchAgent:

`com.guy.reloopbridge`

Existing Spotlight LaunchDaemon:

`com.guy.reloopbridge.spotlightguard`

New v8.1.6 Reduce Motion LaunchAgent:

`com.guy.reloopbridge.reducemotionguard`

Current v8.1.6 files:

- `install_or_upgrade_reloop_bridge_service_v8_1_6.sh`
- `reloop_bridge_service_status_v8_1_6.sh`
- `reloop_reduce_motion_guard_v8_1_6.m`
- `rollback_to_v8_1_5_from_v8_1_6.sh`

Retained unchanged components:

- `reloop_spotlight_guard_v8_1_5.sh`
- installed v8.1.5 bridge supervisor
- engine v8.0.8

The Reduce Motion behavior promoted to v8.1.6 was live-tested as candidate v5 on the original Mac before production promotion.

## v8.1.6 portability boundary

The v8.1.6 upgrade script is deliberately narrow. It expects the original Mac's existing v8.1.5 installation and project repository path.

It does not replace the already-qualified engine, bridge supervisor or Spotlight guard. It validates the v8.0.8 build, stops any v8.1.6 test candidate, restores the existing v8.1.5 bridge under launchd, and adds the production Reduce Motion LaunchAgent.

The production helper requires a one-time Full Disk Access grant on the qualified Sonoma system because `com.apple.universalaccess` is protected.

That makes the script appropriate as the exact upgrade record/package for the original Mac, but not as a fresh installer for an arbitrary machine.

## Historical v8.1.5 files

v8.1.5 remains preserved as the previous production baseline and rollback target.

Its Spotlight helper is still the active Spotlight component in v8.1.6 and remains unchanged.

## Historical v8.1.3 files

The older v8.1.3 scripts remain preserved for provenance.

Known historical local assumptions include:

- launchd label `com.guy.reloopbridge`;
- historical working path `$HOME/Documents/reloop-controller`;
- package source layout under `dev/`.

The old v8.1.3 status helper also has historical reporting-path mistakes. Those are status-script defects, not evidence that the qualified engine version was different.

## Public package rule

The v8.1.6 GitHub Release ZIP is the original-qualified-Mac upgrade package. It is not advertised as a universal fresh-machine installer.

Any future general installer must receive its own structural and live-hardware qualification.
