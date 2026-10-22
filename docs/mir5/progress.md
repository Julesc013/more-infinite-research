---
title: "MIR 5 release progress and continuation"
status: current
applies_to: "MIR 5.0.0 replacement development"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-23
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-execution-progress
---

# MIR 5 release progress

Goal status: **WORKING**. The maintainer authorized the full implementation, qualification, cutover, promotion and verified GitHub/Mod Portal release of MIR 5.0.0 on 2026-10-23. The active Codex goal contains the release contract. A partial slice, static checks or a candidate package cannot complete it.

## Established inputs

- Primary checkout: `C:/Projects/Factorio/more-infinite-research`.
- MIR 5 design and crash/request continuity integrated into `dev` through [PR #757](https://github.com/Julesc013/more-infinite-research/pull/757), commit `edf3023d7ec52845746da16c7b793eefe0dfb589`; its tree equals the resolved integration commit `114bc5a7b48660e005a1950d07f4c3330c94cf86`. GitHub's supported squash merge was used.
- Starting `main`: `4080f73d6af200fb19068f6c1e165ca0a5a67f37`; starting `legacy`: `69f96b3900f337cb1575c0e7e3ca7373089401fb`.
- Published baseline: [MIR 4.7.0](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.7.0), source `84bd157ad7b63b7d171fac2311bf30de70429c11`. F210 asset `more-infinite-research_4.7.21000.zip` has GitHub-recorded SHA256 `708a529f1f6d649e0a732216cd8d8fefe68f2c6c2df2b40da030c2c4c51558d1`; local custody and the native vanilla prototype capture are verified below.
- Original community IDs remain in [the request ledger](../../spec/programmes/community-requests.json), including unresolved `SCI-UNLOCK-01`. Existing request disposition is distinct from delivered feature parity.
- The staged implementation now constructs the historical vanilla F210 gear technology directly, with its exact default cost/effect/science/prerequisite identities, two icon layers, authored locale keys and applicable translations. It has no MIR 4 production imports. This is an incomplete private slice; release/native product acceptance remains pending.

## Current unit

The first slice integrated through [PR #758](https://github.com/Julesc013/more-infinite-research/pull/758) into `dev` at `833946a0b275e1da3471cdec69c239f8aaf3ce9d`; remote readback confirms its tree exactly equals reviewed head `f6d334d6a96af4c3734abf4e5f14f3dbceed7ae1`. Primary `dev` was synchronized before creating `feat/mir5-caps-api-native-r01`, preserving the next unit's local work. Read [the first-batch contract](first-batch.md) and [Generator](../../spec/mir5/generator.md) before continuing.

PR #757's hosted MIR run `39858251701` exposed invalid imported documentation metadata in `docs.check` (job `120113667423`). The integrated correction uses governed draft/reference/explanation/how-to metadata and hyphenated paths, regenerates the documentation projections, and passes `Test-MIRGovernance.ps1`; it does not change the authored design.

Focused host controls passed: eight Lua 5.2 cases for independent default values, cost variants, import precedence/false/zero, detachment, local family preflight/cycles/duplicates/forward references, item-typed science and absence of whole-recipe scans. Two deterministic package/allowlist controls and the private-slice documentation boundary also passed. Command: `python -B tests/mir5/test_generator.py --lua-runtime-dir build/tmp/mir421-lua-runtime --output build/mir5/gear-r01/host-results.json`; package controls: `python -B tests/mir5/test_package.py`.

Independent review confirmed the published growth validation limit of 1000 despite no maximum on the settings prototype; the constructor preserves that distinction. Import requires explicit schema 1, exactly as the released decoder does. The initial slice refused finite caps; PR #759 supplies their controller, with native acceptance pending. Retaining a disabled identity instead of omitting it is a deliberate preservation correction whose native upgrade behavior still needs qualification. Global science/lab policies and overhaul bindings are pending.

The native harness and Default/Tuned fixture are under `tools/mir5/Invoke-NativeSlice.ps1` and `tests/mir5/fixtures/gear/`. Factorio 2.1.23 passed the data-stage assertions and the native production/save/two-cold-reload cases for the exact frozen player archive. Default produced 100 then 110 gears, and Tuned produced 100 then 120 gears, each phase consuming exactly 200 plates. The native counts at levels 1–3 were 8000/16000/32000 and 100/187/337 respectively. Both reloads retained the observed state and left the completed save byte-identical. The unchanged runner receipts are retained in [Default evidence](../../spec/mir5/evidence/gear-default.json) and [Tuned evidence](../../spec/mir5/evidence/gear-tuned.json). This qualifies only the named private slice and inputs; lab consumption, historical upgrades, caps, API consumers and release acceptance remain pending.

Initial runtime attempts exposed fixture assumptions: research energy is in ticks (3600 for a 60-second unit), current cost must be read from the force-bound technology (8000 rather than prototype count 4000), and an assembler initially accepts only 104 plates. The fixture now replenishes its bounded input. The r05 runner incorrectly accepted a saved marker despite a later fixture timeout; that run is invalid evidence. The corrected runner rejects fatal diagnostics and natural exits before completion, and records its controlled termination only after observing the completed save while the process remains alive. Retain all earlier failed logs, including the first r06 strict-mode diagnostic failure, under `build/tmp/mir5-gear-native-*`.

The frozen player archive in `build/mir5/gear-r01/packages/` has SHA256 `3c832f5de36b08746f4e277dc229798eceaf526f5667cc1c95a5957849e6312d`. Accepted fixtures are under `build/mir5/gear-r06/packages/`: Default SHA256 `e0b8dc080743233963ff0d326316c1ecc9f9d2aeb5a57bed22a99f24ba890001`, Tuned SHA256 `efcd5cbc90869c76e3ba0329fc6af2319909ad1c178f63f400e718476741b320`. The direct library retains one selected copy; earlier fixture bytes remain in checkout custody. The engine is the approved Steam 2.1.23 executable. The runner records hashes, selection, stdout/stderr and control restoration even on failure.

`source/mir5/runtime/caps.lua` has seven passing pure Lua controls. The next unit connects it through event-driven lifecycle ownership and the runtime API, with six lifecycle controls. Unlimited caps allocate no state or research handlers; profile/startup settings resolve once while control code is parsed. Native queue/lab/force lifecycle and consumer qualification remain pending. Exact gear and runtime continuity contracts are recorded in `spec/mir5/inventory/gear-baseline.json` and `runtime-continuity.json`.

The external F210 library's wrongly named 4.7.21000 archive (SHA256 `01fdf91912237fa3814fd33292c192b595ae42b35b726fff4163c0c4ab84202e`) is preserved at `build/mir5/published-baseline/library-prior/more-infinite-research_4.7.21000.zip`. The library now contains the hash-verified published asset `708a529f1f6d649e0a732216cd8d8fefe68f2c6c2df2b40da030c2c4c51558d1`.

The published F210 vanilla capture succeeded in `build/tmp/mir5-baseline-470-f210-r07` (receipt SHA256 `c12d7ad8e23fd56930d505b3144d8683395277bcba6c7eb2428e390a19b452bf`), retaining 249 technologies and the full prototype/settings dumps. The matching no-MIR capture succeeded in `build/tmp/mir5-baseline-vanilla-no-mir-f210-r02` (receipt SHA256 `76e8e4e1dfc5224b742b5fa88f5cbfb069670ad508bef8c34af6bc5db80d4412`). Both used the same Steam 2.1.23 engine and restored direct-library controls. Earlier memory/commit refusals remain adverse observations. The monitored 384 MiB process budget was respected; governor reserve thresholds were unchanged. These are data-stage observations, with no gameplay, responsive-menu or release claim.

The [native output inventory](../../spec/mir5/inventory/vanilla-f210-470.json) records seven exact comparison rows. It exposed the missing gear `order`; the constructor now preserves `p[research_gears]`, with current-package native comparison still required. The [settings inventory](../../spec/mir5/inventory/settings-baseline.json) recovers 28 global/non-family settings. The representative `science-ambiguity` fixture preserves two automation-pack unlock owners plus an alternative producing recipe; it is unqualified and does not close the original community report without its missing profile evidence.

[PR #759](https://github.com/Julesc013/more-infinite-research/pull/759) contains the next unit. Its dedicated Windows CI job passed the original 43 host/package controls (run `39866095503`) and the expanded 49 controls including metamorphic/mutation cases at `4a93ded8a` (run `39867819718`). Current documentation/adoption validation also passes after fixing Windows UTF-8 reads; generated Mermaid, SVG, PNG and atlas bytes remained unchanged. The [source catalogue recovery](../../spec/mir5/inventory/catalog-baseline.json) records 61 top-level productivity declarations, 15 direct declarations and six base extensions, with explicit incomplete inventory and capture-required boundaries.

The initial combined native candidate is preserved in `build/mir5/caps-api-r01/packages/`, SHA256 `32718aee4f93ec97021dcaf1e25f5d1f9d9a4bf1958f959804f3123236bb00ec`; its selection is `tests/mir5/profiles/caps-api-f210.json`. After prelaunch refusals, r03 exposed the beta fixture's invalid runtime `mods` guard. r04 passed that corrected guard and exposed the runtime API's unhandled native force-index exception. Both failures remain under `build/tmp/mir5-caps-api-native-*`. The guard now uses `script.active_mods`; the API contains the native lookup exception and returns `force_not_found`, with host regression controls. A new native pass is required. Required observations still include actual lab completion, repeated queue filtering/current progress, cap and foreign disablement state, force reset/merge, both public consumers and two reloads. Optional MIR absence requires its own native selection. The cap fixture preserves the documented numeric runtime infinite maximum (`4294967295`).

The completed first feature branch is retained locally because the accepted initial native receipts reference its unique intermediate source commits after GitHub's squash merge and automatic remote branch deletion. Its tree matches the accepted `dev` integration; no unique source/evidence was discarded.

Existing MIR 4.7 linked worktrees and unique material are preserved for their active or historical evidence custody. No worktree, save, archive or published object was deleted for this transition.

## Next executable work

1. Finish the native cap/API unit and integrate PR #759 after its selected checks, preserving all failed and accepted observations.
2. Complete the same-output replay and its matched large-profile responsive-menu comparison before mass porting; a vanilla diagnostic is not that acceptance endpoint.
3. Continue difficult native ownership/continuation, scripted effects, Library and a second historical research family, using the recovered exact contracts.
4. Continue migration, Library, historical engine subsets, final cutover and frozen release gates. The whole release goal stays active through final publication and anonymous readback.
