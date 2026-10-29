---
title: "Support and upgrade boundaries"
status: current
applies_to: "MIR development"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-29
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-support-guide
---

# Support and upgrade boundaries

## Current scope versus intention

The replacement is under development. This documentation does not announce a released MIR 5 package, completed migration, universal mod support or measured speedup. Use the actual published release and its stated limitations until a qualified replacement is available.

Stable replacement scope must retain delivered applicable research, settings, effects, native continuations, prototype overrides, scripted features, the Library, bundled integrations and each supported engine edition's actual subset. New unimplemented ideas remain the original backlog; they are not silently marked complete.

An ecosystem name is not a test result. Support records should identify exact Factorio and upstream versions/settings, whether the technology is present, researchable, effective, physically productive, upgrade-safe, reload-safe, multiplayer-tested and performance-measured. Load-only evidence is labelled load-only.

## Candidate editions

Factorio **2.1 with minimum base 2.1.23 (F210)** is the primary design target. The nine stable editions retain their actual capability subsets and the existing version encoding, composed from shared source and narrow adapters. Every stable delivered edition requires final current-package and affected native qualification; records distinguish each edition's observed results and remaining gaps. Primary-target priority does not qualify an earlier stable edition or remove its release obligations.

The [tracked edition record](../targets/editions.json) selects one self-contained player ZIP for each stable engine family plus the F018 experimental build. The following are selected baseline engine minimums; they do not announce completed final-package acceptance. F018/0.18.47 is GitHub-only best effort: its source/build port is integrated, but only correct metadata/package information and an actual0.18 native load/crash smoke are in scope, not an upgrade recommendation. For stable upgrades, select the same engine family rather than another target's ZIP because its distribution number is larger.

| Target | Factorio family | Minimum base | MIR5 distribution |
|---|---|---|---|
| F210 | 2.1 | 2.1.23 | 5.0.21000 |
| F200 | 2.0 | 2.0.77 | 5.0.20000 |
| F110 | 1.1 | 1.1.110 | 5.0.11000 |
| F100 | 1.0 | 1.0.0 | 5.0.10000 |
| F018 | 0.18 | 0.18.47 | 5.0.01800 — GitHub-only experimental; native load/crash smoke pending |
| F017 | 0.17 | 0.17.79 | 5.0.01700 |
| F016 | 0.16 | 0.16.51 | 5.0.01600 |
| F015 | 0.15 | 0.15.40 | 5.0.01500 |
| F014 | 0.14 | 0.14.23 | 5.0.01400 |
| F013 | 0.13 | 0.13.20 | 5.0.01300 |

Modern targets expose recipe productivity and the Research Library. Expansion research requires its actual official mods and available science/labs. Historical editions retain their supported direct-effect subset; they do not acquire modern recipe productivity, Library or expansion capabilities. F013/F014 lack the later numeric infinite-level readback, and F013–F016 lack native research queues. The [research and settings reference](../README.md#research-catalog) retains the complete authored catalogue detail; exact profile admissions and omissions are named in the qualification records.

## Additional best-effort historical builds

GitHub packages keep extended versions; only final copies of the nine stable editions receive Portal numbering. Both channels use the same qualified gameplay. Use one channel, or explicitly select/replace the intended package when switching:5.0.21000 sorts above5.0.09, so automatic update selection is not a channel-transfer guarantee.

The separately selected [early-edition record](../targets/early-editions.json) builds F006/0.6.4, F007/0.7.5, F008/0.8.8, F009/0.9.8, F010/0.10.12, F011/0.11.22 and F012/0.12.35. These are data-only fixed finite research subsets recovered from the museum releases, with14/22/22/22/22/22/26 technologies respectively. They have no startup settings, runtime API, Library or migrations, and have not passed current native or save qualification. They are best-effort GitHub artifacts outside the normal-edition native acceptance claim. F006–F008 transport ZIPs require extraction into the engine mods folder; do not infer direct ZIP loading. Preserve original saves and installation files.

F001/0.1.2 and F002/0.2.10 lack an evidenced standalone-mod format. F003/0.3.2, F004/0.4.1 and F005/0.5.3 lack supplied exact engine/prototype inputs, so no build or native pass is claimed. F018/0.18.47 is selected for a permanent GitHub-only experimental package, not a stable or Portal edition. It reuses F100 mechanics and compatible inputs only where justified, has metadata/package and actual native load/crash-smoke scope, and does not inherit an F100 native result or stable save/modpack/science/client/performance obligations. Its missing0.18 engine/input does not block the nine stable editions. Missing editions are recorded explicitly instead of filled with empty packages. The [target contract](../spec/targets.md#additional-historical-editions) owns these limits and their release disposition.

## First upgrade

Keep the original save, its pre-update backup, the selected mod archives and startup settings. Test a copy with the matching edition first. Preserve inherited settings for the first load; configuration changes and productivity-provider changes have separate transition requirements. Load, inspect earned research and bonuses, inspect current/queued or suspended work, save under a new name and cold-reload that copy before adopting it.

MIR 5 is still unreleased. Release qualification prioritizes 4.7.3 predecessor saves on all stable editions and older representatives covering known changes to identities, effects, settings, schemas and ownership. The complete modern-origin inventory remains, but an uncertain older route can be deferred explicitly instead of guessed; not every historical patch has passed a native upgrade. The [migration scope](../spec/migrations.md#required-origin-coverage) distinguishes qualified routes, engine bridges and deferred inputs. Future MIR 5 stable forward-upgrade obligations remain. Earlier pre-5 origins on 1.1 and below are best effort beyond the required 4.7.3 routes. Check the actual release evidence and limitations before adopting a candidate on a real factory.

The candidate refuses a first published F2004.7 upgrade when earned overlapping productivity has no recorded MIR5 preference baseline, startup settings changed, and a known productivity provider is present or being removed. This also applies when moving directly from Factorio2.0 to2.1. Keep the original save: first evaluate the matching MIR5 F200 candidate on the original2.0 engine with the original mods and startup settings, then save and cold-reload that copy before changing the engine, provider or preference. The refusal protects research whose old preference cannot be inferred safely. The [exact4.7.3 two-step preference case](../spec/evidence/legacy-preference-473-current7a2-native-chain-r01.json) now observes both initial preferences with its four pinned providers: simultaneous first switches refuse, unchanged-settings upgrades save successfully, and later preference switches preserve earned credit while completing new research. Other provider/DLC/settings combinations remain unverified. The [migration policy](../spec/migrations.md#finite-transition-policy) keeps this route separate from the provider-free Base engine hop and the earlier4.7.2 observations; each retains its original package and profile inputs.

A cap below earned research limits future work without erasing earned levels. MIR restores only disablement it owns; another mod's configuration callback can independently reset technology state. Hidden migration carriers preserve named historical investments and must not be removed as cosmetic clutter. The retained [recovery guidance](../README.md#save-compatibility) and original incident records remain relevant to previously resaved factories: restoring a missing definition cannot reconstruct history already erased from a save.

Use the Research Library shortcut on modern targets to inspect research, queues, settings and availability. Its search/filter and language preferences belong to each player. Queue actions use native research behavior; the Library is not a second research planner. Startup settings take effect on the appropriate restart, and exporting a settings profile does not silently change the active game configuration.

## Observed same-edition upgrade cases

The following named cases have actual published4.7.3 source,successor-save and two cold-reload observations. They describe tested saved state,not complete qualification of nine editions or arbitrary factories. The [finite origin inventory](../spec/inventory/migration-origins.json) retains exact archives,engines,fixtures and original verdicts. The [fbb7 historical-package comparison](../spec/evidence/current-fbb7-historical-applicability-r01.json) retains its exact changelog-only boundary. The [corrected7b0 package readback](../spec/evidence/current-7b0-aero-independent-readback-r01.json) additionally records three unused German Library strings in the seven stable historical editions; their player logic remains identical. The [bounded non-GUI applicability review](../spec/evidence/current-7b0-nongui-aero-applicability-r01.json) preserves each named gameplay/save result under its original execution identity. Modern changed display/client paths retain separate current-package qualification.

| Edition | Observed saved-state case | Scope limit |
|---|---|---|
| F210 | [Base and Space Age catalogue/effects,queued and detached work,new research,save and reload](../spec/evidence/full-catalogue-473-current38c-native-chain-r01.json) | Separate exact profiles; no automatic DLC or provider-switch claim. |
| F200 | [Base catalogue/effects and saved work](../spec/evidence/full-catalogue-473-f200-current7a2-native-chain-r01.json),plus the [selected Space Age preference/provider route](../spec/evidence/legacy-preference-473-current7a2-native-chain-r01.json) | The provider case exercises its selected breeding/preference boundary,not the complete Space Age catalogue. |
| F110 | [Retained research/effects,capacity bonuses,queue and detached work,new mining research](../spec/evidence/f110-473-current7a2-native-chain-r01.json) | Broader settings,modpacks and physical production remain separate. |
| F100 | [Mining preservation,new research,queue and partial work](../spec/evidence/historical-473-f017-f100-7a2-native-chain-r01.json) | This published-source case is separate from the [MIR5 F100-to-F110 laser bridge](../spec/evidence/f100-f110-laser-native-chain-r03.json). |
| F017 | [Mining preservation,new research,queue and partial work](../spec/evidence/historical-473-f017-f100-7a2-native-chain-r01.json) | Named mining/state case,not a full historical modpack. |
| F016 | [Mining preservation,new research and partial work](../spec/evidence/historical-473-f016-7a2-native-chain-r01.json) | This engine has no native research queue. |
| F015 | [Mining preservation,new research and partial work](../spec/evidence/historical-473-f015-7a2-native-chain-r01.json) | This engine has no native research queue. |
| F014 | [Mining-bonus preservation,save and reload](../spec/evidence/historical-473-f014-f0dd-native-chain-r01.json) | No later numeric infinite-level readback or invented continuation. |
| F013 | [Mining-bonus preservation,save and reload](../spec/evidence/historical-473-f013-f0dd-native-chain-r01.json) | No later numeric infinite-level readback or invented continuation. |

For engine changes,the separately observed [F110-to-F200](../spec/evidence/f110-f200-current7a2-native-chain-r01.json) and [F200-to-F210 Base](../spec/evidence/full-catalogue-473-f200-current7a2-native-chain-r01.json) routes reuse their protected originals. The [F100-to-F110 laser case](../spec/evidence/f100-f110-laser-native-chain-r03.json) starts from a fresh MIR5 F100 save and tests the laser identity/effect-category rename;it is not a published MIR4 laser save. Uncertain older histories,unselected DLC/provider permutations and best-effort editions retain their explicit limits.

## Researched planet still locked

MIR preserves ambiguous locks rather than deciding that another mod was wrong. For a deliberately chosen one-time repair on Factorio 2.1 Space Age, first confirm that no active mod intends that lock. The following player-console example targets only your current force and Vulcanus, and only when the current researched technology contains the matching native unlock effect. It leaves unresearched discoveries and other forces alone. The [LuaForce API](https://lua-api.factorio.com/latest/classes/LuaForce.html#unlock_space_location) provides the operation; the methods are also present in the locally inspected 2.1.23 API documentation. This is operator recovery guidance, not a MIR migration qualification result.

Lua console commands permanently disable achievements for that save, so use a copy; see the [official console documentation](https://wiki.factorio.com/Console#Scripting_and_cheat_commands).

```lua
/c local f=game.player.force; local n="vulcanus"; local t=f.technologies["planet-discovery-"..n]; for _,e in pairs(t and t.researched and t.prototype.effects or {}) do if e.type=="unlock-space-location" and e.space_location==n and not f.is_space_location_unlocked(n) then f.unlock_space_location(n) end end
```

For another official discovery, replace `vulcanus` with `gleba`, `fulgora` or `aquilo`. In a server console, explicitly select the intended force with `game.forces["force-name"]` instead of `game.player.force`. If the current technology has no matching native grant, the example does nothing; retain the save and report that configuration rather than inventing an association or granting research. An existing native upgrade may already restore the location without any operator repair.

## Recovery from the 4.2.1 incident

This procedure retains the historical4.2.2 hotfix scope. It is not a MIR5 upgrade pass and does not change current edition requirements.

> **Upgrade and recovery:** Use the [4.2.2 hotfix](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.2) directly from 4.2.0 or 4.2.1; do not install 4.2.1 as an intermediate step. Preserve original saves and pre-update backups. If you already saved after 4.2.1 removed research, restored definitions cannot recreate erased levels or bonuses: load a copy of your pre-update backup directly with 4.2.2 to retain that history. A whole backup returns the factory to its saved point. Do not remove MIR or downgrade an already-resaved factory as an assumed recovery. See [issue #621](https://github.com/Julesc013/more-infinite-research/issues/621) and the [hotfix notes](https://github.com/Julesc013/more-infinite-research/releases/download/v4.2.2/release-notes.md) for the tested scope and remaining limits.

## Safe diagnosis

Record Factorio/MIR version, exact archive identity where reissues existed, enabled mods/settings, the relevant log and a reproducible save when shareable. Preserve originals. Do not ask a player to repeatedly risk their only save, downgrade a resaved factory or disable a required mod as an assumed recovery.

On modern editions, the Library Settings tab offers **Export Settings** and **Export Compact**. Full export records effective MIR settings and is the support default; compact export omits defaults, so its meaning can change when defaults change between versions. The selectable MIRSET1 string is the same representation written to `script-output/more-infinite-research/settings/mir-settings-profile.txt`. Strings above the 1 MiB preview limit remain complete in that file. The existing `/mir-settings-export` and `/mir-settings-export --compact` commands use the same exporter. Validate a shared string with `/mir-settings-import-check <profile-string>`, then explicitly paste it into `mir-settings-profile-import` and restart to apply it. Exporting and validating never apply settings or change research; a MIR profile is not a backup of other mods, map settings or saved research.

The Library Debug tab's **Export Diagnostics**, or `/mir-diagnostics-export`, replaces `script-output/more-infinite-research/mir.log` and exports full MIR settings. This latest report is bounded to 64 KiB, at most512 active-mod entries and32 queued-research entries, with omissions labelled. It records versions, effective-settings information and the requesting player's selected/native research state; native totals are not attributed exclusively to MIR. The complete settings file remains separate when its string is too large for the report. Output is local to the requesting player; server-console output explicitly targets the server. File-write failures report an error without changing gameplay state. A partial export can leave its already-written settings file intact.

The small automatic header is replaced after MIR initialization or configuration change. It is not an operating-system launch transcript and is not rewritten by `on_load`, research events, UI refreshes or periodic work. Factorio manages `factorio-current.log` and its previous-run log; attach the current engine log separately for complete session, startup and crash evidence, including failures before MIR can run. The mod cannot read or copy that file. Test/support launchers should preserve logs once after completion or failure, before another run rotates them.

Review exports before sharing: profile metadata includes `exported_by`, while engine logs can contain usernames and local paths. No export uploads anything automatically. Keep verbose binding diagnostics separate from normal-logging acceptance measurements.

For a new optional unsupported addition, MIR can omit that addition with a useful reason. Existing earned research requires a preservation/migration decision. A crash suppressed by deleting the technology is not a fix.

## Relevant retained incident subjects

Science trigger/output chains and independently available alternatives; specialist/resource science and labs; native-owner collisions; staged material/K2 progression; hidden credit carriers; caps and uncapping; foreign force offsets; manufacturing versus mining; settings imports and zero/inherit values; module/recycling safeguards; runtime registration; personal Library views and stale translations.

The original request/issue IDs and independent expected behavior must remain discoverable after source cleanup. Keep small current tests and pinned historical references, not old contradictory architecture documents in the active tree.

## Performance claims

Report whole-game startup separately from MIR-added startup. Headless creation/save, responsive menu, save load, first Library use and simulation are separate measurements. A one-technology demo or source-size reduction cannot establish the full replacement's performance. Missing data is inconclusive, not a proof of non-regression.
