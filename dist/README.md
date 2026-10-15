# Distribution status

Binary installation ZIPs should be published as **GitHub Release assets**, not committed to Git history.

## v8.1.3 qualification artifact

The exact package used in the private qualified setup is:

`Reloop_Controller_Bridge_v8_1_3.zip`

- Service/package: **v8.1.3**
- Engine: **v8.0.4**
- SHA-256: `5255a15b3f9062b6df068daa0f118079306e8e6a5e3ac6e408612bac074aa908`

This ZIP is retained outside Git as qualification provenance.

It should **not** be published as the general public installer because its service wrapper contains local project assumptions. See `service/README.md`.

A future portable package should be attached to a GitHub Release only after its own qualification.
