# Distribution status

Binary/release ZIPs are published as **GitHub Release assets**, not committed to Git history.

## v8.1.6 release asset

The repository contains deterministic release tooling:

`tools/release/build_release_package_v8_1_6.py`

The GitHub release workflow builds and publishes:

- `Reloop_Jockey_3_ME_Bridge_v8_1_6.zip`
- `Reloop_Jockey_3_ME_Bridge_v8_1_6.zip.sha256`

The package is the upgrade artifact for the **original qualified Mac**. It expects the existing v8.1.5 environment and is not a universal fresh-machine installer.

## Historical v8.1.3 qualification artifact

The older private qualification ZIP `Reloop_Controller_Bridge_v8_1_3.zip` remains historical provenance and should not be presented as the current public installer.
