# v8.2.0 release review

## Promotion boundary

v8.2.0 promotes the already-qualified runtime state:

- service/application architecture: 8.2.0 Candidate 8;
- engine: v8.0.9-c4;
- exact engine SHA-256: `17421220f6d677640b03ebbd245c429a91506333326e8d55272f59d5c9d9f7a5`.

## Artifact integrity

Expected release ZIP:

- filename: `Reloop_Jockey_3_ME_Bridge_v8_2_0.zip`;
- size: 75,100 bytes;
- SHA-256: `e46cad077e3724b59a95abf704aa3b316342a653a4ee30a778e5e70366c1134b`.

The workflow reconstructs this artifact from immutable repository blobs and refuses release creation on any size, digest, ZIP-integrity or script-validation failure.

## Known limitation

The c4 engine detects/escalates a hard zero-byte playback failure and exits so Candidate 8 can attempt recovery. A physically wedged Reloop/Genesys USB transport can still require a controller power-cycle.
