# Service scripts — qualification provenance

This directory contains both the historical v8.1.3 service artifacts and the current v8.1.5 service/helper artifacts used on the original qualified Mac.

They are **qualification provenance**, not a universal public installer.

## Current original-Mac runtime

Current service/package:

**v8.1.5**

Current engine:

**v8.0.8**

LaunchAgent:

`com.guy.reloopbridge`

Spotlight LaunchDaemon:

`com.guy.reloopbridge.spotlightguard`

Current files:

- `install_or_upgrade_reloop_bridge_service_v8_1_5.sh`
- `reloop_bridge_service_status_v8_1_5.sh`
- `reloop_spotlight_guard_v8_1_5.sh`
- `rollback_to_v8_1_3_from_v8_1_5.sh`

The v8.1.5 upgrade was installed and live-tested on the original Mac. The Spotlight helper's Traktor start/stop behavior was also live-confirmed repeatedly.

## v8.1.5 portability boundary

The v8.1.5 upgrade script deliberately preserves the original Mac's existing v8.1.3 runtime before replacement. It therefore assumes those v8.1.3 files exist.

That makes it appropriate as the exact qualified upgrade record for the original Mac, but not as a fresh installer for an arbitrary machine.

## Historical v8.1.3 files

The older v8.1.3 scripts remain preserved for provenance.

Known historical local assumptions include:

- launchd label `com.guy.reloopbridge`;
- historical working path `$HOME/Documents/reloop-controller`;
- package source layout under `dev/`.

The old v8.1.3 status helper also has historical reporting-path mistakes:

- it looks for a v8.0.3 process while displaying v8.0.4;
- it tails a v8.1.2 log while displaying v8.1.3.

Those are status-script defects, not evidence that the qualified engine version was different.

## Public package rule

A future fresh-machine installer should be separately implemented and qualified. Do not “clean up” one of these provenance scripts and call it the same qualified package without another test pass.
