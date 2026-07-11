---
title: "MIR 2.4.0 Release Notes"
status: current
applies_to: "2.4.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# MIR 2.4.0 Release Notes

MIR 2.4.0 brings the supported 3.1 compiler improvements to the maintained Factorio 2.0 line while preserving 2.3.x saves and target-appropriate behavior.

## Highlights

- Canonical typed stream descriptors, immutable recipe facts, split science/lab planning, governed mutation commands, and deterministic packages now run on Factorio 2.0.
- Loader, mining-drill, and native-owner capability decisions use the validated lifecycle and target-positive requirements.
- Recycler-loop handling covers ambiguous paths, byproducts, fluids, variants, conversions, ignored productivity, and nonstandard returns conservatively.
- Scripted Space Age effects retain their level, save/load, disable/restore, re-enable, force lifecycle, and baseline-rebase behavior on Factorio 2.0.
- Validation now declares and passes 78 Factorio 2.0 scenarios, including exact archive base and Space Age loads.

## Compatibility

MIR 2.4.0 deliberately omits the two Factorio 2.1-only cargo technology modifiers. Compatibility remains opportunistic and evidence-based: unsupported or unsafe streams are skipped with diagnostics rather than forcing broad overhaul claims.

The exact 2.3.5 upgrade path retains generated IDs, settings, profiles, persisted state, and scripted runtime effects.
