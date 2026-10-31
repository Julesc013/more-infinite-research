---
title: "F200 enabled armor recipe witness"
status: prepared
applies_to: "MIR 5 F200 combined Bob/Angel startup"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-30
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-f200-enabled-armor-fixture
---

# F200 enabled armor recipe witness

This private fixture changes only `bob-mech-armor-plate.enabled` from `false` to `true` during data-updates. Factorio 2.0.77 documents `enabled` as an optional boolean defaulting to `true`. MIR's authored armor productivity output does not use that activation flag. The fixture adds no settings, technologies, runtime handler or save state.

Use `tests/profiles/bob-angel-enabled-armor-f200-2077.json` with the exact engine/archive controls inherited from the existing combined selection. Build only `info.json` and `data-updates.lua` into the fixture ZIP; keep this README outside it. The native execution owner retains exclusive staging, archive restoration and native execution.

Use the existing `tools/Invoke-PrototypeCapture.ps1`: first qualify the NoMIR arm, then retain the original guard's exact refusal, then capture the corrected candidate. Bind fresh output paths and actual MIR archive hashes in the native packet. Retain the prior combined-profile resource policy; this is a data-stage regression, not a new menu benchmark.

Require the fixture marker and final recipe `enabled=true`. The original guard must reject the same variation with `MIR F200 combined Bob/Angel preflight armor route changed`; if it loads, the changed flag did not exercise that guard and the witness is unqualified. The corrected candidate must retain all 69 independent public rows, the applicable existing private-credit oracle and MIR settings, plus every unmodified upstream row. Preserve the actual lab/owner state and all input archives. Stop and diagnose a missing marker, reset flag, different refusal or output difference; do not relabel it as a pass.

The frozen published oracle and the already-qualified ordinary combined data remain their original observations. This prepared witness does not qualify a native run, gameplay, performance, the severe-loading incidents or release acceptance.
