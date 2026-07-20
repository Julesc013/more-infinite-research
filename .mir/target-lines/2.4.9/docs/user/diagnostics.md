---
title: "Diagnostics"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# Diagnostics

Enable `mir-debug-generation-report` when a generated technology is missing or unexpected. The report explains whether a stream generated, skipped, reduced its science pack set, hit a lab incompatibility, or detected a competing owner.

Enable `mir-debug-recipe-matches` when a recipe did not receive productivity and you need the matched recipe list for a stream.

For processing units, plastic, low-density structures, rocket fuel, and steel plate, the generation report also identifies the native-owner outcome. `preserve_native_owner` means defaults retained the existing infinite technology exactly. `configure_native_owner` means explicit settings changed recognized owner fields. `adopt_native_owner_effects` means the existing owner received newly proven recipes without changing its configured values. `configure_and_adopt_native_owner` means both happened in one checked transaction.

If MIR reports a native-owner rejection, check the reason before changing costs. A missing or finite owner can fall back to MIR generation. An unrecognized external cost formula is preserved under defaults, but explicit base or growth changes are rejected because rewriting it would be unsafe. Recipes already covered by the external owner are never duplicated by fallback generation.

Attach the relevant log rows when reporting compatibility issues.
