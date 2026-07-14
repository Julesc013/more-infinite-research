---
title: "MIR 1.4.0 Candidate Notes"
status: current
applies_to: "1.4.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 1.4.0 Candidate Notes

MIR 1.4.0 is an independent canonical MIR 3.1.9-derived Factorio 0.14 finite-continuation reconstruction from `DEV_LOWER_WAVE_ANCHOR` commit `7ca81bbc98f02cfaf2d40012096d94e261e74d98`. The earlier `tmp/0.14` candidate remains `SUPERSEDED-UNRELEASED` characterization evidence and is not this reconstruction's source ancestry.

- Generated technologies use science-pack-1, science-pack-2, science-pack-3, and alien science.
- Research uses fixed target-supported counts; unsupported native infinite fields are not emitted.
- Iterative prerequisite graph checks still reject missing, disabled, and cyclic paths.
- Only modifier types present in the matching Factorio 0.14 engine are eligible.
- Unsupported recipe-productivity controls are omitted instead of displayed as inert settings.
- This target does not claim native-infinite parity; supported continuations use target-valid finite levels.

The Space Age-specific Muluna and Astroponics repair is intentionally absent because those technologies do not exist on Factorio 0.14.
