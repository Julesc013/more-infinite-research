---
title: "MIR 2.5.0 Release Notes"
status: current
applies_to: "2.5.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-27
supersedes: []
superseded_by: []
---

# MIR 2.5.0 Release Notes

## Highlights

- Backports the MIR 3.2 compiler platform, deterministic planning, fail-closed integrity checks, settings, localization, and established research streams to Factorio 2.0.
- Preserves valid concrete planet-discovery effects while pruning genuinely missing location targets.
- Loads after Pyanodons Post-processing and sanitizes the final Py technology surface, preventing `casting-mk02` from unlocking removed `casting-gear`.
- Retains valid sibling technology effects in their original order and records the exact reviewed sanitation row.
- Keeps Factorio 2.0-specific science, prototype, effect, dependency, and capability behavior; Factorio 2.1-only surfaces remain excluded.
- Uses 2.4.9 as the mandatory direct upgrade and approved-delta baseline.

## Compatibility

- Target: Factorio 2.0.
- Qualification binary: Factorio 2.0.77.
- Exact Py support claim: startup-integrity correction for the locked 2.0 closure; this is not a blanket claim of full Py technology-generation support.

## Candidate integrity

- Candidate: `2.5-P9`.
- Baseline commit: `7ebe93029695bbf809a15a14c6540530738a9e62`.
- Portable C22 source: `7ebe10dd52e34c8df54dc98dbc0f1375a134c4b8`.
- Package source: `f446d89f94ce4b9dc26f04c31c92f9bcffbac70d`.
- ZIP SHA-256: `30D7205527F3643169799AD8AF87C313D35DB81B14A6BDD460D9ED4D1B819DE3`.
- ZIP size: `1,029,910` bytes; `290` entries.

## Release status

P9 is an unreleased candidate. Exact Factorio 2.0 runtime, approved delta, upgrade, performance, full no-reuse, manual, protected, seal, and promotion gates remain pending until their candidate-bound evidence is produced.
