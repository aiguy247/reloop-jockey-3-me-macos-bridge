# Troubleshooting

## Bridge does not see the controller

- Confirm the physical Reloop Jockey 3 ME is connected and powered.
- Disconnect/reconnect the controller once.
- Avoid assuming the USB hub is the cause without an A/B test.
- If the service has entered its three-rapid-failure backoff, a physical unplug/replug is required.

## Traktor has no audio

Check:

- BlackHole 16ch is selected in Traktor;
- sample rate is 48 kHz;
- Master uses channels 1/2;
- Monitor uses channels 4/3;
- the bridge engine is actually running.

## Headphones are reversed or silent

The qualified bridge expects Monitor Left/Right on BlackHole **4/3**, not 3/4.

## MIDI controls do not respond

Confirm every included Reloop Controller Manager device uses:

`Reloop Jockey 3 ME (Bridge)`

for both In-Port and Out-Port.

## Tempo Master LEDs do not follow the master

Check the Deck A/B actual-master and Beat Phase OUT rows described in `CURRENT_MAPPING_SPEC.md`. The v8.0.4 bridge depends on those messages to decide which physical LEDs to gate/mirror.

## Current v8.1.3 status helper is misleading

The preserved qualified status script contains two historical mistakes:

- it searches for a v8.0.3 engine process name while labeling the result v8.0.4;
- it tails the v8.1.2 service log while labeling the section v8.1.3.

Do not use those two lines as proof that the current engine/service is running. They are preserved unchanged for qualification provenance and will be corrected in a future portable service package.

## USB stall in logs

A write over 50 ms is not automatically an underrun. Check the ring depth, catch-up behavior, dropped-frame count and underrun count around the event.

The known 119.3 ms stall in the qualified long session recovered without a software-path underrun. Its root cause remains unproven.
