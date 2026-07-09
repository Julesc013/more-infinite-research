---
title: "Lab Compatibility Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Lab Compatibility Capability

Lab compatibility proves that at least one active lab can research a generated
technology's science pack set. MIR treats labs as the science authority and does
not rely on old `data.raw.tool` science-pack assumptions.

The capability may accept, reduce, or reject proposed ingredients according to
the configured policy and observed lab inputs.
