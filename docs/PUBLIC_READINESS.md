# Public-readiness audit

Status: **public repository; current v8.0.8 / v8.1.6 baseline approved for publication on 20 October 2026.**

## Repository status

The repository is public:

`aiguy247/reloop-jockey-3-me-macos-bridge`

The owner explicitly approved promotion of the accepted v8.1.6 Reduce Motion behavior and creation of the GitHub release.

## Current-tree audit scope

The publication set includes:

- v8.0.8 Objective-C source and Phase 4 diagnostic/recovery history;
- retained v8.1.5 bridge/Spotlight provenance;
- v8.1.6 Reduce Motion helper source and original-Mac upgrade tooling;
- five mapping-only Traktor exports;
- mapping and source checksums;
- qualification/runtime documentation;
- engineering/test/release tooling.

The release workflow builds the v8.1.6 ZIP as a GitHub Release asset rather than committing the binary ZIP to Git history.

## Mapping privacy

The five files under `mapping/` are mapping-only Controller Manager exports.

They do not contain global Traktor preferences, playlists or arbitrary user files.

## Service/package portability

The v8.1.6 release package is an upgrade for the original qualified Mac. It expects the existing v8.1.5 environment and repository path.

It is explicitly **not** described as a universal one-click fresh installer.

## Permission disclosure

The v8.1.6 Reduce Motion helper requires Full Disk Access on the qualified Sonoma system because it writes the protected `com.apple.universalaccess` preference.

The installer checks this before changing the running bridge state.

## Author identity

Public Git author name is intentionally **Guy R. Hood**.

The repository uses the GitHub noreply address associated with the account.

## License / third-party scope

The repository uses the **MIT License** and does not bundle Traktor, BlackHole, Reloop firmware or a vendor driver binary.

The project is independent and unaffiliated with Reloop, Native Instruments or the BlackHole project.

## Current publication boundary

- normal v8.0.8/v8.1.5 bridge operation is live-tested;
- Spotlight automatic disable/restore is live-confirmed;
- v8.1.6 Reduce Motion behavior was live-confirmed as candidate v5 before promotion;
- the v8.0.8 catastrophic USB recovery path remains unexercised in a reproduced catastrophic failure;
- other Macs/macOS/controller revisions are not claimed as qualified.
