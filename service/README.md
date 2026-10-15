# Service scripts — qualification provenance

The scripts in this directory are the exact service-side artifacts preserved from the **v8.1.3 private qualification environment**.

They are **not a general public installer**.

## Why they are preserved

Keeping them unchanged records exactly how the qualified long-running service was installed and supervised.

## Known local assumptions

The installer uses:

- launchd label `com.guy.reloopbridge`;
- historical working path `$HOME/Documents/reloop-controller`;
- package source layout under `dev/`.

Those values are specific to the original setup.

## Known status-helper mistakes

`reloop_bridge_service_status_v8_1_3.sh` contains two historical version references that should not be copied into a future portable package:

- process lookup uses `reloop_bridge_engine_v8_0_3` while the display says v8.0.4;
- recent-log lookup uses `reloop_v8_1_2_service.log` while the display says v8.1.3.

The qualified bridge engine itself is v8.0.4. These are status/reporting-script defects, not evidence that the qualified engine was v8.0.3.

## Public package rule

Do not “clean up” these exact provenance files and then describe them as the same qualified package.

A future reusable service package should use generic identifiers/paths, correct status checks, and then receive its own structural and live-hardware qualification.
