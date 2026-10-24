# Qualified runtime — v8.1.7

## Qualified software baseline

- macOS: Sonoma 14.8.9, Apple Silicon
- Traktor observed: 3.11.1.17
- Bridge engine: v8.0.8
- Bridge supervisor behavior: v8.1.5
- Service/package release: v8.1.7
- WatchGuard / Spotlight automation: physically qualified Candidate 7
- Traktor audio sample rate: 48 kHz
- Traktor audio buffer size: 512 samples
- Traktor Multi-Core Processing: OFF

## Qualified automation behavior

When Traktor starts:

- WatchGuard receives an NSWorkspace launch event;
- original Reduce Motion and Spotlight states are persisted before DJ-state writes;
- Spotlight is disabled only if it is not already disabled;
- Reduce Motion is enabled only if it is not already enabled;
- each required change is verified.

When Traktor exits:

- each current state is compared with its saved original;
- no write occurs when already restored;
- otherwise the original state is restored once and verified;
- recovery state is removed only after successful restoration.

## Steady-state automation behavior

The new automation layer has no recurring Traktor polling loop and no recurring Spotlight status loop.

- WatchGuard sleeps in the NSRunLoop awaiting NSWorkspace events.
- Spotlight helper blocks in `accept()` awaiting authenticated local requests.
- `mdutil` is invoked only at state transitions/recovery.
- Reduce Motion preference refresh processes are touched only when a Reduce Motion state write is actually required.

## Physical qualification

Candidate 7 passed installer/reversible state tests and then completed approximately one hour of live DJ operation on 23 October 2026 with no reported crackling, popping, audio dropouts or bridge/control failure.

The qualification session intentionally ran without other applications and with Wi-Fi and Bluetooth disabled.

## Artifact identity

Exact qualified Candidate 7 ZIP SHA-256:

`8ebc35f548ec231c64214f68a7e481d5885d093e1b10ce2cfbfde6a0b48a801d`

GitHub v8.1.7 publishes this exact artifact; internal Candidate 7 identifiers are retained intentionally.
