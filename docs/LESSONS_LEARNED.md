# Engineering lessons learned

The project intentionally records failed approaches because several failures materially improved the development process.

## 1. A MIDI address is not enough to identify a physical control

An early Deck D change translated an address through a factory chart and identified the wrong control. Live testing showed the control was FX Select 3.

**Rule:** live hardware evidence outranks inferred physical-control identity.

## 2. Structural validity is not Traktor semantic validity

Several Sync rows were structurally valid but behaved as Hold inputs instead of the intended direct OFF action.

**Rule:** a TSI that parses correctly is not automatically functionally correct. Controller Manager semantics and live behavior must be checked.

## 3. Copying an unrelated mapping row can copy hidden behavior

An Unload mapping inherited `M1=1` from an unrelated template. Clearing the modifier fixed the behavior.

**Rule:** when reusing a Traktor row, audit modifiers, controller type, interaction mode, assignment, set value and OUT behavior.

## 4. Current user exports outrank generated masters

Manual fixes and Traktor re-exporting can change internal bytes/order while retaining intended semantics.

**Rule:** once a live-proven full export exists, it becomes the authoritative source. Do not reconstruct it from older generated files.

## 5. Protect a qualified transport layer

Once the v8.0.2 audio/USB path survived long-run testing, subsequent LED work was deliberately isolated from that code.

**Rule:** do not reopen a qualified subsystem without evidence of a regression. Make the smallest change that solves the new problem.

## 6. A recovered stall is still evidence

A 119.3 ms USB write did not produce a logged underrun because the catch-up mechanism worked. That does not make the transport timing perfect.

**Rule:** separate “recovered successfully” from “did not happen.” Preserve the event and improve diagnostics rather than hiding it behind a pass/fail label.
