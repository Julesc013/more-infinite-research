---
title: "Determinism and reproducibility"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-determinism-contract
---

# Determinism and reproducibility

## Scope: deterministic behavior, not identical elapsed time

`DET-01` — The Generator and every MIR-controlled gameplay state transition MUST be deterministic for the complete, explicitly stated input. Determinism is separate from correctness, compatibility, idempotence, order independence and speed. A reproducibly wrong prototype is still wrong. Timings, peak resident memory, profiler readings, logs containing timestamps and benchmark noise are measurements, not deterministic product output.

| Boundary | Complete input | Required equality |
|---|---|---|
| Package | Exact source and assets, selected target, version metadata, packager, ordering/modes/timestamp/compression policy | Identical member names/bytes; identical ZIP bytes only with the same declared container environment |
| Settings | Target, ordered settings-stage mod execution, setting definitions, stored values, actual profile/import rules | Same effective setting meaning |
| Data/Generator | Engine and upstream mod bytes, ordered stage/invocation, relevant visible prototypes, authored definition bytes, resolved startup values and target capability | Same native output, omission/error class and MIR-owned field changes |
| Runtime | Same loaded game/native state, MIR persistent state, relevant settings, ordered events/remote calls, game tick, target behavior and any authorized RNG state | Same MIR state transition and game-affecting operations |
| Migration | Same original save, applied-migration history, old/new package closure, settings and target | Same supported transformation, not a generic repeat-every-migration promise |
| Tests | Fixed fixture, seeds, harness and expected observation endpoint | Same semantic assertion; timing thresholds still need repeated measurement |

The mod list and version labels alone are insufficient: different archive bytes with the same version or a later finalizer changing a consumed prototype are different inputs. No claim of equal behavior across different engine builds without separate qualification.

## Ordering rules

`DET-02` — Use dense authored arrays for semantic sequences and maps for lookup. Define a deliberate winner or reject a conflict; never let whichever extension happens to arrive first silently own a shared technology. Repeat calls creating an existing identity are errors. Data-stage dependency order remains part of the input; do not claim arbitrary mod-order independence.

Factorio modifies `pairs()`/`next()` for deterministic insertion-dependent traversal and modifies its random generator. Therefore **do not ban `pairs()` as inherently nondeterministic in Factorio**. That guarantee does not make two differently inserted tables equivalent. A plain-Lua test host may behave differently. Reference: [Factorio libraries](https://lua-api.factorio.com/latest/auxiliary/libraries.html), retrieved 2026-10-22, page identified as 2.1.23.

Where order is irrelevant by contract, permutation tests MUST show equal semantic outputs. Where an output is a sequence, retain its declared order. A bounded collected set that needs canonical presentation may be sorted once by an explicit stable key with a total tie-breaker; account for the O(k log k) work. Do not sort the whole prototype world or repeatedly sort static authored arrays. Comparisons of maps may use test-only normalization; that must not hide effect multiplicity, prerequisites, formula changes or ownership conflicts.

## Randomness, numbers and presentation

`DET-03` — Ordinary generation consumes no random values: research identity, recipe targets and progression are authored. Runtime randomness is allowed only for an explicitly accepted feature with a deterministic, owned RNG policy and replay tests. Prefer not to disturb the shared game RNG merely for MIR presentation. No undocumented global random call, wall clock, filesystem enumeration, process identifier or local machine preference may influence game state.

Validate finite consumed numbers and exact units. Do not assume floating-point addition is associative or reassociate historical cost/effect formulas for a micro-optimization. Sum in an explicit order where accumulation is needed; use native engine semantics for research costs. Distinguish literal zero, unlimited, inherit and absent values. Native engine math guarantees do not automatically apply to every offline Python/Lua test implementation.

`DET-04` — Locale, translated names, asynchronous translation reply order, screen size, GUI search text and per-player view state MUST NOT choose research identity, science progression or game-affecting order. Display ordering can vary by language; stable prototype IDs and explicit semantic order govern gameplay. Late callbacks must identify the player/view generation and discard stale replies. A hidden Library does not keep rebuilding its view.

## Runtime reconstruction and scheduling

`DET-05` — Native research effects require no recurring MIR Lua maintenance. Scripted periodic work uses game ticks and explicit work counts, never "do as much as this machine can in 2 ms". Persist a cursor/backlog only when needed for save/reload-equivalent behavior. Batch limits, fairness, revisit rates and overload behavior are part of feature semantics; do not silently change repair/growth effectiveness under load to pass a timing test.

`on_load` reconstructs local bindings and conditional subscriptions only as permitted by the engine; it does not change saved state or query unavailable `game`. A joining client must reconstruct the same handlers without rerunning server migrations. A reconstructible cache cannot decide a gameplay outcome differently when empty. Test cold reloads, host restart, join/rejoin, forces created/merged/reset and feature disable/re-enable.

Changing a persistent field's shape needs an explicit state migration. State reconciliation functions that claim idempotence must demonstrate it separately. Engine migration filename tracking is not permission to execute all historical migrations twice.

## Cross-stage and third-party boundaries

`DET-06` — Startup Lua state is discarded. Do not assume a data-stage registry, upvalue or `require` cache becomes runtime state. Runtime reads native technology state, compact authored metadata and explicitly supported cross-stage metadata only. API calls happen immediately in the caller's stage; they never depend on a later MIR finalizer that is not guaranteed to run.

The MIR API is a cooperation boundary, not an adversarial sandbox. An arbitrary other mod can mutate shared prototypes or fail outside MIR. Qualified input closures and explicit failure modes define support. Deterministic output does not certify safe recycling economics, reachability or save preservation.

## Validation and evidence

`DET-07` — Test equal-input replay, unrelated-input growth, input-table insertion permutations for declared sets, intentional ordering differences for declared sequences, input/output alias isolation, duplicate calls, complete closure changes, lifecycle reconstruction, and migration-history changes. Preserve minimized failing seeds.

Use state/prototype comparisons at declared native observation points; do not claim whole Factorio save ZIPs are byte-identical unless that exact representation is tested and meaningful. Compare work counters in diagnostic builds, timings in ordinary packages. Counts/hashes prove identity only, not semantics.

`DET-08` — Build reproducibility uses an explicit sorted member list, normalized paths, fixed permitted file modes, declared timestamp policy and a pinned compression recipe. A read-only cutover with unchanged player members should not create new gameplay bytes. Package reproducibility checks are outside Factorio; no runtime canonical-hash system is required.

## Required acceptance

The product cases `DET-BUILD`, `DET-GENERATOR`, `DET-ORDER`, `DET-RUNTIME`, `DET-MIGRATION`, `DET-NUMERIC` and `DET-PRESENTATION` in the acceptance catalogue are initially **not run**. Passing this documentation pack's tests is not passing those cases. See [verification](verification.md), [runtime](runtime.md) and [performance](performance.md).
