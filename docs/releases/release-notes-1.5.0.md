---
title: "MIR 1.5.0 Candidate Notes"
status: current
applies_to: "1.5.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 1.5.0 Candidate Notes

MIR 1.5.0 is an unreleased Factorio 0.15 old-science native-infinite port.

- Generated technologies use Factorio 0.15's science pack identifiers and formula grammar.
- Iterative prerequisite graph checks reject missing, disabled, and cyclic technology paths.
- The package excludes Factorio 0.16+, 1.x, 2.x, recipe-productivity, and DLC-only behavior.

The Space Age-specific Muluna and Astroponics repair is intentionally absent because those technologies do not exist on Factorio 0.15.
