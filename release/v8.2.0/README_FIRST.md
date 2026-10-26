# v8.2.0 release artifact

This directory records the exact v8.2.0 artifact promoted from the qualified Candidate 8 service architecture plus the verified v8.0.9-c4 engine state.

The release artifact is stored as base64 parts under `artifact/`, reconstructed by `tools/release/build_release_package_v8_2_0.py`, and accepted only if all of these gates pass:

- exactly 13 artifact parts;
- decoded size exactly 75,100 bytes;
- SHA-256 exactly `e46cad077e3724b59a95abf704aa3b316342a653a4ee30a778e5e70366c1134b`;
- ZIP integrity test;
- shell syntax checks for release, Candidate 8 and c4 scripts;
- Python syntax checks for audit/patch tools.

The GitHub Release workflow creates tag/release `v8.2.0` only after those gates pass on `main`.
