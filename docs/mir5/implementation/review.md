---
title: "Implementation review: close decisions, do not expand architecture"
status: draft
applies_to: "MIR replacement development; explanatory pseudocode, not executable product"
audience: developer
doc_type: implementation-draft
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-implementation-draft-review
---

# Implementation review

## Verdict

The architectural direction is sufficient for a first implementation. It is **not yet a complete executable design or evidence of product correctness**. The remaining work is predominantly resolving concrete semantics and showing the consequences in code, rather than adding more subsystems.

This review uses the current archive, not every conflicting proposal in the conversation. In particular, it retains `add_technologies`, the versioned API module/interface names, detached native output, finite-family preflight, justified broad collection, full applicable parity, and the distinction between historical preservation and optional absence.

## A. Already specified, but not yet recovered or demonstrated

| Area | Existing authority | Exact outstanding decision/evidence |
|---|---|---|
| Gear research | `docs/mir5/first_batch.md`; `GEN-01`, `SET-01` | Actual prototype IDs, published defaults, profile precedence, cost/bonus units, targets and disable behavior. The `research_gears` source key is not a complete prototype identity. |
| Availability/preservation | `GEN-07`, `MIG-01` | Per-family, per-configuration decision for disablement, missing upstream targets, native-owner takeover and removed integrations. No generic hidden/no-effect carrier can be presumed safe. |
| Settings resolution | `SET-01` through `SET-04` | Which value wins when raw settings and an imported profile both specify a key, including an explicit value equal to the default. Preserve inherit, absent, zero, unlimited and false distinctly. |
| Stage placement | `API-02`, `COMP-02` | Exact entrypoint, prerequisite availability and field read/write order for each real family and override. Do not move all work to final-fixes by default. |
| Native-owner change | `GEN-04`, `COMP-01` | Which exact fields may change and which preconditions justify that change; what happens when a foreign mod already changed them. |
| Costs and caps | `GEN-02`, `SET-02`, `SET-03` | Native starting suffix, numeric/formula model, rounding, accepted high-level domain and earned-above-cap treatment. No universal `level - 1` or cost formula. |
| Runtime ownership | `RUN-02`, `RUN-03`, `MIG-02` | Actual persistent field schema, baseline ownership, reset behavior and shared-writer cooperation. A recorded last value is not proof of exclusive ownership. |
| Product closure | `VER-03`, continuity inventory | Complete relevant catalogue before any real-save upgrade. Independent legacy expectations, not candidate-generated golden files. |

These are not newly invented requirements. The archive already requires them; the historical records and implementation have not yet supplied the needed answers.

## B. Proposed refinements exposed by writing pseudocode

### P-01 — Describe field order, not just module order

**Proposed amendment to `compatibility.md` and `architecture.md`:** for a real integration, add a short note naming the stage, exact fields read, exact fields written, and whether it consumes pre-override or post-override values. This is a sentence/table in that integration's contract, not a new execution-plan format.

Two deterministic operations can still conflict. For example, collecting recipes before changing productivity permissions need not mean the same thing as collecting afterward. Where ordering is intended to be irrelevant, test both orders; otherwise declare the one required order and test it. Re-read consumed foreign fields at the actual operation, not a cached earlier-stage snapshot.

### P-02 — Close the public-call edge cases before API stability

**Proposed amendment to `api.md`:** specify empty batches/lists, supported plain-table keys, depth/materialization limits, error selection order and the ownership of returned names. Proposed initial behavior: reject empty creation batches and empty recipe lists as `invalid_definition`; always reject sparse positional arrays and nonfinite consumed values; never silently truncate. These empty-input policies are proposals, not already frozen API facts.

Limits must be selected against valid historical content and independent consumers. Do not invent a hard maximum here. Copies of an acyclic input with repeated shared children must charge the actual expanded work; a depth bound alone does not bound allocation. Errors identify the operation and relevant technology/reference, without serializing the entire world.

### P-03 — Separate build purity, failed-write safety and successful-repeat behavior

**Clarification to `generator.md` / `verification.md`:**

- `build(template, values)` is pure and produces detached output.
- A rejected family preflight makes no MIR writes.
- Repeating a successful create is a duplicate error, not an idempotent no-op.
- Reconciliation of unchanged runtime state must not double-apply an effect.
- Engine-tracked migrations and ordinary reconciliation have different repeat contracts.

No generic engine transaction or rollback mechanism follows from these requirements.

### P-04 — Distinguish local graph checks from global correctness

**Clarification to `GEN-06`:** a local cycle check accepts forward references inside the submitted family but does not prove that arbitrary foreign prototypes cannot lead back to it. Kahn's leftover set includes nodes downstream of a cycle; do not label every leftover node a cycle member. A late foreign edit remains a native/profile-test concern.

Research attainability, the science vector's acceptance by a real lab, and safe recycling economics are not consequences of `reference_exists`. They remain compatibility obligations, not new Generator solvers.

### P-05 — Specify the test-runner/save boundary

**Proposed clarification to `migrations.md`:** refuse ordinary full-save upgrade tests for a partial experimental catalogue in the *developer harness before launch*. Do not ask the data stage to inspect saved research. Never use a release marker on disk as a substitute for the actual accepted catalogue and package bytes.

A runtime callback may be too late to rescue state already discarded during prototype reconciliation. Capture historical expectations from the original environment and preserve the original fixture bytes.

### P-06 — Make side effects of native setters part of the migration test

**Clarification to `MIG-02`:** do not treat `level` and `researched` as passive metadata. The 2.1.23 `LuaTechnology` documentation says their writes can apply/reverse research benefits, and writing a level enables the technology. Test modifier values, enablement, current/queued research and partial progress after every proposed migration, not only the stored number.

This does not authorize a blanket reset-and-restore migration. Exact setter ordering remains a feature-specific native test.

### P-07 — Account for collector fan-out honestly

**Proposed precision update to `performance.md` / `COMP-01`:** a typed-product lookup eliminates an all-families scan for each recipe, but one product may interest several families. Count **candidate associations inspected**, including rejected ones, not only accepted matches. Also count any additional fields inspected by predicates. The bound is visited entries + candidate fan-out + additional predicate work + output (+ a declared local sort), not automatically visited entries + accepted output.

Track this independently from ordinary exact-binding generation. A collector cannot infer safety from a product name or justify re-running once per public API call.

### P-08 — State the scheduler's overload semantics

**Clarification to `RUN-05` / `DET-05`:** a fixed number of entities processed each tick gives deterministic work but may increase revisit latency as the world grows. A hard CPU ceiling, fixed per-entity update frequency and unbounded entity population cannot all be guaranteed simultaneously. Preserve the accepted effect/rate or expose the precise changed latency/overload behavior for approval. No hidden work-dropping optimization.

This is not a request for a general scheduler. Only implement a feature-specific cursor or batch where that feature actually requires it.

## C. What should not change

Do not add a compatibility compiler to solve these decisions; recover known rules and implement their direct branches. Do not add a public arbitrary-patch endpoint. Do not replace `get_version`/`get_capabilities` with another renamed API. Do not manufacture runtime extension status from a discarded startup registry. Do not move inventories or diagrams into the player package. Do not enforce a whole-product LOC ceiling that hides data/UI complexity.

No new input above authorizes importing MIR 4 production code. Historical source remains evidence for semantics and independent fixtures.

## D. Minimal implementation authority

The first accepted work should recover and implement one exact gear-research contract, exercise at least one changed setting and a disposable save, and establish the same-output performance comparator. Recover a continuation/cap case concurrently as an input investigation, not a prerequisite for an exhaustive new architecture programme.

Only after two sufficiently different real operations work should the common helper and public API stabilize. The remaining delivered feature set remains required for stable replacement parity.

## Official cross-checks

Checked on 2026-10-22. Most pages below identified as **2.1.23**; the ResearchIngredient page returned **2.1.21**. This documents the retrieved versions, not native qualification of any engine.

- [Data lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html): startup rounds, stage boundaries, configured settings and discarded startup state.
- [Libraries](https://lua-api.factorio.com/latest/auxiliary/libraries.html): deterministic insertion-dependent iteration and restrictions on runtime `require`.
- [TechnologyUnit](https://lua-api.factorio.com/latest/types/TechnologyUnit.html): count versus formula and actual native level semantics.
- [TechnologyPrototype](https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html): native fields, trigger/unit alternatives and final engine constraints.
- [LuaTechnology](https://lua-api.factorio.com/latest/classes/LuaTechnology.html): native status and write side effects.
- [LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html): initialization, configuration changes and restricted `on_load` behavior.
- [Migrations](https://lua-api.factorio.com/latest/auxiliary/migrations.html): filename history and JSON/Lua ordering.
- [LuaRemote](https://lua-api.factorio.com/latest/classes/LuaRemote.html): runtime calls and interface registration.
- [ResearchIngredient](https://lua-api.factorio.com/latest/types/ResearchIngredient.html): item identity, not a blanket `data.raw.tool` restriction.

Exact target-native validation remains required, including every older supported engine. No SDK example or pseudocode substitutes for it.
