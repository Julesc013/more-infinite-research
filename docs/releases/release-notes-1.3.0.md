---
title: "MIR 1.3.0 Candidate Notes"
status: current
applies_to: "1.3.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 1.3.0 Candidate Notes

MIR 1.3.0 is an unreleased Factorio 0.13 finite-continuation reconstruction.

- Generated technologies use science-pack-1, science-pack-2, science-pack-3, and alien science.
- Research uses fixed target-supported counts; unsupported native infinite fields are not emitted.
- Iterative prerequisite graph checks reject missing, disabled, and cyclic paths.
- Only modifier types present in the matching Factorio 0.13 engine are eligible.

Modern recipe-productivity, Space Age, Quality, and scripted technology surfaces are intentionally absent because they do not exist on Factorio 0.13.
