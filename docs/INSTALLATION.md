# Installation status

## Current recommendation

For third-party/public reuse, **do not run the v8.1.3 service scripts as a general installer**.

Those scripts are preserved as the exact wrapper used for the qualified private setup. They contain local assumptions such as a historical project directory and service identifier. The status helper also contains historical version-path mistakes documented in `service/README.md`.

A portable installer will require its own test and qualification.

## Controlled manual run

For engineering evaluation:

1. Build the engine using `docs/BUILD.md`.
2. Install/configure BlackHole 16ch separately.
3. Configure Traktor using `docs/TRAKTOR_SETUP.md`.
4. Connect the Reloop Jockey 3 ME.
5. Run:

```bash
./build/reloop_bridge_engine_v8_0_4
```

Stop it with Control-C.

The bridge does not require `sudo` in the qualified setup.

## Owner's existing qualified service

The already-qualified v8.1.3 service installation can remain in use on the original test Mac. Preserving its exact scripts is useful for provenance, but those scripts are not the public installation interface.

## Before a public installer is released

A reusable package must:

- remove local user/project identifiers;
- use repository/package-relative source paths;
- report the correct engine and service log versions;
- install and uninstall without touching unrelated files;
- require no `sudo` unless a future technical requirement is proven;
- pass structural checks and live hardware testing.
