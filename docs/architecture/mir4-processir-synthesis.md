---
title: "MIR 4 ProcessIR, Effect Channels, and Synthesis"
status: current
applies_to: "4.0.0 M4C02-09-24H W06 and T12"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
---
# MIR 4 ProcessIR, Effect Channels, and Synthesis

W06 and T12 form a package-excluded developer preview. W06 consumes serialized canonical recipe and risk facts, preserves their fingerprints, derives deterministic process graphs and bounded minimal SCC witnesses, and classifies synthesis proposals. T12 obtains those inputs from a read-only mod that runs after MIR's terminal finalizer against exact target packages and environments. Neither path recreates recipe-risk heuristics or admits operations to the player planner, emitter, runtime, or migration executor.

## Authority boundary

The terminal owners remain `recipe_facts.lua`, `recipe_risk_facts.lua`, and `relationships.lua`. `ProcessIR.ps1` validates a copied transport record and derives ProcessIR V1. Missing, ambiguous, partial, opaque, or unsupported facts are `UNKNOWN`; they never become safe through confidence or policy. `SafetyKernel.ps1` remains non-overridable and rejects known unsafe processes. The bilateral fixture gate also proves at least one known-safe process remains admissible as a preview proposal, so rejecting everything is not treated as safety.

`fixtures/mir4-processir-exact-observer` asks the terminal `CompilationSnapshot` adapter and recipe-risk fact owner for data inside a fresh, scoped read context. It performs no prototype write and cannot reach the planner or emitter. Each capture binds the exact engine executable, candidate archive, retained dependency closure, startup settings, source commit/tree, and `EnvironmentLockV1`. Factorio parameter recipes whose finalized flows do not expose concrete item or fluid identities are retained as explicit `unavailable` transport omissions; they are never converted to an empty name or zero quantity.

Cycle witnesses use deterministic breadth-first shortest-cycle search. This retains minimal deterministic witnesses while bounding dense official-recycling SCC work; the former enumeration of every simple cycle is prohibited.

The EffectChannel registry records the existing owner's value domain, composition, neutral value, repeatability, saturation, bounds, representation, runtime owner, migration, presentation, and proof references. Opaque channels retain null unknown semantics and a `Preserve` disposition. MEP scripted channels remain data-only references until runtime, migration, target, and proof evidence exists.

## Synthesis maturity

The ten constructors are descriptive proposals, never compiler operation objects. `Diagnose` emits proposals only. `Conservative` can mark a candidate complete only when hard-safety, target, migration, and proof certificates are independently complete, but W06 still cannot mutate a player build. `Experimental` is private opt-in research. K2, Space Exploration, Angel, and Pyanodon process models remain exact-environment, review-required previews.

The governing prompt names five terminal dispositions: `Preserve`, `RequireExtension`, `RequestReview`, `Omit`, and `FailHardSafety`. W06 does not invent an unnamed sixth value; `admissible-preview` is an assessment state.

## Exact T12 and T13 evidence

The governed T12 matrix contains 11 target/environment requests: F210 and F200 base and official closures; F210 Corrundum, Cubium, Recycler, K2SO, AAI, and BZ; and F200 K2SO. The immutable T12 reference records ten deterministic captures plus the historical F200 K2SO custody blocker that existed at that turn.

T13 closes that narrow blocker without rewriting T12 history. Scenario dependency rows are now joined to their authoritative lock entries, including exact archive source paths, versions, and SHA-256 identities. All 11 captures reproduce twice. The tracked T13 supplement carries the exact F200 K2SO lock and ProcessIR snapshot, and its canary record binds clean load, two byte-preserving reloads, the F200 direct-predecessor matrix, performance, limitations, and expiry. No substitute archive was guessed or fabricated.

Every captured snapshot retains bounded recipe inputs and outputs, exact/bounded quantities, independent probabilities, catalysts, productivity exclusions, temperature and quality facts, categories, machines, surface conditions, unlocks, owners, recycling/recovery classification, terminal risk fingerprints, SCCs, and safety outcomes. Source-mod ownership remains explicitly unavailable because Factorio's finalized recipe surface does not expose a trustworthy last-writer identity.

The reference set under `sdk/preview/mir4/reference/t12` contains the immutable T12 snapshots, locks, bounded A/B comparisons, Inspector bundles, blocker, manifest, and receipt. The T13 reference under `sdk/preview/mir4/reference/t13` supersedes only the current custody assessment and adds exact lifecycle canaries; it does not mutate T12 evidence. Neither reference authorizes synthesis, player mutation, public support claims, source freeze, signing, sealing, promotion, or publication.

```powershell
.\tools\mir.ps1 mir4 processir-synthesis export
.\tools\mir.ps1 mir4 processir-synthesis check
.\tools\mir.ps1 mir4 exact-processir export --repetitions 2 --publish-reference
.\tools\mir.ps1 mir4 exact-processir check
```
