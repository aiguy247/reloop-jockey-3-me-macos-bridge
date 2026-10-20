# Public-readiness audit

Status: **public repository; current v8.0.8 / v8.1.5 baseline approved for publication on 20 October 2026.**

## Repository status

The repository is public:

`aiguy247/reloop-jockey-3-me-macos-bridge`

The owner explicitly approved promotion of the current live-tested baseline to the public current release.

## Current-tree audit scope

The publication set includes:

- v8.0.8 Objective-C source and Phase 4 diagnostic/recovery history;
- v8.1.5 service and Spotlight-helper source used on the original Mac;
- five mapping-only Traktor exports;
- mapping and source checksums;
- qualification/runtime documentation;
- engineering/test tooling.

The repository does not include runtime WAV recordings or the large local diagnostic logs used during qualification.

## Mapping privacy

The five files under `mapping/` are mapping-only Controller Manager exports.

They do not contain global Traktor preferences, playlists or arbitrary user files.

The current Deck A/B mapping additions are documented separately and their exact mapping-file SHA-256 values are recorded in `checksums/MAPPING_ONLY_SHA256SUMS.txt`.

## Service/package portability

The current v8.1.5 installer is the exact upgrade script used on the original qualified Mac.

It includes original-environment assumptions, particularly the requirement to preserve the pre-existing v8.1.3 runtime before replacement.

Therefore publication of the source does **not** mean it is advertised as a universal one-click installer.

See `docs/INSTALLATION.md`.

## Author identity

Public Git author name is intentionally **Guy R. Hood**.

The repository uses the GitHub noreply address associated with the account.

## License

The repository uses the **MIT License**.

Copyright holder:

`Guy R. Hood`

## Third-party scope

The repository does not bundle Traktor, BlackHole, Reloop firmware or a vendor driver binary.

The project is independent and unaffiliated with Reloop, Native Instruments or the BlackHole project. Product names are used only to describe compatibility.

## Current publication boundary

The public baseline records exactly what was tested and what remains unproven.

In particular:

- normal v8.0.8/v8.1.5 operation is live-tested;
- Mix Recorder works in the final configuration;
- Spotlight automatic disable/restore is live-confirmed;
- the bounded catastrophic USB recovery path remains unexercised in a reproduced catastrophic failure;
- other Macs/macOS/controller revisions are not claimed as qualified.
