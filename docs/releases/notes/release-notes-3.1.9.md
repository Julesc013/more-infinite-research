---
title: "MIR 3.1.9 Release Notes"
status: current
applies_to: "3.1.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# MIR 3.1.9 Release Notes

MIR 3.1.9 is the final Factorio 2.1 patch in the 3.1 line. It keeps the released 3.1.5 compiler behavior and fixes settings that were visible but ineffective when Space Age or another mod already owned an infinite productivity technology.

## Fixed

- Processing-unit, plastic, low-density-structure, and rocket-fuel productivity owners now honor the normal MIR Enable, base cost, cost growth, maximum level, research time, and effect-per-level controls.
- Default values preserve the final existing owner exactly, including changes made by another mod.
- Disabling one of these streams leaves its external technology untouched.
- Explicit effect changes update only recipe-productivity effects whose recipes produce the stream's product; unrelated effects are preserved.
- Recognized native and MIR exponential cost formulas retain their mathematical style. MIR rejects explicit cost changes to unknown formulas instead of approximating them.
- Owner updates are planned and applied as one fingerprint-checked transaction; unsafe or unavailable owners retain the existing fallback-generation path without duplicate coverage.

## Maintainer Tooling

The repository now includes change-aware, content-addressed release assurance and the finite museum compiler used to reconstruct Factorio 0.12 through 0.6. Neither tooling surface, its manifests, fixtures, evidence, nor historical target source is included in the Factorio 2.1 release ZIP.

Interactive settings layout, technology-tree presentation, icon fit, locale fit, and human balance judgment remain maintainer review gates.
