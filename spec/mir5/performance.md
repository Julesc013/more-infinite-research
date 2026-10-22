---
title: "Performance and resource contract"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-performance-specification
---

# Performance and resource contract

`PERF-01` — Optimize necessary work, not file count or labels. A Generator still executes while Factorio builds prototypes. There is no zero-startup-work or universal fastest/crash-free guarantee. Native effects need no recurring MIR tick work, but scripted features, state reconciliation and requested UI do have necessary cost.

## Work model

For a fixed implementation, count activation descriptors `D`, processed settings `K`, active declarations/patches `A`, referenced entries `R`, output entries `O`, consumed text bytes `B`, and visited broad-operation entries `W`.

Target expected work: **O(D + K + A + R + O + B + W)** under expected constant-time table lookup. Exact-binding/default paths use `W = 0` where their actual preserved behavior needs no collection. Enabling a whole-recipe override necessarily increases `W`. Active new effects necessarily increase `O`. String operations, hash-table worst cases, garbage collection, allocation and Factorio's own processing are not strictly constant time.

No repeated per-family global scan, repeated world serialization, future-level enumeration or planner fixed point. Scan a named owner's effects once per relevant unchanged scope when several declarations need them. Do not introduce a generic cache/invalidation layer to save a few named lookups.

`PERF-02` — Inactive adapter bodies are not loaded. Native effects add no recurring Lua handlers. Default/inactive global overrides exit before enumeration. No hidden Library refresh or runtime reconstruction of the old compiler.

## Empirical decision before mass porting

Use one existing dependency-valid large profile to compare exact published 4.7, a private direct replay of the same intended native output/patches, the real replacement and no MIR where dependency-valid. The replay is an empirical reference, not a mathematical optimum or player-side modpack compiler. Include all relevant settings/effects/runtime when comparing the corresponding endpoint.

If an incomplete one-technology package wins, it establishes only that slice's construction behavior. It is not a full-product speed claim. If same-output replay does not reduce the suspected cost, revise the hypothesis before porting every family.

## Measurement

`PERF-03` — Match each arm on the same computer, engine binary/API/official mods, upstream archives, startup values, graphics/cache policy and observer. Black Glass and Aero each run their own complete comparisons; never subtract one machine's baseline from another's candidate.

Measure process start to observed response to a harmless main-menu action. Window creation, initialization logs, headless map creation/save, simulation `--benchmark`, save load and first Library open are different endpoints. Report all game startup seconds separately from the incremental MIR effect.

For paired block `b` retain `d4_b=T4_b-T0_b`, `d5_b=T5_b-T0_b`, and direct `T5_b-T4_b`. Use a same-version A/A pilot, fixed counterbalancing and a predeclared sample/extension plan. Report sample spread and uncertainty. An unresolved/nonpositive added-time denominator does not support a percentage. Failure to reject a difference is not proof of equivalence; a bootstrap from very few noisy samples is not a precision machine.

No-MIR must leave valid dependencies. Otherwise state the alternate comparator and the claim it can support. Retain all accepted/adverse observations and classify refusals/errors separately. Native memory admission refusal is not a sample. Keep inference, archive preparation, builds and other heavy jobs out of timed runs.

## Replacement acceptance

`PERF-04` — Stable replacement acceptance requires full applicable parity and a credible substantial responsive-menu improvement on predeclared high-cost profiles; target at least **50% less MIR-added time versus 4.7** where measurable. This is a proposed replacement objective, not an observed result or the inherited emergency concession for 4.7. Freeze the exact workload and practical tolerances before final runs. Any later requirement amendment must be explicit, not hidden in analysis.

Require no material regression on controls, peak/retained memory, save load, first Library open/search and actual runtime under predeclared tolerances. Report remaining unexplained gap from the direct replay. Do not remove technologies, weaken migration checks, alter settings or shrink primary profiles to make a result pass.

## Work-count and footprint tests

`PERF-05` — Vary unrelated recipes with fixed exact definitions: lookup/build counts should not grow with that unrelated domain. Vary active definitions/effects and test proportional output growth. Vary enabled broad operations separately, including increasing actual matches. Instrumented counts prove the implementation's work shape; uninstrumented native timings prove elapsed cost.

Track all shipped logic, declarations, compatibility data, migrations, UI, imports, raw/compressed bytes and process memory. No minification, opaque packed data or hard LOC cap that hides code in a huge table. A roughly 150–300-line shared constructor is a review target from the proposals, not a proven whole-product size estimate. Larger coherent code needs a reason; a tiny core with duplicated complexity elsewhere also fails the objective.

Optimizations earn admission with a concrete consumer, invariant, measured benefit and opposing test. Rejected experiments keep their adverse evidence; do not retry them under new names without a changed mechanism.

## Deterministic work versus noisy measurements

`PERF-06` — Operation counts for a fixed diagnostic input are reproducible; elapsed seconds and peak process memory are not expected to be identical. Never use a profiler or wall clock to decide gameplay work. Keep production and instrumented packages separate in receipts. Apply [Determinism](determinism.md) and test extra unrelated recipes, more selected output, more players/forces and more scheduled entities as different scaling axes.

A bounded collector may need a measured local canonical sort. Report it rather than falsely calling every operation worst-case linear. Direct exact-binding generation remains proportional to consumed definition/reference/output size under expected native table lookup costs. Source line count alone neither proves this bound nor guarantees low latency.
