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
- Loads after Pyanodons Post-processing and sanitizes the final Py technology surface when targets are genuinely removed.
- The exact Py 2.0 closure retains valid `casting-gear` and ordered `casting-mk02` effects with zero external prunes; the synthetic late-removal fixture separately proves stale-unlock cleanup.
- Keeps Factorio 2.0-specific science, prototype, effect, dependency, and capability behavior; Factorio 2.1-only surfaces remain excluded.
- Uses 2.4.9 as the mandatory direct upgrade and approved-delta baseline.

## Compatibility

- Target: Factorio 2.0.
- Qualification binary: Factorio 2.0.77.
- Exact Py support claim: startup-integrity correction for the locked 2.0 closure; this is not a blanket claim of full Py technology-generation support.

## Candidate integrity

- Candidate: `2.5-P9`.
- Baseline commit: `7ebe93029695bbf809a15a14c6540530738a9e62`.
- Portable C24 source: `29f81addc0eec9b571afd6428c9e3529c4497a1b`.
- Package source: `f446d89f94ce4b9dc26f04c31c92f9bcffbac70d`.
- ZIP SHA-256: `30D7205527F3643169799AD8AF87C313D35DB81B14A6BDD460D9ED4D1B819DE3`.
- ZIP size: `1,029,914` bytes; `290` entries.

## Release status

P9 is an unreleased candidate. Exact Base and official Space Age ZIP loads, the direct 2.4.9 upgrade matrix, the 319-row approved delta, all six paired performance lanes, and the exact 11-mod Py 2.0 integrity campaign pass. Full no-reuse, manual, protected, seal, and promotion gates remain pending.
