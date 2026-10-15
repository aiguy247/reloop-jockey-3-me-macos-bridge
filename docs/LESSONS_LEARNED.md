# Engineering lessons learned

## 1. A MIDI address is not enough to identify a physical control

An early Deck D change translated an address through a factory chart and identified the wrong control. Live testing showed the control was FX Select 3.

**Rule:** live hardware evidence outranks inferred physical-control identity.

## 2. Structural validity is not Traktor semantic validity

Several Sync rows were structurally valid but behaved as Hold inputs instead of the intended direct OFF action.

**Rule:** a TSI that parses correctly is not automatically functionally correct.

## 3. Copying an unrelated mapping row can copy hidden behavior

An Unload mapping inherited `M1=1` from an unrelated template. Clearing the modifier fixed the behavior.

**Rule:** when reusing a row, audit modifiers, controller type, interaction mode, assignment, set value and OUT behavior.

## 4. Current live exports outrank generated predecessors

Manual fixes and Traktor re-exporting can change internal bytes/order while retaining intended semantics.

**Rule:** once live-proven individual Controller Manager exports exist, those current exports become source truth. Do not reconstruct them from older generated files.

## 5. Separate bridge requirements from workflow preferences

The qualified mappings include both bridge-integration rows and personal/project workflow choices.

**Rule:** do not tell another user that Favorites, Recorder/Cruise, EQ or Deck C/D customizations are required by the audio bridge when they are not.

## 6. Protect a qualified transport layer

Once the v8.0.2 audio/USB path survived long-run testing, later LED work was isolated from that code.

**Rule:** do not reopen a qualified subsystem without evidence of a regression.

## 7. A recovered stall is still evidence

A 119.3 ms USB write did not produce a logged underrun because catch-up worked.

**Rule:** separate “recovered successfully” from “did not happen.”

## 8. Preserve provenance without pretending it is portable

The exact v8.1.3 service scripts contain local paths/identifiers and two status-helper version mistakes.

**Rule:** keep exact qualification artifacts when they matter, but do not publish them as a generic installer. A cleaned portable package is a new test item.
