---
title: "MIR 2.5.0 Release Notes"
status: current
applies_to: "2.5.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-02
supersedes: []
superseded_by: []
---

# MIR 2.5.0 Release Notes

## Highlights

- Backports the MIR 3.2 compiler platform, deterministic planning, fail-closed integrity checks, settings, localization, and established research streams to Factorio 2.0.
- Adds a separate Platform Productivity research stream: plus 10 percent for ice platforms and plus 5 percent for space-platform foundations.
- Gates Ice and Platform progression with cryogenic science while keeping the target-appropriate Factorio 2.0 science profile.
- Discovers compatible modded belts, underground belts, splitters, lane splitters, loaders, inserters, and module tiers structurally instead of relying only on fixed names.
- Preserves explicit productivity denial, recycling and catalyst safety, and disabled automatic-productivity policy.
- Preserves valid concrete planet-discovery effects while pruning genuinely missing location targets.
- Loads after Pyanodons Post-processing and sanitizes the final Py technology surface when targets are genuinely removed.
- Keeps Factorio 2.0-specific science, prototype, effect, dependency, and capability behavior; Factorio 2.1-only surfaces remain excluded.
- Uses 2.4.9 as the mandatory direct upgrade and approved-delta baseline.

## Compatibility

- Target: Factorio 2.0.
- Qualification binary: Factorio 2.0.77.
- AdvancedBeltsSA 2.3.3: exact native load and structural assertions passed on Factorio 2.0.77.
- Exact Py support claim: startup-integrity correction for the locked 2.0 closure; this is not a blanket claim of full Py technology-generation support.

## Candidate integrity

- Candidate: 2.5-P11.
- Baseline commit: 7ebe93029695bbf809a15a14c6540530738a9e62.
- Portable C30 source: c1fd8b932c8d916a14925678056e08893b87b2db.
- Package source: 493e71a6c883c2e191e1e13c7647cf38a8a8b261.
- ZIP SHA-256: 65C1610BAE120F135E328583899672E3636EAAD6D946DF104FD045B2D9AB10F1.
- ZIP size: 1,033,875 bytes; 291 entries.

## Release status

P11 is an unreleased, locally automated-qualified candidate. All 126 machine-verifiable tasks pass against the exact archive, including exact runtime, upgrade, ecosystem, approved-delta, AdvancedBeltsSA, and six-lane paired performance evidence. Exact maintainer manual acceptance, protected qualification, seal verification, promotion, tagging, and publication remain pending. P9 and P10 results remain superseded historical evidence and are not current P11 proof.
