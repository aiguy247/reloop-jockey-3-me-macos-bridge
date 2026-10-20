# Compatibility

## Current live-tested combination

The current evidence supports this exact environment:

- **Controller:** Reloop Jockey 3 ME
- **Controller firmware observed:** 1.0.6
- **Mac:** MacBookPro17,1, M1, 16 GB
- **Mac architecture:** Apple Silicon
- **macOS:** Sonoma 14.8.9, build 23J631
- **Traktor observed:** 3.11.1.17
- **Bridge engine:** v8.0.8
- **Service/package:** v8.1.5
- **Audio route:** BlackHole 16ch at 48 kHz
- **Buffer:** 384 samples
- **Traktor Multi-Core Processing:** OFF

The final accepted configuration also used the v8.1.5 automatic Spotlight guard and the macOS settings recorded in `QUALIFIED_RUNTIME_SETTINGS_v8_1_5.md`.

## Not currently claimed as qualified

- Intel Macs;
- other macOS versions;
- other Reloop Jockey models;
- other controller firmware revisions;
- alternative virtual-audio devices;
- alternative sample rates.

Some may work. This repository does not claim that without hardware evidence.

## USB hubs

The final accepted tests used the Hama hub path:

- Genesys Logic USB2.1 hub function VID:PID 05e3:0610;
- version 6.56;
- Reloop enumerated at USB High Speed / 480 Mb/s.

Earlier UGREEN tests used a different Genesys USB2 path and produced worse results in some stress runs, but the tests contained workload confounds.

Therefore:

- Hama is the preferred hub for the qualified original-Mac configuration;
- no hub model is claimed to be universally required or superior.
