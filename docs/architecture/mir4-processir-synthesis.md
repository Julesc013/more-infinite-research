---
title: "MIR 4 ProcessIR, Effect Channels, and Synthesis"
status: current
applies_to: "4.0.0 M4C02-09-24H W06"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 ProcessIR, Effect Channels, and Synthesis

W06 is a package-excluded developer preview. It consumes serialized canonical recipe and risk facts, preserves their fingerprints, derives deterministic process graphs and minimal SCC witnesses, and classifies synthesis proposals. It does not scan Factorio prototypes, recreate recipe-risk heuristics, or admit operations to the player planner, emitter, runtime, or migration executor.

## Authority boundary

The terminal owners remain `recipe_facts.lua`, `recipe_risk_facts.lua`, and `relationships.lua`. `ProcessIR.ps1` validates a copied transport record and derives ProcessIR V1. Missing, ambiguous, partial, opaque, or unsupported facts are `UNKNOWN`; they never become safe through confidence or policy. `SafetyKernel.ps1` remains non-overridable and rejects known unsafe processes. The bilateral fixture gate also proves at least one known-safe process remains admissible as a preview proposal, so rejecting everything is not treated as safety.

The EffectChannel registry records the existing owner's value domain, composition, neutral value, repeatability, saturation, bounds, representation, runtime owner, migration, presentation, and proof references. Opaque channels retain null unknown semantics and a `Preserve` disposition. MEP scripted channels remain data-only references until runtime, migration, target, and proof evidence exists.

## Synthesis maturity

The ten constructors are descriptive proposals, never compiler operation objects. `Diagnose` emits proposals only. `Conservative` can mark a candidate complete only when hard-safety, target, migration, and proof certificates are independently complete, but W06 still cannot mutate a player build. `Experimental` is private opt-in research. K2, Space Exploration, Angel, and Pyanodon process models remain exact-environment, review-required previews.

The governing prompt names five terminal dispositions: `Preserve`, `RequireExtension`, `RequestReview`, `Omit`, and `FailHardSafety`. W06 does not invent an unnamed sixth value; `admissible-preview` is an assessment state.

## Evidence limit

The repository does not yet contain a governed exact-target serialized terminal recipe/risk snapshot. W06 therefore reports `BLOCKED-EXACT-TARGET-PROCESSIR-SNAPSHOT`, proves only the synthetic safe/unsafe/unknown corpus, and retains developer-preview maturity. The three official records are exported under `build/mir4/m4c02-processir-synthesis` and remain outside player packages.

```powershell
.\tools\mir.ps1 mir4 processir-synthesis export
.\tools\mir.ps1 mir4 processir-synthesis check
```
