---
title: "Science Integration Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: []
---

# Science Integration Capability

Science integration decides when active science packs participate in generated
research costs or science-pack productivity. Lab compatibility remains the hard
gate.

Science ingredients and progression prerequisites are separate decisions. MIR
adds no prerequisite when the pack's same-named recipe is already enabled in
every declared recipe difficulty. Otherwise it may use an enabled technology
that unlocks a recipe producing that pack. Technologies with
`enabled = false` are not valid inferred progression gates.

This distinction matters on Factorio `0.17`: the disabled tutorial technology
`basic-mining` also lists the normally available Automation science recipe as
an unlock. Treating that tutorial prototype as normal progression makes every
generated stream using Automation science unavailable in freeplay.

The `generated-prerequisite-safety` fixture rejects disabled prerequisites on
generated stream technologies, then researches all normal technologies in its
isolated save and rejects any remaining blocked stream. It runs in both reduced
legacy binary gates and the current-line base generation scenario.
