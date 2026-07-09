---
title: "Generated Technologies"
status: current
applies_to: "3.0.0+"
audience: player
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Generated Technologies

MIR generates infinite research lines from active Factorio prototypes during
`data-final-fixes.lua`. It reads recipes, items, fluids, labs, technologies, and
active optional mods, then creates or skips streams according to implemented
policy.

Generated recipe productivity technologies use stable prototype IDs documented
in the [generated ID reference](../reference/generated-id-reference.md). Stream
behavior and migration policy are tracked by the stream manifest.
