# Local Idea Mods Audit And Release Plan - 2026-07-05

Source library: `C:\Projects\Factorio\ideamods_readonly_mix`

Text-only working copy used for code reading: `tmp/ideamods-text-audit-20260705/`

Scope: 50 downloaded archives, 49 unique mod/version pairs. `Research_Productivity_1.1.3.zip` and `Research_Productivity_1.1.3 (1).zip` are duplicate archives. The set mixes Factorio `2.0` and `2.1` targets. `research-cost-curve` has an unusual `info.json` shape but its source was readable.

## Decision Summary

| Lane | Decision | Why |
| --- | --- | --- |
| `2.1.5` | Keep the compatibility commit. | It only adds guarded known-competitor profiles and one precise native lab-productivity skip. |
| `2.1.5` | Do not add new streams from this audit. | The remaining overlaps need balance, progression, runtime, or product-scope decisions. |
| `2.1.5` | Preserve finite lead-ins from other mods. | MIR's current cleanup model is for exact infinite owners, not finite upgrade chains. |
| `2.2.0` | Plan new feature work from grouped demand signals. | Tile productivity, ore crushing, overhaul materials, cap-aware UX, and native overlap policy need design. |
| Companion/modpack scope | Keep rule mutators adjacent unless explicitly adopted. | Beacon/module/productivity-rule mods change factory rules, not just research ownership. |

## Safety Model

The shipped `2.1.5` profiles are not deletion rules. They only mark external technology names as known competitors. MIR still removes an external technology only when all of these checks pass:

| Required proof | Purpose |
| --- | --- |
| The external technology is active and infinite. | Avoid touching finite lead-ins or inactive prototype leftovers. |
| Every effect is `change-recipe-productivity`. | Avoid deleting mixed-purpose technologies. |
| Every recipe effect is covered by enabled MIR replacement effects. | Avoid partial replacement. |
| Every `change` value matches MIR's generated effect value. | Avoid silent balance changes. |
| Replacement science is lab-compatible. | Avoid replacing with unresearchable MIR techs. |
| No other blocking external owner remains. | Avoid creating duplicate or ambiguous productivity ownership. |

The `Research_Productivity` change is separate: MIR skips its own base-game lab-productivity stream when the other mod provides `laboratory-productivity-4`, because both use the native `laboratory-productivity` force modifier.

## 2.1.5 Ship Table

These are release-appropriate because they are exact duplicate-avoidance or exact-coverage cleanup.

| Mod | Audit signal | 2.1.5 action | Guardrail |
| --- | --- | --- | --- |
| `bioflux-productivity` | Infinite `bioflux-productivity`, recipe `bioflux`, `+0.10`. | Add known-competitor profile. | Exact recipe and `change` match required. |
| `fish-productivity` | Infinite `fish-breeding-productivity`, recipe `fish-breeding`, `+0.10`. | Add known-competitor profile. | Exact recipe and `change` match required. |
| `Science_packs_productivity` | Official science pack chains with infinite `*-science-productivity-4`, `+0.10`. | Add level-4 known-competitor patterns only. | Finite levels 1-3 are preserved. |
| `ProductivityResearch` | Broad generated `sem-prfe_<recipe>-productivity-1`, usually `+0.10`. | Add guarded known-competitor pattern. | Cleanup only fires for exact covered effects. |
| `ProductivityResearchForEveryone` | Earlier `sem-prfe_` broad generator. | Add guarded known-competitor pattern. | Cleanup only fires for exact covered effects. |
| `ProductivityResearchForEveryoneFG` | Forked `sem-prfe_` generator with staged science settings. | Add guarded known-competitor pattern. | Cleanup only fires for exact covered effects. |
| `ExpandedProductivityResearch` | Broad configurable `epr_<item>-productivity-<level>` generator. | Add guarded known-competitor pattern. | Cleanup still rejects changed values or uncovered recipes. |
| `crafting-efficiency-2` | Staged generated `ce-<name>-<level>` productivity chains. | Add guarded known-competitor pattern. | Cleanup still rejects changed values or uncovered recipes. |
| `Research_Productivity` | Native infinite `laboratory-productivity-4` chain. | Skip MIR lab productivity when present. | Only the exact native lab-productivity overlap is skipped. |

## 2.1.5 Explicit Non-Goals

These were intentionally not absorbed into `2.1.5`.

| Area | Mods | Reason not shipped in `2.1.5` |
| --- | --- | --- |
| Balance-heavy tile/productivity chains | `concrete-productivity`, `landfill-productivity`, `foundation-productivity`, `asphalt-productivity` | Per-level values differ materially from MIR defaults. Replacing them would be a balance change. |
| Module productivity with different tier values | `productivity_tech_modules` | External chain uses `+0.10` for all module tiers; MIR uses tiered lower values. |
| Broad generated productivity systems | `ExpandedProductivityResearch`, `crafting-efficiency-2`, `ProductivityResearch*` | Only exact overlap cleanup shipped. Their broader design remains separate. |
| Productivity caps and finite conversion | `finite_prod_techs`, `productivity-technology-limit`, `remove-productivity-cap`, `modified-productivity-cap` | These alter cap semantics or useful max levels, which needs explicit player-facing policy. |
| Rule mutators | `UnlimitedProductivityFork`, `prodforce`, `Productivity`, `productivity_fix`, `Productivity-config`, `rosnok-productivity-quality-beacon`, `SchallModules`, `Prod-Beacon`, `space-exploration-spaceproductivity-2` | They change allowed effects, recipe productivity eligibility, beacons, modules, or machine rules. |
| Runtime productivity systems | `progressive-productivity`, `productivity-through-science`, `solar-productivity` | They rely on runtime force/entity/stat behavior rather than MIR's current recipe-productivity model. |
| Research cost and automation tools | `research-cost-curve`, `research-multipliers`, `zz-long-science`, `research-control-tower`, `research-skip`, `combatresearchtech`, `show-missing-bottles-for-current-research` | They are compatible utilities or progression tools, not MIR stream ownership work. |

## 2.2.0 Planning Table

| Priority | Candidate | Source mods | First useful slice | Main design question | Validation gate |
| --- | --- | --- | --- | --- | --- |
| High | Tile and surface productivity policy | `asphalt-productivity`, `concrete-productivity`, `landfill-productivity`, `foundation-productivity`, `ExpandedProductivityResearch` | Decide stream split and default values for concrete/refined concrete/landfill/foundation/asphalt-style recipes. | One stream family or separate balance profiles per material? | Fixture proves no silent replacement when values differ and exact replacement when values match. |
| High | Ore-crushing productivity | `crushing-industry-productivity-research` | Add recipe-ID driven stream for Crushing Industry ore/coal/calcite/stone crushing when visible. | MIR-owned stream or compatibility profile around the existing mod? | Fixture with Crushing Industry recipes and optional infinite setting. |
| Medium | Overhaul material families | `py_productivity`, `crafting-efficiency-2`, `ExpandedProductivityResearch`, `5dim_mining` | Pick one concrete family, such as casting/alloys/glass/biomass, and prove with visible recipe IDs. | Which families fit MIR's identity without becoming a generic productivity generator? | Overhaul fixture or local-scenario proof with exact recipe list. |
| Medium | Cap-aware UX | `finite_prod_techs`, `productivity-technology-limit`, `remove-productivity-cap`, `modified-productivity-cap` | Add diagnostics for recipe `maximum_productivity` and effective useful levels. | Warn only, cap generated max level, or provide an explicit setting? | Static and runtime fixture where caps are default, raised, removed, and lowered. |
| Medium | Native modifier overlap policy | `Research_Productivity`, `solar-productivity`, `miner-start`, `mining-prod-0`, `ResearchProductivity_Rebalance` | Generalize skip/warn/prefer/allow policy for overlapping native modifiers. | Which native modifiers should default to external-owner preference? | Fixture with duplicate native modifier owners and setting permutations. |
| Low | Research cost cooperation | `research-multipliers`, `research-cost-curve`, `zz-long-science` | Document compatibility and add diagnostics only if evidence shows conflicts. | Should MIR expose cost-shape presets or stay neutral? | Load scenarios showing formulas remain valid after cost mutators. |
| Companion candidate | Productivity rules and beacons | `UnlimitedProductivityFork`, `prodforce`, `productivity_fix`, `Productivity-config`, `rosnok-productivity-quality-beacon`, `SchallModules`, `Prod-Beacon`, `space-exploration-spaceproductivity-2` | Keep MIR compatible; consider separate companion only if deliberately adopting rule mutation. | Does this belong in MIR core at all? | Separate design review before implementation. |
| Companion candidate | Runtime production-based productivity | `progressive-productivity`, `productivity-through-science`, `solar-productivity` | No core MIR change unless a bounded, event-driven model exists. | Does runtime productivity violate MIR's no broad scanning/default stability rules? | Performance and save-behavior proof before any core proposal. |

## Grouped Mod Disposition

| Group | Mods | Current disposition |
| --- | --- | --- |
| Shipped exact overlap cleanup | `bioflux-productivity`, `fish-productivity`, `Science_packs_productivity`, `ProductivityResearch`, `ProductivityResearchForEveryone`, `ProductivityResearchForEveryoneFG`, `ExpandedProductivityResearch`, `crafting-efficiency-2` | `2.1.5` known-competitor profiles with exact-coverage guards. |
| Shipped native duplicate avoidance | `Research_Productivity` | `2.1.5` lab-productivity skip for `laboratory-productivity-4`. |
| Preserve as finite or balance-distinct chains | `more-productivity-research`, `concrete-productivity`, `landfill-productivity`, `foundation-productivity`, `productivity_tech_modules` | Compatible, but not replaced by MIR in `2.1.5`. |
| New stream candidates | `asphalt-productivity`, `crushing-industry-productivity-research`, `py_productivity`, selected `crafting-efficiency-2` and `ExpandedProductivityResearch` families | Candidate `2.2.0` work after recipe-ID proof and balance decisions. |
| Rule mutators | `base-prod`, `prodforce`, `Productivity`, `productivity_fix`, `Productivity-config`, `remove-productivity-cap`, `modified-productivity-cap`, `UnlimitedProductivityFork`, `rosnok-productivity-quality-beacon`, `SchallModules`, `Prod-Beacon`, `space-exploration-spaceproductivity-2` | Compatible/adjacent. Prefer companion boundary over MIR core absorption. |
| Research utilities and cost tools | `research-control-tower`, `research-cost-curve`, `research-fixer`, `research-multipliers`, `research-skip`, `zz-long-science`, `combatresearchtech`, `show-missing-bottles-for-current-research` | Compatible utilities. Document and test if conflicts appear. |
| Native/progression tweaks | `miner-start`, `mining-prod-0`, `ResearchProductivity_Rebalance`, `productivity-module-3-aquilo` | Compatible. Feed future native-overlap policy only if needed. |
| Runtime productivity systems | `progressive-productivity`, `productivity-through-science`, `solar-productivity` | Defer or reject for core unless bounded runtime design is proven. |
| Broad content mods | `5dim_mining` | Compatible content source; MIR may pick up visible matching recipes opportunistically. |

## Per-Mod Appendix

| Archive | What it does | MIR plan |
| --- | --- | --- |
| `5dim_mining_2.0.3` | Adds high-tier mining drills, pumpjacks, water pumpjacks, and offshore pumps. | Compatible. MIR may pick up visible drill recipes through Mining Drill Productivity. |
| `asphalt-productivity_1.0.1` | Adds infinite `Arci-asphalt` recipe productivity at `+0.50`. | `2.2.0` tile/surface productivity candidate. |
| `base-prod_0.0.2` | Mutates base productivity/prototype productivity behavior. | Adjacent rule mutation; no MIR core change. |
| `bioflux-productivity_0.1.0` | Adds one infinite Bioflux recipe-productivity technology. | Shipped exact known-competitor profile. |
| `combatresearchtech_0.1.0` | Grants research progress from enemy kills. | Compatible runtime utility; no MIR code needed. |
| `concrete-productivity_1.2.1` | Adds concrete/refined-concrete productivity chain, infinite level uses `+0.25`. | Defer. Balance differs from MIR concrete coverage. |
| `crafting-efficiency-2_0.3.0` | Generates staged recipe productivity for selected recipe groups and expansions. | Shipped guarded known-competitor profile; broader families are `2.2.0` candidates. |
| `crushing-industry-productivity-research_1.0.6` | Adds ore/crushing productivity for Crushing Industry and forces ore crushing on. | `2.2.0` ore-crushing stream candidate. |
| `ExpandedProductivityResearch_1.3.8` | Broad configurable generator for productivity techs, including science packs and many recipe categories. | Shipped guarded known-competitor profile; broader absorption needs planner work. |
| `finite_prod_techs_0.1.0` | Converts infinite productivity techs to finite levels based on recipe productivity caps. | Compatible but order-sensitive; cap-aware UX candidate. |
| `fish-productivity_1.0.0` | Adds infinite fish-breeding recipe productivity. | Shipped exact known-competitor profile. |
| `foundation-productivity_1.1.1` | Adds infinite foundation recipe productivity at `+0.25`. | Defer due balance mismatch. |
| `landfill-productivity_1.0.2` | Adds landfill productivity chain, final infinite level at `+0.50`. | Defer due balance mismatch. |
| `miner-start_1.0.0` | Adds starter mining productivity bonus. | Compatible native/progression tweak. |
| `mining-prod-0_1.0.2` | Inserts early `mining-productivity-0` before vanilla mining productivity. | Compatible native/progression tweak. |
| `modified-productivity-cap_1.2.2` | Lets startup settings change recipe `maximum_productivity`. | Compatible cap mutator; cap-aware UX candidate. |
| `more-productivity-research_1.0.1` | Adds finite science-pack productivity chains. | Compatible; preserve finite lead-ins. |
| `Prod-Beacon_1.0.3` | Adds a productivity beacon prototype. | Companion/rule-mutation territory. |
| `prodforce_0.0.8` | Forces productivity/quality allowed effects onto machines and recipes. | Companion/rule-mutation territory. |
| `Productivity_2.0.5` | Broadly enables productivity for recipes. | Compatible as a producer of more productivity-allowed recipes. |
| `productivity_fix_2.0.0` | Allows productivity in beacons/recycler and broad recipe productivity. | Companion/rule-mutation territory. |
| `productivity_tech_modules_0.0.3` | Adds module recipe-productivity technology at `+0.10` for all tiers. | Defer; MIR uses tiered lower module values. |
| `productivity_weight_fix_0.0.2` | Adjusts productivity-related weight behavior. | Compatible utility; no MIR action. |
| `Productivity-config_0.1.1` | Configurable productivity allowances. | Companion/rule-mutation territory. |
| `productivity-indicator_1.0.0` | UI/indicator for productivity. | Compatible UI utility. |
| `productivity-module-3-aquilo_1.0.4` | Moves or enables productivity module 3 access on Aquilo. | Compatible progression tweak. |
| `productivity-technology-limit_0.0.2` | Limits productivity technologies by recipe cap and prior productivity. | Compatible but order-sensitive; cap-aware UX candidate. |
| `productivity-through-science_1.1.0` | Runtime recipe productivity bonus per researched technology. | Runtime system; not MIR core for `2.1.5`. |
| `ProductivityResearch_2.1.0` | Broad recipe-productivity generator with `sem-prfe_` technology IDs. | Shipped guarded known-competitor profile. |
| `ProductivityResearchForEveryone_1.0.9` | Earlier `sem-prfe_` broad recipe-productivity generator. | Shipped guarded known-competitor profile. |
| `ProductivityResearchForEveryoneFG_1.2.0` | Fork with staged science-pack settings for `sem-prfe_` generator. | Shipped guarded known-competitor profile. |
| `progressive-productivity_1.1.5` | Runtime productivity improves as production statistics rise. | Runtime system; defer or companion only with performance proof. |
| `py_productivity_1.3.0` | Hand-authored Pyanodon productivity families for alloys, biomass, casting, glasswork, smelting, and more. | `2.2.0` overhaul-family candidate with recipe-ID proof. |
| `remove-productivity-cap_1.1.1` | Sets recipe `maximum_productivity` extremely high. | Compatible cap mutator; cap-aware UX candidate. |
| `Research_Productivity_1.1.3` | Adds native laboratory-productivity finite levels and infinite `laboratory-productivity-4`. | Shipped lab-productivity skip. |
| `Research_Productivity_1.1.3 (1)` | Duplicate of the same archive/version. | No separate action. |
| `research-control-tower_1.3.1` | Circuit-controlled automation for choosing infinite research. | Compatible with MIR infinite techs. |
| `research-cost-curve_0.1.4` | Runtime science-cost multiplier curve after research completion, plus fixed startup cost option. | Compatible cost tool; outside MIR core. |
| `research-fixer_1.0.6` | Adds missing science prerequisite links inferred from science ingredients. | Generally compatible; monitor if it touches MIR techs. |
| `research-multipliers_0.2.0` | Startup research cost multipliers by pack, infinite status, planet, and individual tech. | Compatible cost mutator; order-sensitive. |
| `research-skip_1.0.1` | Unlocks early/midgame technologies at game start or by command. | Compatible progression utility. |
| `ResearchProductivity_Rebalance_1.0.0` | Rebalances Space Age `research-productivity` cost/time. | Compatible; MIR already skips vanilla `research-productivity`. |
| `rosnok-productivity-quality-beacon_1.1.2` | Allows productivity and quality in beacons. | Companion/rule-mutation territory. |
| `SchallModules_2.0.0` | Adds module tiers/options and mutates allowed beacon effects. | Adjacent module ecosystem; no MIR absorption. |
| `Science_packs_productivity_0.0.1` | Adds finite plus infinite official science-pack productivity chains. | Shipped guarded profile for infinite level-4 owners only. |
| `show-missing-bottles-for-current-research_2.0.2` | UI overlay for missing current research ingredients. | Compatible UI utility. |
| `solar-productivity_3.0.0` | Adds finite solar/accumulator efficiency research via runtime entity upgrades. | Defer/reject for MIR core unless bounded native/prototype model exists. |
| `space-exploration-spaceproductivity-2_0.1.2` | Allows productivity in Space Exploration space machines, recipes, and beacons. | Companion/rule-mutation territory. |
| `UnlimitedProductivityFork_2.1.0` | Removes productivity restrictions, allows productivity/quality in beacons, tunes beacon settings. | Companion/rule-mutation territory. |
| `zz-long-science_2.0.0` | Progressively increases technology cost multipliers as research is completed. | Compatible cost mutator; outside MIR core. |

## Release Checklist From This Audit

| Step | Required before publishing `2.1.5` | Status |
| --- | --- | --- |
| Keep the narrow compatibility commit. | Yes. | Done. |
| Rebuild `dist/more-infinite-research_2.1.5.zip` from committed source. | Yes. | Required on the final source tree because package docs are included. |
| Run static validation. | Yes. | Required on the final source tree. |
| Run Factorio fixture validation. | Yes before publishing. | Done for the compatibility commit with the local Steam Factorio binary. |
| Run exact external idea-mod load pass. | Recommended. | Still recommended because the fixture validation did not prove every downloaded zip combination. |
| Push/tag. | Only after the final package and chosen external check are complete. | Pending release decision. |
