---
title: "Verification and acceptance"
status: current
applies_to: "MIR development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-31
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

The [required migration boundaries](migrations.md#required-origin-coverage) retain every actual 4.7.3 stable predecessor route, representative older saves for each materially distinct known identity/effect/settings/schema/ownership change, and future MIR 5 stable save continuity. The 28 October maintainer clarification removes a separate every-old-patch campaign as a 5.0.0 prerequisite. Grouping guides scenario selection, never relabels evidence: each claimed native route still needs its actual source/candidate/save/two-reload proof. Keep direct mod upgrades, engine/DLC/provider changes and cold reloads separately observable. Uncertain or unavailable older cases may be recorded as deferred/unverified with preserved inputs and explicit support limits; known failures in required current or selected boundary routes remain blockers. Historical byte variants and adverse receipts remain distinguishable.

## Release verdicts

Keep these independent: feature parity; supported-profile correctness; migration/client safety; performance improvement; non-regression controls; package/delivery identity. A public release deadline or green host CI does not override a missing stable-acceptance verdict. A separately reviewed community prerelease identifies its exact bytes, completed/failed/unverified gates and support limits; its GitHub prerelease flag does not claim stable acceptance. The maintainer authorizes the first `v5.0.0` GitHub beta with unfinished Library input/export/personal-view checks and performance tests disclosed as unverified and deferred to stable. Package integrity, exact source/package/controller provenance, upgrade safety and normal checked publication remain mandatory; no missing or adverse result is reclassified as passed. Stable publication still requires every applicable verdict. No native test is counted as passed when unavailable, refused or not run.

Do not execute another local native job if the maintainer's worker already owns the same scenario. Three total agent slots and one heavy native workload per admitted machine remain the working capacity rule; a multiplayer scenario may require its intended simultaneous participants. Preserve and restore mod-list/settings controls.

## Historical preservation before stable

`VER-07` — Before declaring MIR5 stable, reconcile the historical tests, fixes, accepted requests and design decisions in the existing [continuity inventory](inventory/continuity.json) and [original request ledger](programmes/community-requests.json). Inventory published tags/packages, changed tests and fixtures, issue/PR discussions, changelogs, accepted design/playtest records and retained screenshots; deduplicate identical Git blobs instead of rereading each release. Account for all inventoried sources, grouping equivalent test intents or superseded machinery with their original references rather than requiring separate semantic work per blob or patch. Every applicable delivered behavior or accepted decision needs its original identity/decision, current implementation and adequate verification mapping. Unreviewed source groups, missing inputs and uncertain intent remain unresolved. An initial source inventory or source-route mapping does not complete this gate.

Retain correct tests; port only obsolete harness boundaries around valid independent expectations; consolidate duplicates while preserving their obligation links. Retire implementation-only compiler assertions, and preserve proposed, rejected and superseded decisions without turning them into promised features. Do not import the old framework or automatically rewrite/rerun every historical campaign. A changed oracle or mock needs an accepted historical decision or independent engine evidence. New regression controls must detect the known broken behavior, not merely accept the candidate's element names or mock geometry.

Start with the accepted 4.2 Library interaction amendment recorded under `CONT-10`: retained stable window, usable split browse/details with a narrow-screen fallback, continuous lists, working search/dropdowns, localized discovery, settings provenance, personal state, diagnostics/exports and native-research handoff. Do not restore superseded pagination/shrinking tabs or withheld queue authority. Host behavior, rendered screenshots and actual mouse/keyboard input establish separate scopes. Check the affected tabs, sizes/scales, long English/German text, lifecycle and burst/closed-view costs on the changed candidate; retain unrelated technology/migration results under their original inputs. Published 5.0.0 bytes remain fixed, and affected beta-to-successor state continuity needs its own result.

Native UI preparation must exercise the dispatcher's actual path resolution, archive-role binding, directory creation and launch validation before starting Factorio. Validate the complete config/write-data/output/capture composition with a cheap temporary-directory control. Review a bounded permitted action sequence before dispatch, then enforce desktop, process/window identity, foreground, geometry and state guards at each action and stop on an unexpected state. This does not bypass any existing safeguard or turn preparation into native acceptance.

## Implementation status

The companion case catalogue preserves the original acceptance requirements and their initial not-run status; it is not a native-result registry. The current ordered host driver exercises Generator, settings, compatibility, runtime, SDK, packaging and fixture controls, while exact native evidence and remaining gates are recorded in [progress](../docs/progress.md) and its named chains. The layout exporter was retired after canonical adoption. Host assertion counts, fixture controls and repository checks do not qualify native saves, clients or elapsed speed.

Two independent API consumer mods must pass before API 1.0 stability. Keep the host-only mock run, native load and actual effect/state observations separate.

## Additional determinism and consumer gates

`VER-05` — The deterministic property cases in [Determinism](determinism.md) are required wherever applicable. Repeat equal-input runs, vary irrelevant inputs and insertion histories independently, distinguish ordering-sensitive from ordering-insensitive contracts, and record semantic output separately from elapsed-time samples. Test a real second client; multiple forces in one process are not a multiplayer test.

`VER-06` — A cached test result is reusable only when all consumed inputs are demonstrably unchanged: relevant source/package members, actual engine and mod bytes, settings, save/fixture bytes, harness, scenario and measurement endpoint. Shared path or uncertain impact widens coverage. A reused result retains its original execution identity. No candidate may revise its oracle or lower its threshold as part of claiming that it passed.

These remain product acceptance requirements. Current host tests and source/package checks cover their named boundaries; native acceptance requires the exact engine/profile/scenario evidence above. Canonical relocation preserves original receipt and fact bytes, resolving only former source/spec/tests root prefixes at consuming lookup boundaries.
