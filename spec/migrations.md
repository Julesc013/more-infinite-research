---
title: "Save continuity and migration"
status: current
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-migrations-specification
---

# Save continuity and migration

`MIG-01` — Preserve historical prototype/setting IDs, level boundaries, effective native effects, hidden carriers and relevant persistent state before attempting runtime recovery. Same ID alone is insufficient if effect values, targets or starting levels change.

A data-stage generator cannot inspect the player's save. Runtime code cannot reliably reconstruct state already discarded by engine loading. Missing a required historical technology must not be treated like an absent optional new addition. [Lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html)

## Baseline and upgrade paths

The principal predecessor is the exact published 4.7 package for the same engine family. Preserve prior release variants by their hashes where relevant; version text alone does not identify previously reissued bytes. Distinct older upgrade boundaries retain their previously promised scope or receive an explicit documented bridge decision. Never recommend downgrade as the automatic inverse of upgrade.

Private incomplete slices use disposable worlds only. Do not load and resave a real full MIR factory with a one-technology replacement package. Full-save migration qualification starts only after all relevant definitions and runtime bridges exist.

The published F200 Base `recipe-prod-research_science_pack_productivity-1` six-recipe public row is intentionally present in F210 Base with the same authored ID, settings, cost and effects because both targets support its named native recipe-productivity effects; this narrow `MIG-01` compatibility correction restores the historical identity to fresh F210 Base worlds as well as preventing engine-load loss for earned F200 levels. It adds no new identity or runtime carrier and leaves F210 Space Age unchanged. The [C563 Base save hop](evidence/full-catalogue-f200-f210-c563-native-chain-r01.json) now demonstrates the exact published4.7.20003/2.0.77 to source1c90/C563/2.1.23 transition, retained54 level-backed public rows, actual source/successor gear labs and two independent cold reloads. The later [8F protected-save successor](evidence/full-catalogue-f200-f210-8f-native-chain.json) consumes the same unchanged published source save on exact2.1.23, retains54 seeded rows and42% queued/27% detached work, completes one new successor gear lab and preserves the successor save through two separate read-only cold reloads. Its carried source-lab count is not additional work. These results retain their original C563 and8F package/controller identities; they do not qualify later changed inputs, other mod/DLC closures or simultaneous settings/provider changes.

The direct published F2004.7.20000/.20001/.20002/.20003 to current MIR5 F210 transition also retains proven cap-restoration rights. Only that exact package-change event permits the F210 configuration callback to read the F200 settings-derived V3 tuples for currently admitted named research and native worker tails. Existing policy, visibility, foreign-disablement and current MIR5 ownership checks still apply; a predecessor bucket alone cannot authorize the exceptional reader. Construct its bounded predecessor map only for that one-time import, never ordinary control parsing or cold loading. Host controls cover owned versus foreign disablement, wrong or missing events, native-effect mismatch and the separate F200 MIR5 ledger-to-F210 route. Native finite-cap engine-hop, saved successor and two-cold-reload qualification remain required.

Published F2004.7 did not persist the old competing-productivity preference, and the configuration event reports only whether any startup setting changed. On the first4.7.20000/.20001/.20002/.20003→MIR5 upgrade, an earned named overlap without its own valid MIR5 credit ledger must refuse if startup settings changed and a known provider is current or being removed. Upgrade with startup settings unchanged and save once before changing the preference in a later MIR5 configuration. Ordinary provider-free upgrades are unaffected. The [exact4.7.20002 native chain](evidence/legacy-preference-transition-native-chain.json) verifies refusal and both two-step directions, actual successor labs, earned effects, foreign queue and two cold reloads at its recorded source. The4.7.20003 guard extends the same rule because the inspected4.7.3 hotfix retains the preference-history producers; its opposing host control covers both inclusion states without ledger/native writes on refusal. This source-level guard does not qualify an unpinned4.7.3 archive: exact predecessor bytes and its actual successor save/two-reload route remain required. Other predecessor binaries and provider mixtures retain their affected qualification obligations.

## Finite transition policy

Record direct, staged, refused and unresolved routes against their exact inputs instead of treating every engine/DLC/provider permutation as supported. Additional best-effort editions do not silently multiply the retained native matrix. A later source change needs a consumed-path applicability review and any affected native scenario; unchanged evidence keeps its original name and verdict.

| Route | Policy and current evidence boundary |
|---|---|
| Published MIR4.7 to MIR5 on the same retained engine | Intended direct upgrade for the complete admitted subset; every final package still needs its applicable earned/current/queued/suspended/runtime checks. |
| Published F2004.7.3 Base to F210 Base | The exact C563 route and separate8F successor above passed with the protected published source save; other profiles and later changed inputs require execution or justified VER-06 reuse. |
| Published F1104.7.3 to F200 | [r05](evidence/f110-f200-published-source-r05-native-chain.json) passes the protected F110 source stage. The separate [a1fd/8BA recovered successor](evidence/f110-f200-a1fd-successor-recovery-chain.json) passes one actual successor lab, seeded-state preservation, save and two cold reloads on2.0.77. Its outer caller adverse remains preserved; final changed inputs still need execution or justified VER-06 reuse. |
| First4.7 upgrade with changed startup settings and an earned known productivity overlap | Refuse when the former preference is unknowable; use the unchanged-settings first upgrade and saved/reloaded MIR5 intermediate before a later preference/provider change. The exact4.7.2 two-step record above does not qualify every4.7.3 closure. |
| Add/remove Space Age or a productivity provider | Require the named admitted route and separate native evidence for that closure. Preserve original saves; neither ordinary reloads nor an unrelated successful profile establishes this axis. |
| Remove MIR/provider, save, then readd | Absence cannot execute that mod's preservation code. Do not promise reconstruction of levels/state already discarded by the engine; use an original backup or an explicitly qualified bridge. |
| F018/0.18.47 normal edition | Recover its actual historical predecessor and shared subset, then qualify its admitted native/save route. It is a normal release obligation; an F100 test is not an F018 pass. |
| F001–F012 additions | Build/loader feasibility and native save continuity remain separately recorded best-effort obligations. No direct-save-hop promise follows from a build. |

For a refused or unqualified upgrade, retain the original save and its matching archives/settings, test only a copy, and use a named qualified intermediate route when one exists. Do not recommend a downgrade or a remove-save-readd cycle as an inferred inverse migration.

## Migrations themselves

`MIG-02` — Inventory existing JSON/Lua migrations by filename, purpose, required predecessor and imports. Factorio remembers applied names and runs JSON before Lua migrations. Do not rename filenames mechanically during repository cleanup. Decouple required historical logic from retired imports without retaining a whole old subsystem. [Migrations](https://lua-api.factorio.com/latest/auxiliary/migrations.html)

Small state transformations are idempotent. Keep the existing storage/global namespace and contribution baselines where necessary. Do not reset every force/technology, clear `mir` storage or grant invented levels to repair an unexplained failure. Writing native `level`/`researched` can itself change benefits/enablement; test effective state. [LuaTechnology](https://lua-api.factorio.com/latest/classes/LuaTechnology.html)

## Independent observation

Capture the earliest accessible loaded state before MIR compensation, then after migration and ordinary lifecycle handling. Compare completed/next levels; science/cost/effect semantics; native owner contributions; hidden carriers; queue/current research; saved progress; configured caps; disablement ownership; runtime multipliers; settings and unrelated force data.

`MIG-03` — Acceptance is original immutable save → candidate upgrade → saved candidate → independent cold reload → second cold reload, plus actual multiplayer lifecycle where affected. Same binary and upstream closures must be retained or any deliberately changed boundary isolated. State disappearance before callbacks is a failure to diagnose, not a fixture value to overwrite.

Required opponents include levels 0/2/3/7 around staged continuations; finite-at-cap and earned-above-cap; 42% partial investment where existing fixtures use it; native powder/crystal separation; unrelated scripted offset sentinels; mod removal/readdition; optional feature disable cleanup; force merges/resets; library state reconstruction.

## Cleanup is not history erasure

Delete retired implementation after obligations are recovered and replacement acceptance exists. Keep small active regression fixtures and source/hash pointers that still test current continuity. Old release branches/tags hold old design documents. Old migration filenames, real compatibility aliases, copyright and changelog entries are **live obligations**, not confusing architecture remnants to be renamed blindly.

## Determinism does not replace migration qualification

`MIG-04` — The migration input includes the save's applied migration-name history, not just its research levels. Equal complete input must yield equal output. An exactly-once engine migration and an idempotent reconciliation function have different tests. Never reset migration history as a shortcut.

Do not open and save a real full-catalogue world with a one-family experimental package. Early slices use disposable fixtures. A preserved prototype ID with changed effect recipes, initial level or per-level scalar may still lose meaning; compare the earned native/physical outcome, not only names. See [determinism](determinism.md).
