---
title: "Verification and acceptance"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-verification-specification
---

# Verification and acceptance

`VER-01` — A plan, source review, registered scenario, assertion count or archive signature is not a native result. Each claim records its exact source/player ZIP, target engine and official mods, mod/settings closure, relevant harness revision, command, endpoint and observed result. The same semantic assertion may share a launch with others; do not equate scenario count with native-launch count.

## Ordered test ladder

| Tier | Run for | Purpose |
|---|---|---|
| 0 — Fast static | Every affected change | Syntax, imports, package membership, local links, IDs, obvious duplicate declarations and native shape basics |
| 1 — Host behavior | Changed pure/data logic | Exact independent outputs, settings boundaries, ownership/alias tests, deterministic properties and targeted mutations |
| 2 — Native slice | Changed gameplay/engine/API consumer | Actual load, effect, progression, physical output and applicable save/reload |
| 3 — Integration | Migration, runtime, combined adapters, public API | Historical states, upstream changes, two independent extensions and genuine multiplayer |
| 4 — Candidate stress/performance | Coherent freeze or significant shared-path change | Matched menu measurements, large valid profiles, peak memory, long-running runtime/Library and exact release artifacts |

Documentation-only edits do not trigger the full native matrix unless a change alters an actual contract. Shared generator/setting/adapter behavior expands affected coverage. Uncertain impact is exposed for review, not used to skip tests. Reuse equivalent player bytes/harness inputs under their original identities; never relabel an old receipt as a new execution.

## Negative and property tests

`VER-02` — Require missing optional input, missing required historical identity, duplicate IDs, native-owner collision, finite/infinite boundaries, unsupported effect/engine, malformed/nonfinite costs, unknown API capability, external input mutation, output mutation, arbitrary foreign-state preservation, mod disable/readdition, event re-registration, late translation callbacks and invalid object references.

Properties: identical ordered input gives the same intended native output; an unrelated adapter cannot alter a family's output; each emitted effect is authorized; preflight rejection makes no MIR writes; public queries cannot mutate state; settings serialization round trips meaning; directory relocation does not alter player members. Property/mutation/fuzz work is offline, fixed-seed/reproducible where appropriate, and confined to small components. Do not generate an unbounded discovery engine merely to test one.

Test mutations should deliberately remove validation, shift a formula level, change an effect target, alias an array or grant a hidden carrier; the independent oracle must fail. Correct a bad oracle only using independent engine/source evidence, not by copying the candidate's unexpected output.

## Native matrix

Preserve previously useful qualified profiles and known incident configurations. Implement modern Base/Space Age plus a difficult K2 and Bob/Angel case early; historical targets follow their own actual capabilities before stable replacement acceptance. Other ecosystems use dependency-valid closures, not all overhauls combined. Broad ecosystem claims require actual useful effects, progression and saves, not only boot success.

Settings coverage combines defaults, per-setting boundaries and targeted interactions. No claim of exhaustive arbitrary-mod combinations. Stress varies definitions, products, prerequisites, research levels, players/forces and scheduled entities independently so the source of growth is visible.

`VER-03` — Production-save tests require a complete relevant catalogue. Partial development slices use disposable worlds. Test first loaded state, upgrade, save, two cold reloads and distinct clients after host restart as applicable.

## Release verdicts

Keep these independent: feature parity; supported-profile correctness; migration/client safety; performance improvement; non-regression controls; package/delivery identity. A public release deadline or green host CI does not override a missing verdict. No native test is counted as passed when unavailable, refused or not run.

Do not execute another local native job if the maintainer's worker already owns the same scenario. Three total agent slots and one heavy native workload per admitted machine remain the working capacity rule; a multiplayer scenario may require its intended simultaneous participants. Preserve and restore mod-list/settings controls.

## Implementation status

The companion case catalogue contains **not-run requirements**, not implemented tests. The archive's Python tests exercise only the layout exporter and documentation pack. A returned test count from that suite does not qualify the Generator, API examples, Factorio saves or speed.

Two independent API consumer mods must pass before API 1.0 stability. Keep the host-only mock run, native load and actual effect/state observations separate.

## Additional determinism and consumer gates

`VER-05` — The deterministic property cases in [Determinism](determinism.md) are required wherever applicable. Repeat equal-input runs, vary irrelevant inputs and insertion histories independently, distinguish ordering-sensitive from ordering-insensitive contracts, and record semantic output separately from elapsed-time samples. Test a real second client; multiple forces in one process are not a multiplayer test.

`VER-06` — A cached test result is reusable only when all consumed inputs are demonstrably unchanged: relevant source/package members, actual engine and mod bytes, settings, save/fixture bytes, harness, scenario and measurement endpoint. Shared path or uncertain impact widens coverage. A reused result retains its original execution identity. No candidate may revise its oracle or lower its threshold as part of claiming that it passed.

These are product acceptance requirements. The included Python tests check the specification pack, its diagrams and the non-destructive cutover utility only.
