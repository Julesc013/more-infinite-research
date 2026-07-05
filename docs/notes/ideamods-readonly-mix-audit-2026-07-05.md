# Local Idea Mods Audit - 2026-07-05

Source library: `C:\Projects\Factorio\ideamods_readonly_mix`

Text-only working copy used for code reading: `tmp/ideamods-text-audit-20260705/`

Scope: 50 downloaded archives, 49 unique mod/version pairs. `Research_Productivity_1.1.3.zip` and `Research_Productivity_1.1.3 (1).zip` are duplicate archives. The set mixes Factorio `2.0` and `2.1` targets. `research-cost-curve` has an unusual `info.json` shape but its source was still readable.

## Executive Summary

The safe `2.1.5` work is narrow and now implemented:

- Add known-competitor profiles for exact infinite recipe-productivity overlap where MIR already has a matching stream and matching `change` value.
- Skip MIR's base-game lab-productivity stream when `Research_Productivity` provides the native infinite `laboratory-productivity-4` chain.
- Do not absorb balance-heavy finite chains, module/beacon/productivity-rule mutators, research cost tools, or runtime productivity systems into `2.1.5`.

The main `2.2.0` discussion is not "copy these mods." The useful pattern is to turn their demand signals into a compatibility planner backlog: tile/surface productivity variants, ore-crushing families, overhaul material taxonomies, cap-aware UX, native modifier overlap policy, and companion-mod boundaries for beacon/module rule mutation.

## Shipped In 2.1.5

These changes use existing MIR safety checks. A profile only marks a technology name as a known competitor; replacement still requires an active infinite technology, exact recipe-productivity effects, exact `change` values, enabled MIR replacement effects, lab-compatible replacement science, and no blocking external owner.

| Mod | External technology shape | MIR action |
| --- | --- | --- |
| `bioflux-productivity` | `bioflux-productivity`, `bioflux`, `+0.10` | Known competitor profile. |
| `fish-productivity` | `fish-breeding-productivity`, `fish-breeding`, `+0.10` | Known competitor profile. |
| `Science_packs_productivity` | Official science pack `*-science-productivity-4`, `+0.10` | Known competitor profile for the infinite level only. |
| `ProductivityResearch` | `sem-prfe_<recipe>-productivity-1`, `+0.10` | Known competitor profile. |
| `ProductivityResearchForEveryone` | `sem-prfe_<recipe>-productivity-1`, `+0.10` | Known competitor profile. |
| `ProductivityResearchForEveryoneFG` | `sem-prfe_<recipe>-productivity-1`, `+0.10` | Known competitor profile. |
| `ExpandedProductivityResearch` | `epr_<item>-productivity-<level>`, usually `+0.10` | Known competitor profile, still exact-coverage guarded. |
| `crafting-efficiency-2` | `ce-<name>-<level>`, staged final infinite chain | Known competitor profile, still exact-coverage guarded. |
| `Research_Productivity` | `laboratory-productivity-4`, native `laboratory-productivity +0.10` | MIR lab productivity skips when this chain exists. |

Notably excluded from `2.1.5`: `concrete-productivity`, `landfill-productivity`, `foundation-productivity`, and `productivity_tech_modules`. They overlap with MIR concepts but use different per-level values or balance models, so silently replacing them would change gameplay.

## Mod-By-Mod Findings

| Archive | What it does | MIR stance |
| --- | --- | --- |
| `5dim_mining_2.0.3` | Adds high-tier mining drills, pumpjacks, water pumpjacks, and offshore pumps. | Compatible/adjacent. MIR may pick up visible drill recipes through Mining Drill Productivity; no direct absorption needed. |
| `asphalt-productivity_1.0.1` | Adds infinite `Arci-asphalt` recipe productivity at `+0.50`. | Defer. New tile/surface stream candidate if asphalt should become first-class. |
| `base-prod_0.0.2` | Mutates base productivity/prototype productivity behavior. | Adjacent rule mutation; keep out of MIR core unless a companion mod is planned. |
| `bioflux-productivity_0.1.0` | Adds one infinite Bioflux recipe-productivity technology. | Shipped as exact known-competitor profile. |
| `combatresearchtech_0.1.0` | Grants research progress from enemy kills. | Compatible runtime utility; no MIR code needed. |
| `concrete-productivity_1.2.1` | Adds concrete/refined-concrete productivity chain, infinite level uses `+0.25`. | Defer. MIR has concrete coverage but different balance; do not replace. |
| `crafting-efficiency-2_0.3.0` | Generates staged recipe productivity for selected recipe groups and expansions. | Shipped as guarded known-competitor profile for exact matches only. |
| `crushing-industry-productivity-research_1.0.6` | Adds ore/crushing productivity for Crushing Industry and forces ore crushing on. | Defer. Good `2.2.0` stream candidate for ore crushing. |
| `ExpandedProductivityResearch_1.3.8` | Broad configurable generator for productivity techs, including science packs and many recipe categories. | Shipped guarded known-competitor profile; broader absorption needs planner work. |
| `finite_prod_techs_0.1.0` | Converts infinite productivity techs to finite levels based on recipe productivity caps. | Compatible but order-sensitive. Consider cap-aware UX in `2.2.0`. |
| `fish-productivity_1.0.0` | Adds infinite fish-breeding recipe productivity. | Shipped as exact known-competitor profile. |
| `foundation-productivity_1.1.1` | Adds infinite foundation recipe productivity at `+0.25`. | Defer due balance mismatch with MIR's lower foundation gain. |
| `landfill-productivity_1.0.2` | Adds a landfill productivity chain, final infinite level at `+0.50`. | Defer due balance mismatch with MIR landfill gain. |
| `miner-start_1.0.0` | Adds a starter mining productivity technology/bonus. | Compatible; separate from MIR recipe-productivity streams. |
| `mining-prod-0_1.0.2` | Inserts an early `mining-productivity-0` technology before vanilla mining productivity. | Compatible; no MIR overlap. |
| `modified-productivity-cap_1.2.2` | Lets startup settings change recipe `maximum_productivity`. | Compatible cap mutator; consider cap diagnostics, not absorption. |
| `more-productivity-research_1.0.1` | Adds finite science-pack productivity chains. | Compatible; do not remove finite lead-ins. |
| `Prod-Beacon_1.0.3` | Adds a productivity beacon prototype. | Adjacent/companion territory; no MIR core change. |
| `prodforce_0.0.8` | Forces productivity/quality allowed effects onto machines and recipes. | Adjacent rule mutation; keep out of MIR core. |
| `Productivity_2.0.5` | Broadly enables productivity for recipes. | Compatible as a producer of more productivity-allowed recipes; no direct profile. |
| `productivity_fix_2.0.0` | Allows productivity in beacons/recycler and broad recipe productivity. | Adjacent rule mutation; keep out of MIR core. |
| `productivity_tech_modules_0.0.3` | Adds module recipe-productivity technology at `+0.10` for all tiers. | Defer. MIR has tiered lower values, so exact replacement is unsafe. |
| `productivity_weight_fix_0.0.2` | Adjusts productivity-related weight behavior. | Compatible utility; no MIR action. |
| `Productivity-config_0.1.1` | Configurable productivity allowances. | Adjacent rule mutation; no MIR core change. |
| `productivity-indicator_1.0.0` | UI/indicator for productivity. | Compatible UI utility; no MIR action. |
| `productivity-module-3-aquilo_1.0.4` | Moves or enables productivity module 3 access on Aquilo. | Compatible progression tweak; no MIR action. |
| `productivity-technology-limit_0.0.2` | Limits productivity technologies by recipe cap and prior productivity. | Compatible but order-sensitive. Useful input for cap-aware `2.2.0` UX. |
| `productivity-through-science_1.1.0` | Runtime recipe productivity bonus per researched technology. | Different mechanic. Compatible conceptually but not something MIR should absorb directly. |
| `ProductivityResearch_2.1.0` | Broad recipe-productivity generator with `sem-prfe_` technology IDs. | Shipped guarded known-competitor profile. |
| `ProductivityResearchForEveryone_1.0.9` | Earlier `sem-prfe_` broad recipe-productivity generator. | Shipped guarded known-competitor profile. |
| `ProductivityResearchForEveryoneFG_1.2.0` | Fork with staged science-pack settings for `sem-prfe_` generator. | Shipped guarded known-competitor profile. |
| `progressive-productivity_1.1.5` | Runtime productivity improves as production statistics rise. | Different mechanic with runtime scanning; keep out of MIR core. |
| `py_productivity_1.3.0` | Hand-authored Pyanodon productivity families for alloys, biomass, casting, glasswork, smelting, and more. | Defer. Good evidence for overhaul family streams, but only with concrete recipes. |
| `remove-productivity-cap_1.1.1` | Sets recipe `maximum_productivity` extremely high. | Compatible cap mutator; no direct action. |
| `Research_Productivity_1.1.3` | Adds native laboratory-productivity finite levels and infinite `laboratory-productivity-4`. | Shipped skip so MIR does not duplicate native lab productivity. |
| `Research_Productivity_1.1.3 (1)` | Duplicate of the same archive/version. | No separate action. |
| `research-control-tower_1.3.1` | Circuit-controlled automation for choosing infinite research. | Compatible with MIR infinite techs; no core absorption. |
| `research-cost-curve_0.1.4` | Runtime science-cost multiplier curve after research completion, plus fixed startup cost option. | Compatible but broad cost policy belongs outside MIR. |
| `research-fixer_1.0.6` | Adds missing science prerequisite links inferred from science ingredients. | Generally compatible; MIR already generates prerequisites but may be touched by it. |
| `research-multipliers_0.2.0` | Startup research cost multipliers by pack, infinite status, planet, and individual tech. | Compatible cost mutator; order-sensitive, not MIR scope. |
| `research-skip_1.0.1` | Unlocks early/midgame technologies at game start or by command. | Compatible progression utility; no MIR action. |
| `ResearchProductivity_Rebalance_1.0.0` | Rebalances Space Age `research-productivity` cost/time. | Compatible when Space Age owns that chain; MIR already skips `research-productivity`. |
| `rosnok-productivity-quality-beacon_1.1.2` | Allows productivity and quality in beacons. | Adjacent rule mutation; companion territory. |
| `SchallModules_2.0.0` | Adds module tiers/options and mutates allowed beacon effects. | Adjacent module ecosystem; MIR may see recipes but should not absorb module rules. |
| `Science_packs_productivity_0.0.1` | Adds finite plus infinite official science-pack productivity chains. | Shipped guarded profile for infinite level-4 owners only. |
| `show-missing-bottles-for-current-research_2.0.2` | UI overlay for missing current research ingredients. | Compatible UI utility; no MIR action. |
| `solar-productivity_3.0.0` | Adds finite solar/accumulator efficiency research via runtime entity upgrades. | Defer/reject for MIR core unless a bounded native/prototype model exists. |
| `space-exploration-spaceproductivity-2_0.1.2` | Allows productivity in Space Exploration space machines, recipes, and beacons. | Adjacent Space Exploration rule mutator; no MIR core action. |
| `UnlimitedProductivityFork_2.1.0` | Removes productivity restrictions, allows productivity/quality in beacons, tunes beacon settings. | Adjacent rule mutation; likely companion scope, not MIR core. |
| `zz-long-science_2.0.0` | Progressively increases technology cost multipliers as research is completed. | Compatible cost mutator; outside MIR core. |

## 2.2.0 Backlog Candidates

1. Tile/surface productivity policy.
   Asphalt, concrete, landfill, and foundation mods show demand for tile productivity, but they disagree on per-level values. MIR needs either conservative per-stream defaults or explicit balance presets before absorbing them.

2. Ore-crushing stream.
   `crushing-industry-productivity-research` is a clean signal for a recipe-family stream based on Crushing Industry ore/coal/calcite/stone crushing. This should be recipe-ID driven, not a broad name match.

3. Overhaul material families.
   `py_productivity`, `crafting-efficiency-2`, and `ExpandedProductivityResearch` show demand for alloy, casting, glass, biomass, and mod-family productivity. MIR should add only concrete families that can be validated against visible recipes.

4. Cap-aware UX.
   `finite_prod_techs`, `productivity-technology-limit`, `remove-productivity-cap`, and `modified-productivity-cap` show players care about the productivity cap. MIR could add warnings, diagnostics, or an optional finite-level policy, but should avoid silently changing caps.

5. Native modifier overlap policy.
   `Research_Productivity`, Solar Productivity, and mining starter mods reinforce the existing need for a skip/warn/prefer/allow policy for native modifiers and scripted effects. Only the lab skip is narrow enough for `2.1.5`.

6. Companion boundary.
   Beacon/module/productivity-rule mutators are popular, but they change factory rules rather than add research streams. Keep them compatible in MIR core; consider a companion mod only if this becomes a deliberate product direction.

## Validation Notes

The `2.1.5` implementation deliberately does not add new recipes to MIR streams. It only teaches the existing competitor-cleanup path about known external infinite technology names and skips a directly overlapping native lab-productivity owner. Runtime load validation with these exact external zips remains recommended before publishing if the local Factorio binary and dependency libraries are available.
