---
title: "Loader Manufacturing Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Loader Manufacturing Capability

Loader manufacturing identifies recipes that craft loader-like logistics entities. It is about crafting productivity, not loader throughput.

Evidence:

- item exists;
- item has `place_result`;
- placed entity type is `loader` or `loader-1x1`;
- a visible recipe produces the item;
- existing MIR belt productivity or a future validated stream owns the effect.

Known fixture: [AAI Loaders](../compatibility/targets/aai-loaders.md).

