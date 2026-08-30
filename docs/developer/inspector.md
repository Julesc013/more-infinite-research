---
title: "MIR 4 Inspector Preview"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-inspector-developer-guide
---

# MIR 4 Inspector preview

Inspector renders bounded, immutable inspection bundles and exact snapshot comparisons. Extract `mir4-inspector-v1-preview.zip`, generate or select a bundled inspection bundle, and open its local HTML entry point.

Check the target, environment digest, source digest, availability state, diagnostic order, and comparison basis before interpreting a difference. `UNKNOWN` is preserved and is never displayed as safe or absent.

Inspector is read-only. It cannot mutate a save, run a migration, change a prototype, accept a compatibility claim, or authorize release.
