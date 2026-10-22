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
- Published baseline: [MIR 4.7.0](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.7.0), source `84bd157ad7b63b7d171fac2311bf30de70429c11`. F210 asset `more-infinite-research_4.7.21000.zip` has GitHub-recorded SHA256 `708a529f1f6d649e0a732216cd8d8fefe68f2c6c2df2b40da030c2c4c51558d1`; local archive custody and actual output still need reconciliation.
- Original community IDs remain in [the request ledger](../../spec/programmes/community-requests.json), including unresolved `SCI-UNLOCK-01`. Existing request disposition is distinct from delivered feature parity.
- The staged implementation now constructs the historical vanilla F210 gear technology directly, with its exact default cost/effect/science/prerequisite identities, two icon layers, authored locale keys and applicable translations. It has no MIR 4 production imports. This is an incomplete private slice; release/native product acceptance remains pending.

## Current unit

Branch `feat/mir5-native-gear-slice-r01`: recover the actual published gear research definition, implement its direct native construction and necessary settings, then qualify a disposable native effect/save/two-reload case. Recover difficult K2 continuation/carrier and worker-speed cap expectations concurrently. Read [the first-batch contract](first-batch.md) and [Generator](../../spec/mir5/generator.md) before continuing.

The implementation is staged in [PR #758](https://github.com/Julesc013/more-infinite-research/pull/758). PR #757's hosted MIR run `39858251701` exposed invalid imported documentation metadata in `docs.check` (job `120113667423`). The current correction uses governed draft/reference/explanation/how-to metadata and hyphenated paths, regenerates the documentation projections, and passes `Test-MIRGovernance.ps1`; it does not change the authored design.

Focused host controls passed: eight Lua 5.2 cases for independent default values, cost variants, import precedence/false/zero, detachment, local family preflight/cycles/duplicates/forward references, item-typed science and absence of whole-recipe scans. Two deterministic package/allowlist controls and the private-slice documentation boundary also passed. Command: `python -B tests/mir5/test_generator.py --lua-runtime-dir build/tmp/mir421-lua-runtime --output build/mir5/gear-r01/host-results.json`; package controls: `python -B tests/mir5/test_package.py`.

Independent review confirmed the published growth validation limit of 1000 despite no maximum on the settings prototype; the constructor now preserves that distinction. Import requires explicit schema 1, exactly as the released decoder does. Nonzero finite caps are explicitly refused in this private slice until their preservation controller lands. Retaining a disabled identity instead of omitting it is a deliberate preservation correction whose native upgrade behavior still needs qualification. Global science/lab policies and overhaul bindings are pending.

The native harness and Default/Tuned fixture are under `tools/mir5/Invoke-NativeSlice.ps1` and `tests/mir5/fixtures/gear/`. Their intended witness is 100 gears from 200 plates before research, then 110 or 120 gears after the native 10% or 20% effect, followed by a saved disposable world and two cold reloads. Factorio 2.1.23 passed the data-stage assertions. Initial runtime attempts exposed fixture assumptions: research energy is in ticks (3600 for a 60-second unit), current cost must be read from the force-bound technology (8000 rather than prototype count 4000), and an assembler initially accepts only 104 of the required 200 plates. The fixture now replenishes its bounded input while preserving the expected total and outputs. Native production and reload acceptance remain pending; failed run logs are retained under `build/tmp/mir5-gear-native-r02` through `r04`.

The frozen player archive in `build/mir5/gear-r01/packages/` has SHA256 `3c832f5de36b08746f4e277dc229798eceaf526f5667cc1c95a5957849e6312d`. The next Default fixture is `build/mir5/gear-r05/packages/mir-fixture-mir5-gear-native_0.1.0.zip`, SHA256 `8ca77d195160cb4f290cedb827b2287efecf457c81c50e994feac64afeb43855`. The direct library retains one selected copy; earlier fixture bytes remain in checkout custody. The engine is the approved Steam 2.1.23 executable. The runner records hashes, selection, stdout/stderr and control restoration even on failure.

`source/mir5/runtime/caps.lua` is an independent reconciliation primitive with seven passing pure Lua controls. It preserves earned levels/bonuses, queue order and retained current progress, and restores only enablement/visibility changes it owns. It is not yet connected to product lifecycle events or qualified against native queues. Exact gear and runtime continuity contracts are recorded in `spec/mir5/inventory/gear-baseline.json` and `runtime-continuity.json`. The archive named 4.7.21000 in the external F210 library differs from the accepted published asset; preserve it and reconcile custody before any published-baseline run.

Existing MIR 4.7 linked worktrees and unique material are preserved for their active or historical evidence custody. No worktree, save, archive or published object was deleted for this transition.

## Next executable work

1. Finish Default/Tuned native physical production, saved state and two cold reloads against exact frozen inputs; keep failures as failures.
2. Integrate the first bounded unit through PR #758 after its selected checks, then continue cap lifecycle/native queue behavior, a second native effect and independent API consumers.
3. Capture actual published 4.7 final prototypes and recover remaining technologies/settings/integrations before broad parity construction and matched performance comparisons.
4. Continue migration, Library, historical engine subsets, final cutover and frozen release gates. The whole release goal stays active through final publication and anonymous readback.
