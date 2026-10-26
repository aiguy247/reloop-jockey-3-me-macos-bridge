# Reloop Jockey 3 ME macOS Bridge v8.2.0

This release promotes the tested **8.2.0 Candidate 8 + v8.0.9-c4** runtime.

- Service/application architecture: `8.2.0-candidate8`
- Engine: `v8.0.9-c4`
- Verified c4 engine SHA-256: `17421220f6d677640b03ebbd245c429a91506333326e8d55272f59d5c9d9f7a5`

The release ZIP contains the exact Candidate 8 package files and exact c4 package files used in qualification. The top-level installer only runs those two component installers in order.

Known limitation: on the tested Sonoma setup, third-party IOKit USB access can wedge the physical Reloop/Genesys USB transport. c4 detects the hard playback failure and exits so Candidate 8 can attempt restart, but a physical controller power-cycle can still be required.
