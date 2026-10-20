# Installation status

## Public repository scope

The current public baseline is **engine v8.0.8 + service v8.1.5 source + mappings + documentation**.

The repository does **not** currently present the v8.1.5 service script as a universal one-click installer for arbitrary Macs.

## Why the v8.1.5 installer is not universal

`service/install_or_upgrade_reloop_bridge_service_v8_1_5.sh` is the exact installer used to upgrade the original test Mac.

Its safety design intentionally expects that Mac's existing v8.1.3 runtime so it can preserve:

- the previous v8.1.3 LaunchAgent;
- the v8.0.4 engine;
- the v8.1.3 supervisor;

before replacing them.

It also installs a root LaunchDaemon for Spotlight control, so administrator approval is required.

That behavior is useful qualification provenance but is not a clean fresh-install path for another machine.

## Controlled manual source run

For engineering evaluation:

1. Build v8.0.8 using `docs/BUILD.md`.
2. Install/configure BlackHole 16ch separately.
3. Configure Traktor using `docs/TRAKTOR_SETUP.md`.
4. Connect the Reloop Jockey 3 ME.
5. Run the built engine in the foreground.

For the repository build script:

```bash
./build/reloop_bridge_engine_v8_0_8_phase4_recovery_diagnostics
```

Stop it with Control-C.

The foreground bridge engine itself does not require `sudo`.

## Original qualified Mac

The original Mac runs:

- per-user LaunchAgent: `com.guy.reloopbridge`;
- engine: v8.0.8;
- service wrapper: v8.1.5;
- root LaunchDaemon: `com.guy.reloopbridge.spotlightguard`.

The Spotlight helper requires root privileges because it controls filesystem indexing through `mdutil`.

## Future portable installer

A fresh-machine installer should be a separate artifact. It should:

- support installation when no previous bridge version exists;
- use generic package-relative source paths;
- install/uninstall the root Spotlight helper safely;
- preserve and restore pre-existing Spotlight state;
- avoid touching unrelated LaunchAgents/LaunchDaemons;
- validate mappings/checksums;
- receive its own structural and live-hardware qualification.

Do not relabel the original-Mac v8.1.5 upgrade script as that future portable installer without testing it.
