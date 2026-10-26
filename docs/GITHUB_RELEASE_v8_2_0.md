# Reloop Jockey 3 ME macOS Bridge v8.2.0

**Candidate 8 service architecture + v8.0.9-c4 engine recovery behavior.**

## Highlights

- Promotes the SMAppService-based Candidate 8 architecture.
- Keeps event-driven controller, Traktor lifecycle and Spotlight handling.
- Adds c4 stale-audio trimming after long successful synchronous USB stalls.
- Adds c4 hard-failure escalation: after two zero-byte playback writes, the engine exits so Candidate 8 can reopen transport.
- Exact restored c4 engine SHA-256: `17421220f6d677640b03ebbd245c429a91506333326e8d55272f59d5c9d9f7a5`.

## Qualification

After restoring c4 on 26 October 2026:

- Candidate 8 services: PASS
- exact c4 SHA: PASS
- c4 recovery markers: PASS
- c5 marker absent: PASS
- master audio: PASS
- headphone cue: PASS
- controller controls: PASS

## Known external limitation

Third-party IOKit USB access can still wedge the physical Reloop/Genesys transport on the tested Sonoma setup. v8.2.0 detects and escalates the hard playback failure but cannot guarantee recovery while the underlying USB transport remains wedged.

## Release asset

`Reloop_Jockey_3_ME_Bridge_v8_2_0.zip`

SHA-256:

`e46cad077e3724b59a95abf704aa3b316342a653a4ee30a778e5e70366c1134b`
