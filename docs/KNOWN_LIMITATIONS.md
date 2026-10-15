# Known limitations and open diagnostic questions

## USB timing stalls

Long-run tests have observed occasional USB write stalls above 50 ms. The qualified buffering and clock catch-up logic has recovered without logged BlackHole drops or playback underruns, but the origin of the stalls is not yet proven.

Possible layers include:

- USB hub/controller behavior;
- macOS USB stack scheduling;
- Reloop USB transport behavior;
- interactions among USB devices;
- less likely general application scheduling, based on BlackHole callback continuity during the observed 119.3 ms stall.

Do not assign a cause without correlated evidence.

## Analog-output proof

A clean Traktor recording does not prove clean Reloop analog output. End-to-end proof would require independently recording the Reloop's analog Master output with another audio interface/recorder.

## Current logging gap

Service/package v8.1.3 combines MIDI drain `errors/timeouts` into one counter. The large count seen in a long session is consistent with the 0.5-second asynchronous MIDI-IN timeout cadence, but the current log cannot separate normal timeout completions from genuine non-timeout errors.

The next diagnostic version is intended to separate these classes and timestamp cross-endpoint stalls. It is not part of this qualified baseline.

## Platform scope

The qualified OS evidence is macOS Sonoma 14.8.9 on Apple Silicon. Other macOS releases may work, but are not claimed as qualified until tested.
