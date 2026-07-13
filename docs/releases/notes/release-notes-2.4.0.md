---
title: "MIR 2.4.0 Release Notes"
status: current
applies_to: "2.4.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
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
- Automatic recipe-family coverage is modular, disabled by default, and restricted to reviewed providers or explicit experimental opt-in.
- Unavailable Factorio 2.1-only technology controls are hidden on Factorio 2.0; no unsupported modern feature parity is claimed.
- Release assurance classifies changes, plans the affected evidence set, records content-addressed evidence capsules, and seals the exact qualified candidate.
- Processing-unit, plastic, low-density-structure, and rocket-fuel productivity owners now honor their existing MIR enable, cost, growth, level, time, and effect settings.

## Compatibility

MIR 2.4.0 deliberately omits the two Factorio 2.1-only cargo technology modifiers. Compatibility remains opportunistic and evidence-based: unsupported or unsafe streams are skipped with diagnostics rather than forcing broad overhaul claims.

Default native-owner settings preserve the final Factorio or modded technology values exactly, disabled streams leave external owners untouched, and unsafe formula overrides are rejected instead of guessed. Change-aware qualification retained the passing 82-scenario baseline for unaffected behavior, reran every invalidated native-owner and configuration-change case, loaded the exact archive with base and Space Age, and passed the exact 2.3.5 upgrade.
