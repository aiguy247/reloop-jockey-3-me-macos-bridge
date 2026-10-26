# Release notes — v8.2.0

v8.2.0 promotes the qualified Candidate 8 service/application architecture together with the v8.0.9-c4 engine behavior.

## Included

- SMAppService-based Candidate 8 runtime architecture.
- Event-driven USB supervisor, WatchGuard and Spotlight helper.
- c4 stale-audio trim after long successful synchronous USB stalls.
- c4 clean engine exit after two consecutive zero-byte playback writes so the supervisor can reopen transport.

## Qualification

Exact c4 engine SHA-256:

`17421220f6d677640b03ebbd245c429a91506333326e8d55272f59d5c9d9f7a5`

Master audio, headphone cue and controller operation passed after restore. Candidate 8 services were running normally.

A realistic 26 October session ran for almost 58 minutes under mixed DJ/application load before an intentional Chrome cold-start reproduced an external USB transport wedge. Before that event there were no playback errors, no >50 ms successful playback stalls, no c4 soft-resyncs, no underruns and no accumulating latency.

## Known limitation

On the tested Sonoma 14.8.9 system, another application can open USB user clients and wedge the Reloop/Genesys USB transport. c4 exits cleanly after the hard playback failure and Candidate 8 performs bounded restart attempts; a physical controller power-cycle can still be required when the transport itself remains wedged.
