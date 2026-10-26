# Release notes — v8.2.0

v8.2.0 promotes **8.2.0 Candidate 8 + v8.0.9-c4**.

## Included

- SMAppService-based Candidate 8 runtime architecture.
- Event-driven USB supervisor, WatchGuard and Spotlight helper.
- c4 stale-audio trim after long successful synchronous USB stalls.
- c4 clean engine exit after two consecutive zero-byte playback writes so Candidate 8 can reopen transport.

## Qualification

On 26 October 2026 the exact c4 engine was restored and verified:

`17421220f6d677640b03ebbd245c429a91506333326e8d55272f59d5c9d9f7a5`

Master audio, headphone cue and controller operation all passed.

A realistic session also ran for almost 58 minutes under mixed DJ/application load before an intentional Chrome cold-start reproduced an external USB transport wedge. Before that event there were no playback errors, no >50 ms successful playback stalls, no c4 soft-resyncs, no underruns and no accumulating latency.

## Known limitation

On the tested Sonoma 14.8.9 system, another application can open USB user clients and wedge the Reloop/Genesys USB transport. c4 exits cleanly after the hard playback failure and Candidate 8 performs bounded restart attempts. A physical controller power-cycle can still be required when the USB transport itself remains wedged.
