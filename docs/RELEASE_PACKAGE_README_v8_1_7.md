# Reloop Jockey 3 ME Bridge — v8.1.7 package

This is the physically qualified v8.1.7 Candidate 7 package promoted unchanged.

## What it contains

- qualified v8.0.8 bridge engine handling;
- preserved v8.1.5 bridge-supervisor behavior;
- event-driven Traktor WatchGuard;
- event-driven root Spotlight helper;
- installer, status and automation-only rollback scripts;
- Candidate 7 code-review record and checksums.

## Install

Close Traktor first, unzip the package, then run:

```bash
chmod +x install.sh status.sh rollback_automation_only.sh source/*.sh
./install.sh
```

The installer compiles and validates the two macOS helpers before replacing the installed automation layer. Full Disk Access for `Reloop DJ WatchGuard` is verified from the actual LaunchAgent context.

## Status

```bash
./status.sh
```

## Rollback automation only

Close Traktor first, then run:

```bash
./rollback_automation_only.sh
```

Rollback removes the v8.1.7 automation layer only after reconciling saved states. It leaves the qualified bridge installed.

## Artifact identity

This release asset is byte-for-byte the same ZIP as the Candidate 7 artifact physically qualified on 23 October 2026. The release workflow verifies SHA-256 before publishing it.

Expected SHA-256:

`8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d`

The package intentionally reports `8.1.7-candidate7` internally so the released runtime remains identical to the tested runtime.
