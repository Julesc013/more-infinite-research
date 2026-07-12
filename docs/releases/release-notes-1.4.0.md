---
title: "MIR 1.4.0 Candidate Notes"
status: current
applies_to: "1.4.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 1.4.0 Candidate Notes

MIR 1.4.0 is an unreleased Factorio 0.14 finite-continuation reconstruction.

- Generated technologies use science-pack-1, science-pack-2, science-pack-3, and alien science.
- Research uses fixed target-supported counts; unsupported native infinite fields are not emitted.
- Iterative prerequisite graph checks still reject missing, disabled, and cyclic paths.
- Only modifier types present in the matching Factorio 0.14 engine are eligible.

The Space Age-specific Muluna and Astroponics repair is intentionally absent because those technologies do not exist on Factorio 0.14.
