---
title: "MIR 4 Compatibility Cookbook"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-extension-compatibility-cookbook
---

# MIR 4 compatibility cookbook

Use declarative fragments for facts and policy hints that MIR can validate. Prefer the narrowest subject and target closure.

| Need | Fragment or result | Safe approach |
| --- | --- | --- |
| Name an equivalent subject | alias/adoption fragment | bind exact subject IDs and target |
| Preserve another mod's authority | ownership fragment | return adopted or preserved |
| Describe an absent value | availability fragment | encode unavailable explicitly |
| Add ordering | dependency fragment | declare edges; cycles fail |
| Explain a conflict | conflict fragment | name both envelopes and stop |
| Need prototype mutation | none | request first-party review; extensions cannot mutate |

Run `validate` before `lock`, then `explain` and `test` for every target. Use `diff` for review. An unknown fact stays unknown; never convert missing evidence into a safe assertion.
