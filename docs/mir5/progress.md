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

Goal: **WORKING — not released or qualified**. The maintainer authorized implementation through verified publication. Continue on Aero; prepare a coherent beta/RC handoff through GitHub for Black Glass after approximately **20:00 AEDT, 2026-10-23**, then return final validation and release administration to Aero. This supersedes the brief request to stop local development. Neither that time nor a private package is an acceptance waiver.

## Branch and custody checkpoint

- Primary: `C:/Projects/Factorio/more-infinite-research`, implementation branch `feat/mir5-library-ownership-r01`, [PR #760](https://github.com/Julesc013/more-infinite-research/pull/760).
- `dev` integrates the first gear slice through [PR #758](https://github.com/Julesc013/more-infinite-research/pull/758), `833946a0b275e1da3471cdec69c239f8aaf3ce9d`. [PR #759](https://github.com/Julesc013/more-infinite-research/pull/759) remains pending; its line-ending correction is `14d8e6391`. Its preceding hosted run passed 57 checks but failed the committed-delta whitespace gate on three mixed final line endings; the correction passes the actual baseline-to-working-tree whitespace check and six composition controls. New head CI must finish before merge.
- `main` remains `4080f73d6af200fb19068f6c1e165ca0a5a67f37`; `legacy` remains `69f96b3900f337cb1575c0e7e3ca7373089401fb`. No MIR 5 release tag exists.
- Continuity worktree: `C:/Projects/Factorio/mir5-runtime-continuity-r01`, branch `feat/mir5-runtime-continuity-r01`. Completed implementation units through `3a9744ebf` are integrated into the primary branch. Its old dirty progress draft is preserved until reconciled; do not overwrite it without custody.
- Eighteen unique primary inputs were hash-verified, copied into the continuity worktree and later moved into `build/mir5/runtime-continuity-r01/preserved-primary-inputs/`. The primary `worktree-custody.json` records the disposition. All historical dirty/unique worktrees, saves, packages and evidence remain preserved.
- Exact published F210 baseline: source `84bd157ad7b63b7d171fac2311bf30de70429c11`, ZIP `dist/4.7.0/more-infinite-research_4.7.21000.zip`, SHA256 `708A529F1F6D649E0A732216CD8D8FEFE68F2C6C2DF2B40DA030C2C4C51558D1`. The former wrongly named library bytes remain in `build/mir5/published-baseline/library-prior/`.

## Implemented private scope

`source/mir5/` contains fresh direct native gear construction, local family preflight, the data/runtime MIR API, finite-cap lifecycle ownership, admitted worker-speed tail ownership, settings import/export and commands, passive repair, and a partial Research Library. It imports no MIR 4 production modules. It is still an incomplete catalogue and must use disposable worlds only.

Runtime continuity now includes configuration-only import of proven historical cap rights, durable examined markers, foreign/malformed-state rejection, preservation of the shipped repair queue, and game-free read-only `on_load`. Repair uses conditional 60-tick scheduling. Library translation labels/indexes stay local; only bounded issued-request bookkeeping and epochs are durable, with conditional 61-tick maintenance. Closed/disconnected/rootless views do not issue or render translation work.

The Library preserves historical personal records and supports status filters, deterministic sorting and validated hidden selections. Strict name comparison now has ascending/descending, opposite insertion-order and casefold-tie opponents. Legacy `page` is retained as bounded state; **pagination UI is not implemented**. Modes/tabs/settings scope, other delivered UI behavior, rendered interaction and real-client multiplayer remain open.

The standalone unrestricted-module override is activated only for effective `mir-unrestricted-modules=true`; false returns before its body loads or prototypes are enumerated. Its setting meaning and exact published name/warning entries are retained in all 50 current locales. Agriculture/spoilage pure runtime components exist but remain unactivated. Their exact Space Age definitions and fourteen setting rows are now captured in [the Space Age inventory](../../spec/mir5/inventory/space-age-f210-470.json).

The SDK executes its Lua-first examples against the current public modules. The previous-surface audit found the shipped settings/browser interfaces and package-excluded synthetic preview API/MEP envelopes, with no identified independent third-party consumer inside the pinned source/archive scope. Retained browser options are not yet fully compatible; document the actual major transition and finish applicable bridges. Do not invent an external consumer or call synthetic examples its migration.

## Verification and exact evidence

The integrated **31-command** host lane passes locally, including SDK examples, override activation, Library state/model/translation controls, legacy ownership, settings, scripted components, properties and packaging. Log: `build/mir5/runtime-continuity-r01/integrated-31-host-controls.txt`. Its explicit plan is printed before execution. The earlier temporary-worktree run encountered in-flight Library edits; that failed log remains preserved and is not acceptance. The later frozen integrated run passes. The complete local MIR 4 platform conformance/materialization test passed after the staging/classification/projection fixes; it does not qualify the MIR 5 product.

Previously accepted native receipts keep their original package identities:

| Observation | Exact scope and evidence |
|---|---|
| Default/Tuned gear production | 100 then 110/120 gears from exactly 200 plates per phase, native cost boundaries and two cold reloads; [Default](../../spec/mir5/evidence/gear-default.json), [Tuned](../../spec/mir5/evidence/gear-tuned.json). |
| Cap/API scenario | Frozen player SHA256 `6F6817697CDA52C2D8B9576BD308E546FDCFBD9FFD795B63BADC9043592AC3C8`, source `deb16bbe3934502e6520d3a6e308db1db614dd5d`; actual labs consume two of each four packs, complete two gear levels, preserve 0.2 productivity, filter queue/progress, force reset/merge, both consumers and two reloads. [Scope chain](../../spec/mir5/evidence/caps-api-chain.json). Beta's finite productivity technology was queried, not completed in that accepted run. |
| Published 4.7 gear upgrade | Original seed SHA256 `7080EB050770EE5BB5C0525C23F4B25E573A6055E76DFBE6292AD69A4AB627A0`; next level 3, earned 0.2, cap 2, unrelated/foreign state and two reloads preserved. Historical cap import/relaxation remains unqualified. [Scope chain](../../spec/mir5/evidence/gear-upgrade-chain.json). |
| Optional API absence / science ambiguity | Separate native absence and representative ambiguity opponents pass for their named frozen inputs. [Science chain](../../spec/mir5/evidence/science-ambiguity-chain.json) explicitly leaves `SCI-UNLOCK-01` open because the original complete reporter profile is unknown. |
| Vanilla replay | Complete native data/settings equality for the published output; [scope chain](../../spec/mir5/evidence/replay-vanilla-chain.json). |
| K2SO replay | Dependency-valid no-MIR, published 4.7 and direct replay captures pass with exact actual loaded versions, including asset-only mods. Replay equals the **complete** native data/settings output: 83 additions and three patches, plus 889 setting additions. [Scope chain](../../spec/mir5/evidence/replay-k2so-chain.json). |
| Space Age baseline | Exact no-MIR and published native dumps pass; [published receipt](../../spec/mir5/evidence/space-age-published-native.json), [no-MIR receipt](../../spec/mir5/evidence/space-age-no-mir-native.json). These characterize historical definitions, not new implementation gameplay. |

All preceding native refusals/errors remain adverse evidence. The K2SO log-only selection failure remains unchanged in [its receipt](../../spec/mir5/evidence/k2so-no-mir-log-selection-adverse.json); the corrected observed profile adds one hash-bound, non-mutating active-mods fixture. No prior failed receipt was relabelled.

The K2SO single dump durations are diagnostic start-to-exit observations only. They are not responsive-menu timing, sample uncertainty, a percentage improvement or `PERF-04` acceptance. Finish the matched menu experiment before mass porting. No new source, settings, fixture or archive inherits an earlier native pass.

## Machine and resource disposition

Execution host is **AERO-15X-WIN10**. All nine approved executable paths exist; [the machine input observation](../../spec/mir5/inventory/aero-native-inputs.json) distinguishes file availability from qualification. Exact published target ZIPs remain in primary `dist/4.7.0`. Older direct libraries need selected archive membership preparation; the F200 same-name library ZIP differs from accepted custody and must be preserved before replacement. Do not download or retarget historical Steam depots.

Native work is serial under the unchanged 4 GiB physical and 20% commit reserves. Closing Brave allowed the bounded data-stage captures. A fresh untimed graphical seed attempt with its declared 2432 MiB budget was subsequently refused at commit admission; its result remains in `build/tmp/mir5-menu-seed-preparation-r01/result.json`. Controls were restored and it produced no accepted seed/menu sample. Do not lower the budget to force admission. The user's credential-bearing player data was neither copied nor edited. An actual credential-free engine-generated seed and owned acknowledgement of any first-run notice are still required. No self-hosted GitHub runner is registered; Black Glass handoff uses GitHub, with each machine running its own complete comparisons.

## Next executable work

1. Finish PR #759's selected head checks and merge it normally, then reconcile PR #760 against `origin/dev`, finish its checks/review, merge and read back. Keep completed units pushed while independent work continues.
2. Finish the bounded matched responsive-menu replay experiment with actual engine-generated seed and unchanged admission. Retain refusals separately; use Black Glass tonight for heavy tests when available. Do not mass-port every family before resolving the empirical hypothesis.
3. Freeze a current private source/archive and run actual beta productivity production, historical cap relaxation/import, worker ownership, settings/repair and Library lifecycle scenarios; protect original saves and retain two cold reloads. Current old-source passes do not cover these changes.
4. Complete applicable authored catalogue/settings/progression/integrations and activate exact scripted effects. Preserve native owners/carriers and earned research; continue difficult finite/high-level/overhaul cases early.
5. Finish Library fidelity, independent-consumer and API transition evidence, all nine exact target adaptations/qualification, historical upgrades, real multiplayer and final-candidate stress/performance checks.
6. Only after parity/qualification: perform reviewed version-neutral flattening, remove superseded current implementations/instructions, verify package-member equivalence and final layout, freeze exact accepted artifacts, pass administration/immutability/signing/promotion gates, tag `v5.0.0`, publish GitHub/Portal and verify anonymous downloads/hashes. Deliver accepted artifacts to primary `dist`.

Continuation starts with `git status --short`, live PR/check readback and this worklist. Inspect the host plan with `.\tests\mir5\Test-MIR5HostControls.ps1 -Plan`; run affected checks first with the explicit pinned `build/tmp/mir421-lua-runtime`. Run development health before new output batches. Preserve matching in-progress work, dirty drafts and all exact receipts; never reset to synchronize.
