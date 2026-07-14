---
title: "MIR 1.6.0 Candidate Notes"
status: current
applies_to: "1.6.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 1.6.0 Candidate Notes

MIR 1.6.0 is an independent canonical MIR 3.1.9-derived target projection from `DEV_LOWER_WAVE_ANCHOR` commit `7ca81bbc98f02cfaf2d40012096d94e261e74d98`. The earlier `tmp/0.16` candidate remains `SUPERSEDED-UNRELEASED` characterization evidence and is not this reconstruction's source ancestry.

MIR 1.6.0 is an unreleased Factorio 0.16 old-science port of the reduced native-infinite edition.

- Science selection uses Factorio 0.16's native science pack identifiers.
- Generated technologies retain strict iterative prerequisite graph checks.
- The package excludes Factorio 0.17+, 1.x, 2.x, recipe-productivity, and DLC-only behavior.
- Unsupported recipe-productivity controls are omitted instead of displayed as inert settings.

The Space Age-specific Muluna and Astroponics repair is intentionally absent because those technologies do not exist on Factorio 0.16.
