---
title: "Current Factorio 2.1 API Review for MIR 4.2"
status: current
applies_to: "4.2.0 development / Factorio 2.1.20"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir42-current-engine-api-review
---
# Current Factorio 2.1 API review

This is an applicability review for A23, not engine or ecosystem qualification. The [official API index](https://lua-api.factorio.com/) listed 2.1.20 as latest experimental and 2.0.77 as latest stable when observed on 27 September 2026. The installed Steam engine and its bundled official JSON APIs/changelog were reobserved after the maintainer's playtest. Historical engines remain in `D:\Programs\Factorio`; no engine was downloaded or retargeted. Future identity changes enter the existing [experimental-channel authority](../../spec/engines/mir4-factorio-2.1-experimental-channel-v1.json).

| Input | SHA-256 |
| --- | --- |
| Steam `bin/x64/factorio.exe`, 2.1.20 | `E4B1FDBDCC77F4C3449318CE1398493EA7A8E77A19D68BD1AC3A858D0F373B92` |
| Bundled `doc-html/runtime-api.json`, API schema 6 | `1FF275CC085347FAFDDC01B5BA53DF10259319339E78CD6E5B4E0D067E1DAEB6` |
| Bundled `doc-html/prototype-api.json` | `5D2AAB6483F33D1582D2FDFD661B4B9F6FF6A1F97548311524D062ECC32F200B` |
| Bundled `data/changelog.txt` | `20F980C654DD0D3CDE1BDF3DEEF606F6B000E3238CF69C7A21E3CD83BFA66392` |

The bundled changelog supplies all fourteen patch sections, 2.1.7 through 2.1.20, matching the versions in the official index. The [official data repository changelog](https://github.com/wube/factorio-data/blob/master/changelog.txt) is the moving upstream reference. Local extraction is preserved under `build/tmp/mir42-integration/api-current-review/patch-sections.json`. A direct shell download of versioned JSON was blocked by the execution context; this review does not claim a downloaded fourteen-version API diff. Versioned official documentation was browsed for the baseline/current API family, and concrete signatures were read from the bound local APIs.

| Patch | Relevant review and disposition |
| --- | --- |
| 2.1.7 | Research/labs accept any item type; recipe categories become arrays; product probability and quality contracts change; per-prototype effect limits become available. Existing platform profiles, item/lab admission, recipe facts and prototype-limit implementation already cover these contracts. Keep those adapters shared and preserve old-engine forms. Translation requests gain offline/eventual-delivery behavior; pending IDs must remain safe through disconnects and stale callbacks. New inventory GUI, electric networks and notification queues have no demonstrated need in the current library or cap controller. |
| 2.1.8 | Larger technology-price multiplier domain must remain a native setting rather than a MIR clamp. Per-entity verbose benchmark output is available for later entity-performance diagnosis; it does not measure command time by itself. Use `LuaProfiler` for the reported mass-research command. |
| 2.1.9 | Factoriopedia visibility controls are player options. The MIR library must preserve them rather than taking ownership of the native encyclopedia's preferences. |
| 2.1.10 | Lua module-path deduplication is an engine fix. Canonical materialization already uses stable imports; avoid introducing alternate relative spellings. Mac sprite-loading improvements require no MIR mutation. Pin and construction APIs do not solve the reported browser/per-research validation costs. |
| 2.1.11 | Hidden/occluded simulation rendering is optimized by the engine. MIR's browser does not need simulations to present its research catalogue. |
| 2.1.12 | Crafted-recipe events and quality rolling are available for mechanisms that require them. Recipe productivity already uses native research effects, so adding per-craft Lua callbacks would introduce unnecessary work. Editor-setting APIs have no player-library requirement. |
| 2.1.13 | `LuaEntity.local_effect` and quality-roll inspection are potential mechanisms for the distinct machine/quality requests. They require explicit ownership, limits, lifecycle and performance proof before gameplay admission; they are not blanket authorization for global entity mutation. Platform-list queries and burner inspection remain available where a future admitted consumer needs them. |
| 2.1.14 | Bugfix patch; no new MIR-consumed API contract identified. Keep the current engine's fixes through ordinary target qualification. |
| 2.1.15 | Native belt-capacity prerequisites changed. Read the finalized native research graph instead of replacing it with old prerequisite assumptions. Runtime opening still supports native technology deep links; its extra GUI types do not provide a technology-tree extension anchor. Circuit graphics and item-group changes are irrelevant to MIR's current prototype-free browser icons and scalar DTOs. |
| 2.1.16 | Bugfix patch; no new MIR-consumed API contract identified. |
| 2.1.17 | Lab selection/control behavior fixes affect the installed engine. Preserve native lab/research ownership and qualify current science frontiers rather than assuming the old 4.1 engine behaves identically. |
| 2.1.18 | Item science capacity and quality capacity multipliers extend research consumables. Existing item/lab admission is not limited to tools. MIR does not rewrite upstream capacity/durability values. Native Health prerequisites changed; consume final prototypes. `migrates_from` is unnecessary because stable MIR mod/storage identities are preserved. Secondary GUI numbers may be used only if a concrete library task benefits. Research-window/multiplayer/hidden-research fixes still require actual player checks; a headless pass does not prove them. |
| 2.1.19 | Bugfix patch; no new MIR-consumed API contract identified. |
| 2.1.20 | Fuel category changes are a real external-mod compatibility boundary. MIR has no product references to the removed fuel-category field or spectator API. Old Bob/Angel/AAI archives that use removed fields must not be called current-engine compatible or silently patched as support evidence. Space-map presentation additions have no current research-library consumer. |

`LuaPlayer.request_translations` exists in the installed 2.0.77 API as well as 2.1.20. Batch dispatch is therefore not a new 2.1-only feature. Native localized GUI captions supply visible names immediately; asynchronous translation is still needed for plain-text search and name ordering. Correct indexing, bounded outstanding requests and stable rendering are the current implementation priorities, not API novelty.

Existing adoption is evidenced by `source/adapters/f210/prototypes/mir/platform/factorio/target_profiles.lua`, `source/prototypes/mir/index/recipe_facts.lua`, `source/prototypes/mir/capabilities/science_integration/pack_registry.lua`, `source/prototypes/mir/pipeline/prototype_limits.lua` and their governed checks. The item/tool admission cases in `tests/compiler/researchability_planning.lua` are exact controlled evidence, not qualification of every overhaul's science chain.

Remaining work stays in A23/A20 and the existing capability programme: assess consumer-specific uses of local effects/quality APIs, bind meaningful tests for any resulting implementation, and rerun only affected propositions. The current performance and library fixes are tracked separately in [the maintainer's playtest findings](../releases/mir42-playtest-findings.md).
