# Idea Mods Feature Audit - 2026-07-05

Source library: `C:\Projects\Factorio\ideamods_mix`

Test-mod sync targets:

- `C:\Projects\Factorio\testmods_2.0`
- `C:\Projects\Factorio\testmods_2.1`

Audited archive count: 59 zip archives.

Checksum ledger: `docs/audited-zips-2026-07-05.json`

Audit method: text-only extraction of source/config files from each archive, then
manual review of technology effects, runtime scripts, startup settings, recipe
changes, cap changes, allowed-effect mutations, and metadata.

This file is the decision surface for choosing what MIR should recreate,
cooperate with, diagnose, or deliberately leave alone. It is not a promise to
absorb every mod. Most entries are compatibility signals.

## Decision Vocabulary

| Decision | Meaning |
| --- | --- |
| Recreate in MIR | The idea fits MIR, but implementation must be MIR-owned, fixture-backed, and not copied from the source mod. |
| Exact cleanup only | MIR can remove or skip only the exact overlapping infinite owner already covered by the guarded `2.1.5` model. |
| Compatible only | MIR should load alongside the mod and avoid false claims of replacement. |
| Diagnose only | MIR should report caps, duplicate native owners, wasted infinite levels, or rule mutation without changing behavior. |
| Companion only | Useful idea, but outside MIR core because it changes machine, module, beacon, productivity-rule, or runtime semantics. |
| Do not touch | Keep out of MIR core unless a future design deliberately changes MIR's product boundary. |

## Executive Cut

Keep `2.1.5` narrow. The current release should remain guarded duplicate cleanup
plus effect-backed lab-productivity skip.

Use `2.2.0` for designed, fixture-backed work:

1. Compatibility planner and diagnostics.
2. Cap-aware productivity diagnostics.
3. Ore-crushing productivity if exact visible recipe fixtures pass.
4. Tile/surface productivity policy before any tile stream ships.
5. One narrow overhaul material-family prototype, not a generic productivity generator.
6. Native direct-effect overlap policy, kept smaller than the broad idea-mod pile.

Do not clone rule mutators, runtime productivity systems, research-cost systems,
beacons, broad module changes, or radar/logistics content into MIR core.

## Per-Mod Decisions

### `5dim_mining_2.0.3.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds a large mining-content layer, including ten tiers of electric mining drills, pumpjacks, water pumpjacks, and offshore pumps through the `5dim_core` ecosystem.
- Technologies and bonuses: Content progression for higher-tier mining machinery. It is not a simple MIR-style productivity research owner.
- How it works: Adds many prototypes and recipes as a content mod. Any productivity interaction is indirect through recipes and machines it introduces.
- MIR action: Support loading alongside it. Do not claim replacement. Later overhaul/material-family work may pick up visible recipe IDs from this mod only through fixtures.

### `all_around_research_0.0.2.zip`

- Primary role: `MIR_COMPAT_ADAPTER`.
- What it does: Adds several very broad infinite research packages that combine recipe productivity, native force modifiers, character bonuses, logistics stack bonuses, robot bonuses, combat bonuses, and cargo landing pad count.
- Technologies and bonuses:
  - `all-productivity-yyy`: broad `change-recipe-productivity` effects at `+0.10` for many base and Space Age recipes, plus `train-braking-force-bonus`, `laboratory-productivity`, `laboratory-speed`, and `mining-drill-productivity-bonus`.
  - `character-setting-yyy`: character running speed, inventory, health, mining speed, crafting speed, build distance, loot pickup distance, item drop distance, item pickup distance, reach distance, and resource reach distance.
  - `inserter-stack-size-yyy`: inserter stack size, belt stack size, and bulk inserter capacity.
  - `robots-setting-yyy`: worker robot storage, battery, speed, follower count, and follower lifetime.
  - `weapons-setting-yyy`: many ammo damage, gun speed, turret attack, artillery range, and combat modifier effects.
  - `cargo-landing-pad-num-yyy`: cargo landing pad count.
- How it works: Hand-authored infinite technologies bundle many unrelated modifier types into a few very broad techs. It is intentionally much broader than MIR's current recipe-productivity stream model.
- MIR action: Do not clone wholesale. Use as signal for a future native direct-effect policy only. Do not add item pickup, loot pickup, or broad reach-distance effects to MIR core under the current safety boundary.

### `asphalt-productivity_1.0.1.zip`

- Primary role: `MIR_STREAM_CANDIDATE`.
- What it does: Adds infinite productivity for the Asphalt Roads Patched asphalt recipe.
- Technologies and bonuses: Infinite `asphalt-productivity`, recipe `Arci-asphalt`, `change-recipe-productivity = +0.50`.
- How it works: Simple infinite recipe-productivity owner with a high per-level value.
- MIR action: Recreate only as part of a designed tile/surface productivity policy. Do not use the `+0.50` value as the default without a balance decision. Exact cleanup is allowed only if MIR later generates the exact same recipe/value.

### `base-prod_0.0.2.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Lets the player assign base productivity to configured machines.
- Technologies and bonuses: No normal MIR-style research chain. It mutates machine prototype `effect_receiver.base_effect.productivity`.
- How it works: Startup settings identify machine names and types, then data-final-fixes assigns built-in productivity to those machines.
- MIR action: Do not recreate in MIR core. At most, diagnostics should report that external base productivity changed the effective value of recipes or machines.

### `big-brother_2.0.1.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds radar upgrade progression and surveillance behavior.
- Technologies and bonuses: Radar amplifier, radar efficiency, and surveillance technologies. It unlocks and uses surveillance-center behavior rather than recipe productivity.
- How it works: Runtime event handlers track built/mined entities, research completion, sector scans, and scheduled work. It changes radar/surveillance gameplay, not productivity ownership.
- MIR action: Load-test only if it appears in a compatibility matrix. Do not recreate in MIR core.

### `bioflux-productivity_0.1.0.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Adds one infinite Bioflux recipe-productivity technology.
- Technologies and bonuses: Infinite `bioflux-productivity`, recipe `bioflux`, `change = +0.10`.
- How it works: Simple external infinite owner for a recipe MIR already covers.
- MIR action: Already handled by `2.1.5` guarded known-competitor cleanup. Cleanup still requires exact effect type, recipe, value, active infinite tech, MIR coverage, lab compatibility, and no blocking owner.

### `combatresearchtech_0.1.0.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Converts combat activity into research progress.
- Technologies and bonuses: It is a research-progression utility, not a recipe-productivity owner.
- How it works: Runtime combat/killing behavior grants or advances research.
- MIR action: Compatible utility. Do not recreate in MIR core.

### `concrete-productivity_1.2.1.zip`

- Primary role: `MIR_STREAM_CANDIDATE`.
- What it does: Adds finite lead-ins and infinite productivity for concrete and refined concrete.
- Technologies and bonuses: `concrete-productivity` levels 1-3 plus infinite `concrete-productivity-4`; recipes include `concrete`, `refined-concrete`, and Space Age molten-iron concrete when present; `change = +0.25`.
- How it works: A tile/material productivity chain with a value different from MIR's normal recipe-productivity default.
- MIR action: Recreate only after tile/surface productivity policy is set. Preserve finite lead-ins. Do not clean up unless exact MIR recipe/value replacement exists.

### `ConfigurableResearchCost_1.1.3.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Provides configurable research costs, lab research speed, lab energy use, lab module slots, and commands to unlock groups of technology.
- Technologies and bonuses: No MIR-style productivity stream. It modifies technology unit costs and lab prototypes.
- How it works: Startup settings scale research costs and lab properties; runtime commands can unlock predefined tiers of technologies.
- MIR action: Compatible research utility. Do not recreate in MIR. Keep MIR formulas robust under external research-cost changes.

### `crafting-efficiency-2_0.3.0.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Generates staged recipe-productivity chains for selected recipes and expansion content.
- Technologies and bonuses: `ce-<name>-<level>` style productivity technologies, generally recipe-productivity effects.
- How it works: Broad generator. It can overlap MIR, but it can also generate balance-distinct coverage.
- MIR action: `2.1.5` adds guarded known-competitor cleanup only. Broader families may become future stream candidates only after exact recipe/value fixtures.

### `crushing-industry-productivity-research_1.0.6.zip`

- Primary role: `MIR_STREAM_CANDIDATE`.
- What it does: Adds productivity research for Crushing Industry ore and material crushing.
- Technologies and bonuses: `ore-crushing-productivity-1`, `-2`, and `-3`; `-3` can be infinite depending on setting; recipe productivity effects are `+0.05`.
- Recipes and changes: Covers crushed iron ore, crushed copper ore, sand, Space Age holmium/tungsten/lithium paths, optional coal, and optional BZ ore families. It also adjusts crushing outputs.
- How it works: Adds productivity techs and modifies Crushing Industry output balance.
- MIR action: Best clean `2.2.0` stream candidate. MIR should recreate only the recipe-productivity stream for visible exact recipe IDs, not the output-scaling behavior or forced Crushing Industry balance changes.

### `customresearchspeed_2.0.0.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Multiplies lab research speed.
- Technologies and bonuses: No research chain. It changes lab `researching_speed` directly through a startup setting.
- How it works: Data-final-fixes multiplies every lab prototype's `researching_speed`.
- MIR action: Compatible lab mutator. Do not recreate. Consider diagnostics only if MIR adds lab-speed overlap reporting.

### `epic_mining_and_crafting_speed_research_10.0.0.zip`

- Primary role: `MIR_COMPAT_ADAPTER`.
- What it does: Adds finite character mining speed and character crafting speed research chains.
- Technologies and bonuses: Five `crafting-speed-upgrade` technologies and five `mining-speed-upgrade` technologies. Defaults include crafting bonuses of roughly `+0.5`, `+0.5`, `+1`, `+2`, `+4`; mining levels default to `+0.5` each.
- How it works: Direct technology modifier effects, not recipe productivity.
- MIR action: Do not absorb into `2.1.5` or early `2.2.0`. Use as signal for future native direct-effect policy if MIR expands beyond productivity streams.

### `ExpandedProductivityResearch_1.3.8.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Broad configurable productivity generator for intermediate recipes, science packs, and many recipe groups.
- Technologies and bonuses: `epr_<item>-productivity-<level>` style technology IDs with recipe-productivity effects.
- How it works: Generated external productivity ownership can exactly overlap MIR in some cases and differ in many others.
- MIR action: `2.1.5` cleanup only. Do not claim full replacement. Future planner work may mine specific recipe families from it.

### `finite_prod_techs_0.1.0.zip`

- Primary role: `MIR_DIAGNOSTIC_ONLY`.
- What it does: Converts or limits infinite productivity technologies based on practical productivity caps.
- Technologies and bonuses: It scans recipe-productivity effects and sets finite maximum levels from recipe caps and machine base productivity.
- How it works: Data-final-fixes inspects `change-recipe-productivity`, recipe `maximum_productivity`, and machine productivity to compute useful max levels.
- MIR action: Do not copy the cap mutation. Recreate the insight as cap-aware diagnostics first.

### `fish-productivity_1.0.0.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Adds infinite fish-breeding productivity.
- Technologies and bonuses: Infinite `fish-breeding-productivity`, recipe `fish-breeding`, `change = +0.10`.
- How it works: Simple external infinite owner for a recipe MIR already covers.
- MIR action: Already handled by `2.1.5` guarded known-competitor cleanup.

### `foundation-productivity_1.1.1.zip`

- Primary role: `MIR_STREAM_CANDIDATE`.
- What it does: Adds infinite foundation recipe productivity.
- Technologies and bonuses: Infinite `foundation-productivity-1`, recipe `foundation`, `change = +0.25`, deep Space Age science requirements.
- How it works: Single high-value tile/surface recipe stream.
- MIR action: Include in the tile/surface policy discussion. Do not cleanup or replace until MIR intentionally owns foundation productivity at an explicit value.

### `gleba-lab_1.0.1.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds an alternate Gleba-themed lab.
- Technologies and bonuses: The lab prototype has `researching_speed = 4`, four module slots, and allowed effects including productivity and quality.
- How it works: Prototype/content addition, not a productivity technology.
- MIR action: Load-test and lab-compatibility signal only. Do not recreate in MIR.

### `landfill-productivity_1.0.2.zip`

- Primary role: `MIR_STREAM_CANDIDATE`.
- What it does: Adds landfill productivity with finite lead-ins and an infinite final tier.
- Technologies and bonuses: Levels 1-4 finite and infinite `landfill-productivity-5`; recipe `landfill`; `change = +0.50`.
- How it works: Tile/surface productivity chain with a high value and metallurgic-science progression.
- MIR action: Tile/surface policy candidate. Preserve finite levels. Exact cleanup only if MIR later owns the same recipe/value.

### `mach-speed-logistics_1.1.3.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds higher-speed logistics content for Factorio `2.0`.
- Technologies and bonuses: Adds belts, inserters, production chains, wagons, fuel, recipes, and related research. Some recipes are productivity-eligible.
- How it works: Broad content mod, not a MIR replacement target.
- MIR action: Support loading alongside it. MIR may later use visible exact recipe IDs only if a stream policy needs them.

### `mach-speed-logistics_1.1.4.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Factorio `2.1` version of the same higher-speed logistics content family.
- Technologies and bonuses: Adds logistics items, recipes, fuel, wagons, and research; some recipes allow productivity.
- How it works: Broad content mod with its own progression.
- MIR action: Keep as compatibility/load-test coverage. Do not recreate in MIR.

### `miner-start_1.0.0.zip`

- Primary role: `MIR_DIAGNOSTIC_ONLY`.
- What it does: Grants a starter mining productivity bonus.
- Technologies and bonuses: Adds a mining productivity technology/effect using `mining-drill-productivity-bonus`, then runtime marks it researched for forces/players.
- How it works: Hybrid data/runtime progression tweak.
- MIR action: Do not replace. If MIR adds native modifier diagnostics, report pre-existing mining productivity owners.

### `mining-prod-0_1.0.2.zip`

- Primary role: `MIR_DIAGNOSTIC_ONLY`.
- What it does: Adds an early `mining-productivity-0` lead-in before vanilla mining productivity.
- Technologies and bonuses: Finite mining-drill productivity bonus unlocked earlier with automation science.
- How it works: Native modifier lead-in, not recipe productivity.
- MIR action: Preserve/coexist. Do not remove finite lead-ins.

### `modified-productivity-cap_1.2.2.zip`

- Primary role: `MIR_DIAGNOSTIC_ONLY`.
- What it does: Configurably changes recipe productivity caps.
- Technologies and bonuses: No research chain. It mutates `recipe.maximum_productivity` for productivity-eligible recipes and selected categories.
- How it works: Data-final-fixes sets cap from startup setting.
- MIR action: Do not copy cap mutation. Add cap-aware diagnostics so users know when MIR infinite levels are capped, raised, or uncapped.

### `more-productivity-research_1.0.1.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds finite science-pack productivity chains.
- Technologies and bonuses: Finite productivity for automation, logistic, military, chemical, space, production, utility, metallurgic, agricultural, electromagnetic, cryogenic, and promethium science packs. Values are finite and tiered rather than MIR's infinite stream model.
- How it works: Adds finite progression layers with some craft-triggered unlocks.
- MIR action: Compatible only. Do not delete finite chains. MIR's existing infinite science productivity is a different product.

### `omniab-space-age-compat_1.3.7.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Compatibility/progression layer for Omnimatter, Angel's, Bob's, and Space Age combinations.
- Technologies and bonuses: Touches suite progression, research triggers, resources, tiles, mining results, fluid behavior, and compatibility glue rather than a single productivity stream.
- How it works: Cross-suite compatibility patcher.
- MIR action: Future overhaul compatibility-matrix signal only. Do not treat it as a `2.2.0` stream candidate unless specific recipe/productivity evidence is isolated.

### `player-count-based-research-speed_1.1.3.zip`

- Primary role: `MIR_COMPAT_ADAPTER`.
- What it does: Scales laboratory speed and laboratory productivity by online player count.
- Technologies and bonuses: No data-stage tech chain. It reads researched `laboratory-speed` and `laboratory-productivity` modifiers and writes `force.laboratory_speed_modifier` and `force.laboratory_productivity_bonus`.
- How it works: Runtime event handlers recalculate force lab modifiers when players join/leave/change force, forces merge, research finishes, or settings change.
- MIR action: Do not recreate. If MIR adds lab-productivity diagnostics, flag that runtime lab modifiers may be externally managed.

### `Prod-Beacon_1.0.3.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Adds a special productivity beacon that consumes productivity modules.
- Technologies and bonuses: Adds beacon/item/recipe content, not a productivity research stream.
- How it works: Beacon-rule and content change.
- MIR action: Companion territory only. Keep compatible; do not absorb into MIR core.

### `prodforce_0.0.8.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Forces productivity and optional quality effects onto assemblies, drills, furnaces, recipes, and effect receivers.
- Technologies and bonuses: No normal technology chain. It changes allowed effects and `allow_productivity`/`allow_quality` rules.
- How it works: Data-final-fixes mutates large prototype sets.
- MIR action: Do not recreate in MIR core. Diagnostics may report that a rule mutator widened productivity eligibility.

### `Productivity_2.0.5.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Broadly enables productivity modules for many recipe categories and item families.
- Technologies and bonuses: Rule/eligibility changes for logistics, solar, accumulators, generators, heat pipes, satellites, landfill, tiles, equipment, ammo, and optional families.
- How it works: Startup settings and data-stage prototype mutation.
- MIR action: Do not copy. MIR can coexist and may generate streams only for recipes it intentionally owns.

### `productivity_fix_2.0.0.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Selectively enables productivity/quality in beacons, productivity in recyclers, and productivity for non-intermediates.
- Technologies and bonuses: No research stream. It mutates beacon allowed effects, recycler effects, and recipe productivity eligibility.
- How it works: Startup settings and data-updates/data-final-fixes mutation.
- MIR action: Companion/rule-mutation territory. MIR should not normalize or claim these rule changes.

### `productivity_tech_modules_0.0.3.zip`

- Primary role: `MIR_COMPAT_ADAPTER`.
- What it does: Adds productivity research for module recipes.
- Technologies and bonuses: External chain uses `+0.10` recipe productivity for module tiers.
- How it works: Recipe-productivity technology owner for module crafting.
- MIR action: Do not silently replace. MIR uses tiered lower module values, so exact cleanup must reject it unless MIR intentionally matches the same value.

### `productivity_weight_fix_0.0.2.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Rebalances item weight behavior affected by productivity-related changes.
- Technologies and bonuses: No productivity research stream.
- How it works: Prototype weight adjustment utility.
- MIR action: Compatible only.

### `Productivity-config_0.1.1.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Configures productivity behavior and built-in productivity for Space Age machines.
- Technologies and bonuses: No MIR-style research chain. It assigns `base_effect.productivity` to foundry, electromagnetic plant, and biochamber style prototypes from settings.
- How it works: Startup setting based prototype mutation.
- MIR action: Do not recreate. Diagnostics may report machine base productivity when computing effective caps.

### `productivity-indicator_1.0.0.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds UI/tooltip indicators for whether recipes accept productivity.
- Technologies and bonuses: No technology or productivity stream.
- How it works: UI/info utility.
- MIR action: Compatible utility. No MIR replacement.

### `productivity-module-3-aquilo_1.0.4.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Moves or reshapes productivity module 3 access around Aquilo progression.
- Technologies and bonuses: Technology/recipe progression tweak for productivity module 3, including lithium-oriented recipe changes.
- How it works: Data-stage progression adjustment.
- MIR action: Compatible only. MIR should not manage module unlock progression.

### `productivity-technology-limit_0.0.2.zip`

- Primary role: `MIR_DIAGNOSTIC_ONLY`.
- What it does: Limits maximum levels of productivity technologies based on recipe caps and existing productivity.
- Technologies and bonuses: Mutates infinite productivity technology max levels.
- How it works: Data-stage cap-aware conversion similar in spirit to `finite_prod_techs`.
- MIR action: Recreate as diagnostics first, not mutation. Use as input for cap-aware UX.

### `productivity-through-science_1.1.0.zip`

- Primary role: `MIR_REJECT_CORE`.
- What it does: Grants permanent productivity to unlocked recipes for every researched technology.
- Technologies and bonuses: Runtime recipe `productivity_bonus` grows by a global setting per researched tech.
- How it works: Runtime tracks researched technology count per force and applies cumulative productivity to unlocked recipes on init, configuration changes, research finish, and force events.
- MIR action: Do not copy into MIR core. This is a runtime productivity system, not MIR's explicit technology stream model.

### `ProductivityResearch_2.1.0.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Broad recipe-productivity generator for intermediate recipes.
- Technologies and bonuses: `sem-prfe_<recipe>-productivity-1` style generated technology IDs, generally `+0.10`.
- How it works: Generated external ownership that may exactly overlap MIR for covered recipes.
- MIR action: `2.1.5` guarded cleanup only. No broad absorption.

### `ProductivityResearchForEveryone_1.0.9.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Earlier broad recipe-productivity generator.
- Technologies and bonuses: `sem-prfe_` generated recipe productivity technologies.
- How it works: Similar competitor surface to `ProductivityResearch`.
- MIR action: `2.1.5` guarded cleanup only.

### `ProductivityResearchForEveryoneFG_1.2.0.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Forked/configurable broad recipe-productivity generator.
- Technologies and bonuses: `sem-prfe_` generated technologies with staged science settings.
- How it works: Broad external generator.
- MIR action: `2.1.5` guarded cleanup only.

### `progressive-productivity_1.1.5.zip`

- Primary role: `MIR_REJECT_CORE`.
- What it does: Increases productivity as items and fluids are produced.
- Technologies and bonuses: Runtime item/fluid productivity bonuses based on production statistics and configurable cost curves.
- How it works: Runtime storage/settings cache tracks production-driven thresholds and applies recipe productivity behavior.
- MIR action: Do not copy into MIR core. Only reconsider with a dedicated runtime-performance and save-compatibility design.

### `py_productivity_1.3.0.zip`

- Primary role: `MIR_STREAM_CANDIDATE`.
- What it does: Adds hand-authored productivity families for Pyanodon-style material chains.
- Technologies and bonuses: Families include alloys, biomass/phytomining, casting, glasswork, nucleo, smelting, and related overhaul intermediates.
- How it works: Explicit overhaul-family recipe productivity, not a generic name scanner.
- MIR action: Good future candidate, but only one family at a time with exact visible recipe fixtures. Do not claim broad Pyanodon compatibility from this alone.

### `remove-productivity-cap_1.1.1.zip`

- Primary role: `MIR_DIAGNOSTIC_ONLY`.
- What it does: Removes or effectively raises the recipe productivity cap.
- Technologies and bonuses: No research chain. It mutates recipe `maximum_productivity`.
- How it works: Data-stage cap mutator.
- MIR action: Do not copy cap removal. Add diagnostics that identify uncapped or raised-cap environments.

### `Research_Productivity_1.1.3.zip`

- Primary role: `MIR_COMPAT_ADAPTER`.
- What it does: Adds native laboratory productivity research.
- Technologies and bonuses: Finite lab-productivity lead-ins and infinite `laboratory-productivity-4`, using native `laboratory-productivity` modifier at `+0.10`.
- How it works: Native modifier owner, not recipe productivity.
- MIR action: Already handled by `2.1.5`: MIR skips its lab-productivity stream only when `laboratory-productivity-4` exists and has the expected native effect.

### `research-control-tower_1.3.1.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds a circuit-controlled tool for selecting and managing infinite research.
- Technologies and bonuses: Control/automation utility for research selection, including modded infinite techs.
- How it works: Runtime control surface for research queue behavior.
- MIR action: Compatible utility. MIR should keep infinite tech prototypes normal enough for tools like this to see them.

### `research-cost-curve_0.1.4.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Changes research cost multiplier over time as research completes.
- Technologies and bonuses: No productivity stream. It can set fixed initial science costs and then update cost multipliers.
- How it works: Runtime hooks research completion and mod setting changes to update the global cost multiplier.
- MIR action: Compatible cost tool. Do not recreate in MIR.

### `research-fixer_1.0.6.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Adds missing prerequisite edges inferred from science pack requirements.
- Technologies and bonuses: No productivity stream. It mutates technology prerequisites.
- How it works: Data-stage graph repair.
- MIR action: Compatible utility. Monitor whether it adds prerequisites to MIR techs during load tests.

### `research-multipliers_0.2.0.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Provides detailed startup research cost multipliers.
- Technologies and bonuses: Cost changes by science pack, infinite status, planet/category, and individual tech rules.
- How it works: Data-stage cost scaling.
- MIR action: Compatible cost mutator. Do not copy.

### `research-skip_1.0.1.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Unlocks early or midgame technologies at game start or by command.
- Technologies and bonuses: Progression shortcut utility.
- How it works: Runtime unlock behavior.
- MIR action: Compatible utility. Do not copy.

### `ResearchProductivity_Rebalance_1.0.0.zip`

- Primary role: `MIR_COMPAT_ADAPTER`.
- What it does: Rebalances Space Age's native `research-productivity` technology.
- Technologies and bonuses: Adjusts cost/time of `research-productivity`.
- How it works: Data-stage tweak to an existing native owner.
- MIR action: Compatible. MIR already skips the vanilla native research-productivity owner; do not claim replacement.

### `rosnok-productivity-quality-beacon_1.1.2.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Allows productivity and quality modules in beacons.
- Technologies and bonuses: No research stream. It mutates all beacon allowed effects.
- How it works: Data-final-fixes assigns beacon `allowed_effects` to include productivity and quality.
- MIR action: Companion/rule-mutation territory. Do not absorb.

### `SchallModules_2.0.0.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Adds module ecosystem content, optional beacon productivity/quality support, efficiency buffs, and multicomponent modules.
- Technologies and bonuses: Adds module recipes, technologies, settings, and allowed-effect changes.
- How it works: Broad module-system extension.
- MIR action: Compatible/adjacent only. Do not merge module-system behavior into MIR core.

### `Science_packs_productivity_0.0.1.zip`

- Primary role: `MIR_REPLACE_EXACT`.
- What it does: Adds finite plus infinite productivity chains for official science packs.
- Technologies and bonuses: Science pack productivity levels 1-4; level 4 is infinite; `change = +0.10`.
- How it works: Direct recipe-productivity owner for science pack recipes.
- MIR action: `2.1.5` guarded cleanup covers only infinite level-4 owners. Preserve finite levels 1-3.

### `show-missing-bottles-for-current-research_2.0.2.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Shows which science packs are missing for current research.
- Technologies and bonuses: UI overlay only.
- How it works: Runtime/UI utility.
- MIR action: Compatible. No MIR replacement.

### `solar-productivity_3.0.0.zip`

- Primary role: `MIR_REJECT_CORE`.
- What it does: Adds solar panel and accumulator efficiency progression.
- Technologies and bonuses: Solar productivity levels with visible bonuses such as `+15%`, `+10%`, `+10%`, and `+5%` in early tiers, then extended progression.
- How it works: Creates upgraded solar panel and accumulator variants and uses runtime upgrade/replacement logic on build, research, force creation, and tick queues. Includes commands for update and transition/removal.
- MIR action: Do not copy into MIR core. This is runtime entity replacement and energy-system progression, not recipe productivity. Consider only as separate companion/future direct-effect design.

### `space-exploration-spaceproductivity-2_0.1.2.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Allows productivity modules in Space Exploration space machines, recipes, and beacons.
- Technologies and bonuses: Rule mutation for SE productivity restrictions.
- How it works: Data-stage compatibility patcher for Space Exploration.
- MIR action: Companion territory. MIR should not mutate SE space productivity rules as part of core compatibility.

### `UnlimitedProductivityFork_2.1.0.zip`

- Primary role: `MIR_COMPANION_SCOPE`.
- What it does: Removes productivity restrictions and optionally allows productivity/quality in beacons while tuning beacon settings and productivity caps.
- Technologies and bonuses: No normal MIR stream. Startup settings control beacon productivity, all-beacon support, quality in beacons, maximum productivity, beacon range, beacon module count, and effectivity values.
- How it works: Broad prototype/rule mutation.
- MIR action: Do not absorb. Keep compatible; diagnostics can note widened productivity eligibility and cap changes.

### `zz-long-science_2.0.0.zip`

- Primary role: `MIR_DOCS_ONLY`.
- What it does: Progressively increases science cost as technologies are unlocked.
- Technologies and bonuses: No productivity stream. Settings control base multiplier override, normal-tech multiplier, trigger-tech multiplier, initial multiplier, and exclusions.
- How it works: Runtime updates the force technology price multiplier after research completes or settings change; data-final-fixes can scale all science costs to bypass the vanilla multiplier ceiling.
- MIR action: Compatible cost mutator. Do not recreate in MIR.

## Recreate Candidates

These are candidates for MIR-owned implementation, not cloning:

| Candidate | Source mods | Required policy before code |
| --- | --- | --- |
| Ore-crushing productivity | `crushing-industry-productivity-research` | Exact visible recipe IDs, value decision, and no output-scaling copy. |
| Tile/surface productivity | `asphalt-productivity`, `concrete-productivity`, `landfill-productivity`, `foundation-productivity` | Per-material values, finite lead-in preservation, exact cleanup rules. |
| Cap-aware diagnostics | `finite_prod_techs`, `productivity-technology-limit`, `modified-productivity-cap`, `remove-productivity-cap`, `Productivity-config`, `base-prod` | Warn/report first; no silent cap mutation. |
| Native direct-effect policy | `Research_Productivity`, `all_around_research`, `epic_mining_and_crafting_speed_research`, `miner-start`, `mining-prod-0`, `player-count-based-research-speed` | Explicit skip/prefer/coexist/warn rules by modifier type. |
| One overhaul material family | `py_productivity`, selected `ExpandedProductivityResearch` and `crafting-efficiency-2` families | Exact recipe family fixture and public claim limited to that family. |

## Compatibility Only

These should be supported through load tests, diagnostics, or non-action rather
than recreated:

- `5dim_mining`
- `big-brother`
- `combatresearchtech`
- `ConfigurableResearchCost`
- `customresearchspeed`
- `gleba-lab`
- `mach-speed-logistics`
- `more-productivity-research`
- `omniab-space-age-compat`
- `productivity_weight_fix`
- `productivity-indicator`
- `productivity-module-3-aquilo`
- `research-control-tower`
- `research-cost-curve`
- `research-fixer`
- `research-multipliers`
- `research-skip`
- `show-missing-bottles-for-current-research`
- `zz-long-science`

## Do Not Copy Into MIR Core

These change rules, runtime state, or gameplay systems outside MIR's current
identity:

- `base-prod`
- `Prod-Beacon`
- `prodforce`
- `Productivity`
- `productivity_fix`
- `Productivity-config`
- `productivity-through-science`
- `progressive-productivity`
- `rosnok-productivity-quality-beacon`
- `SchallModules`
- `solar-productivity`
- `space-exploration-spaceproductivity-2`
- `UnlimitedProductivityFork`

## Immediate Planning Notes

1. `2.1.5` should not expand from this audit.
2. The newly added idea mods strengthen the case for a compatibility planner, not for broader cleanup.
3. The next implementation decision should be a `2.2.0` planner/diagnostics layer or the ore-crushing stream fixture.
4. Public wording should say "MIR cooperates with or avoids duplicates from these mods" unless a fixture proves exact replacement.
5. Any future "replacement" claim must say which portion is replaced. For many mods here, MIR can at most replace the recipe-productivity portion.
