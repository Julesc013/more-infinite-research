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

Branch `feat/mir5-native-gear-slice-r01`: recover the actual published gear research definition, implement its direct native construction and necessary settings, then qualify a disposable native effect/save/two-reload case. Recover difficult K2 continuation/carrier and worker-speed cap expectations concurrently. Read [the first-batch contract](first_batch.md) and [Generator](../../spec/mir5/generator.md) before continuing.

PR #757's hosted MIR run `39858251701` was still executing selected historical static checks when this unit began. Preserve that execution identity and inspect its final result before claiming the integration checks complete.

Focused host controls passed: eight Lua 5.2 cases for independent default values, cost variants, import precedence/false/zero, detachment, local family preflight/cycles/duplicates/forward references, item-typed science and absence of whole-recipe scans. Two deterministic package/allowlist controls and the private-slice documentation boundary also passed. Command: `python -B tests/mir5/test_generator.py --lua-runtime-dir build/tmp/mir421-lua-runtime --output build/mir5/gear-r01/host-results.json`; package controls: `python -B tests/mir5/test_package.py`.

Independent review confirmed the published growth validation limit of 1000 despite no maximum on the settings prototype; the constructor now preserves that distinction. Import requires explicit schema 1, exactly as the released decoder does. Nonzero finite caps are explicitly refused in this private slice until their preservation controller lands. Retaining a disabled identity instead of omitting it is a deliberate preservation correction whose native upgrade behavior still needs qualification. Global science/lab policies and overhaul bindings are pending.

The native harness and Default/Tuned fixture are prepared under `tools/mir5/Invoke-NativeSlice.ps1` and `tests/mir5/fixtures/gear/`. Their intended witness is 100 gears from 200 plates before research, then 110 or 120 gears after the native 10% or 20% effect, followed by a saved disposable world and two cold reloads. These are planned assertions until executed; no native result is inferred from host checks.

Existing MIR 4.7 linked worktrees and unique material are preserved for their active or historical evidence custody. No worktree, save, archive or published object was deleted for this transition.

## Next executable work

1. Pin local published-baseline archives and independently recover exact technology, settings, progression and effect values; write that narrow continuity row with its references.
2. Implement the first source slice under `source/mir5/`; keep it isolated from production saves and the MIR 4 writer. Add only the minimal selected package/harness support it needs.
3. Run selected independent host checks and the affected native disposable scenario using the approved engine and exclusive direct archive library controls; record actual results.
4. Commit, push and integrate the completed unit, then continue the next risk-bearing functionality. The whole release goal stays active through final publication and anonymous readback.
