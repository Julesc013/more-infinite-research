---
title: "API Proof Points"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: []
---
# API Proof Points

Updated: 2026-07-10

This ledger records API claims that affect release planning. Use it to avoid turning Reddit ideas or memory into implementation assumptions.

Official Factorio API references should be rechecked before a release if the local Factorio version changes.

Latest official API docs checked on 2026-07-06: `2.1.9`. Local runtime validation evidence in `docs/releases/2.2.0-validation-record.md` now includes Factorio `2.1.9`.

## Verified Or Locally Proven

| Claim | Proof source | Status | Release impact |
| --- | --- | --- | --- |
| Mod zip names follow `{mod-name}_{version}` and `info.json` controls Factorio compatibility | Factorio mod structure docs | Verified | Package validation must match `info.json` and zip filename |
| `factorio_version = "2.0"` and `factorio_version = "2.1"` are separate release targets | Factorio mod structure docs | Verified | Main `v2.x` line targets Factorio `2.1.x`; legacy `v1.9.0` targets Factorio `2.0.x` |
| `gun-speed` modifiers use `ammo_category` | Factorio modifier docs plus local prototype files | Verified | Electric shooting speed must include `tesla` for Tesla weapons |
| Space Age Tesla gun/ammo/turret use `ammo_category = "tesla"` | Local Factorio `2.1.8` Space Age prototypes | Verified | Tesla turret speed is covered by `tesla`, not `electric` |
| Space Age `electric-weapons-damage-1` uses `__space-age__/graphics/technology/electric-weapons-damage.png` | Local Factorio `2.1.8` Space Age prototypes | Verified | Electric Shooting Speed can reuse the matching electric weapon damage art when Space Age is active |
| Base discharge defense uses `ammo_category = "electric"` | Local Factorio `2.1.8` base prototypes | Verified | Keep `electric` effect for discharge-defense-style equipment |
| Vanilla tank cannon fire-rate bonuses are `gun-speed` effects for `cannon-shell` on finite `weapon-shooting-speed` technologies | Local Factorio `2.1.8` base prototypes | Verified | MIR overlap handling must preserve finite vanilla `cannon-shell` speed effects |
| Base game locale does not provide every generated shooting-speed modifier string MIR needs | Local Factorio `2.1.8` base and Space Age locale files | Verified | MIR ships `flamethrower`, `electric`, and `tesla` shooting speed modifier descriptions |
| Hidden optional dependencies use the `(?)` prefix and affect load order | Factorio mod structure docs | Verified | The main line declares `(?) quality` so module productivity can see Quality module recipes when Quality is active without adding a separate version gate |
| Hidden optional official DLC dependencies can stay out of the user-facing optional list when support is opportunistic | Factorio mod structure docs plus local metadata validation | Verified | The main line declares `(?) elevated-rails` without a separate version gate; Rail productivity covers Elevated Rails support/ramp recipes when those prototypes are active |
| Quality module quality chance is stored on `ModulePrototype.effect.quality` | Factorio `ModulePrototype` and `Effect` docs plus local Quality prototypes | Verified | Quality module enrichment is prototype-stage, not a native infinite technology modifier |
| Omega Drill style content adds the Omega Drill and Space Age Omega-Tau | Factorio mod portal page plus validation fixture | Locally covered by fixture | Mining drill productivity covers `omega-drill`, `omega-tau`, and broader visible modded drill recipe outputs |
| Vanilla Space Age has infinite `processing-unit-productivity` | Local Factorio `2.1.8` Space Age prototypes | Verified | MIR skips parallel processing unit productivity in Space Age |
| Vanilla Space Age has infinite `low-density-structure-productivity` | Local Factorio `2.1.8` Space Age prototypes | Verified | MIR skips covered LDS recipes in Space Age |
| Vanilla Space Age has infinite `plastic-bar-productivity` | Local Factorio `2.1.8` Space Age prototypes | Verified | MIR skips covered plastic recipes in Space Age |
| Vanilla Space Age has infinite `rocket-fuel-productivity` | Local Factorio `2.1.8` Space Age prototypes | Verified | MIR skips covered rocket fuel recipes in Space Age |
| `NothingModifier` can display custom scripted effects in technology UI | Factorio `NothingModifier` docs | Verified | Scripted technologies should use visible `nothing` effects |
| JSON migrations can rename technology prototypes before Lua migrations run | Factorio migrations and data lifecycle docs | Verified | Removed generated technology IDs need explicit migration coverage |
| `DifficultySettings.spoil_time_modifier` is writable and bounded | Factorio `DifficultySettings` docs | Verified | Spoilage preservation can be global, bounded, and event-driven |
| `on_research_finished`, `on_research_reversed`, and `on_technology_effects_reset` exist | Factorio events docs | Verified | Scripted techs can recompute on research lifecycle changes |
| `on_tower_planted_seed` exists | Factorio events docs | Verified for Factorio `2.1.x` | Agricultural growth speed can be event-driven on the main line |
| `LuaEntity.tick_grown` is writable for plants | Factorio `LuaEntity` docs | Verified for Factorio `2.1.x` | Agricultural growth speed can shorten remaining growth time |
| Agricultural tower `owned_plants` can contain the same plant through multiple towers | Factorio `LuaEntity` docs | Verified | Existing plant rescale must dedupe plants |
| `PumpPrototype.pumping_speed` controls pump throughput per tick | Factorio `PumpPrototype` docs | Verified | High-throughput pump is a clean prototype unlock candidate |
| `FluidBox.max_pipeline_extent` is prototype-stage behavior | Factorio `FluidBox` docs | Verified | Pipeline extent belongs as a startup setting, not runtime research |
| `FluidBox.max_pipeline_extent` applies to a pipeline through the minimum extent of all fluid boxes in that pipeline | Factorio `FluidBox` docs plus runtime pipeline fixture | Verified | MIR's current pipeline multiplier is a global fluidbox prototype extension, not only a pipe-entity extension |
| `FluidBox` is used by many prototype classes, including pipes, pipe-to-ground, pumps, storage tanks, crafting machines, mining drills, generators, thrusters, and valves | Factorio `FluidBox` docs | Verified | Pipeline extent docs must warn that non-default values can affect machine/tank/thruster/modded fluid boxes |
| Technology modifier list includes cargo landing pad count, cargo bay unloading distance, and recipe productivity | Factorio modifier docs | Verified | These are native modifier candidates where supported |
| Technology prototypes expose effects and `max_level = "infinite"` | Factorio `TechnologyPrototype` docs | Verified | Generated stream IDs and migration policy are save-compatibility surfaces, not temporary report IDs |
| Technology modifier list includes mining-drill productivity, belt stack size, lab productivity, lab speed, and worker robot modifiers | Factorio modifier docs | Verified | Native modifier ownership diagnostics must stay separate from recipe-productivity streams |
| `RecipePrototype` exposes productivity eligibility, productivity caps, results, ingredients, and surface conditions | Factorio `RecipePrototype` docs | Verified | The compatibility kernel can observe recipe-productivity risk without mutating recipe rules |
| `RecipePrototype.maximum_productivity` is an optional non-negative cap | Factorio `RecipePrototype` docs | Verified | MIR's recipe productivity cap setting can set explicit startup-only recipe caps, while the default leaves recipes unchanged |
| `EffectReceiver` exposes consumption, pollution, speed, and quality effect limits with documented bounds; consumption and pollution lower bounds cannot be below `-0.9999` | Factorio `EffectReceiver` docs | Verified | MIR's energy, pollution, speed, and quality cap settings can mutate effect receiver limit tables during prototype loading; UI exposes `-99.99%` rather than invalid `-100%` |
| `QualityPrototype` chance fields are separate from machine quality effect limits | Factorio `QualityPrototype` docs | Verified | MIR's quality cap setting changes effect receiver caps only; it does not change quality-tier probabilities |
| Loader entities are distinct `LoaderPrototype` surfaces, including the `loader` and `loader-1x1` prototype types seen in local base prototypes | Factorio `LoaderPrototype` docs plus local Factorio `2.1.9` base prototypes | Verified | Loader support should mean loader crafting productivity, not loader throughput or operating behavior |
| Mining drills are distinct `MiningDrillPrototype` entities | Factorio `MiningDrillPrototype` docs plus local Factorio `2.1.9` base prototypes | Verified | Drill manufacturing productivity and native mining-yield productivity are separate lanes |
| Labs expose accepted science inputs on `LabPrototype` | Factorio `LabPrototype` docs plus runtime custom-lab fixtures | Verified | Added science packs should be validated against labs instead of hard-coded by mod name |
| `change-recipe-productivity` is an official technology modifier type | Factorio modifier docs plus runtime fluid-productivity fixtures | Verified | Fluid-output productivity should stay native recipe productivity instead of runtime fluid scripting |
| `change-recipe-productivity` is scoped by explicit recipe ID and `change`, not by output item family | Factorio `ChangeRecipeProductivityModifier` docs | Verified | Vanilla family adoption must append exact recipe effects to an existing owner technology |
| Factorio `1.1.110` rejects `change-recipe-productivity` | Disposable local proof mod loaded with `D:\Programs\Factorio\1.1\bin\x64\factorio.exe --dump-data`; load failed with `Unknown modifier type "change-recipe-productivity"` | Locally disproven for `1.1` | Keep recipe-productivity streams disabled on the `1.1` target line and document missing item/intermediate/science-pack productivity as an engine-surface exclusion |
| Factorio `1.1` generated direct-effect technologies can use target-era high-resolution core `constants/*` art as technology tile badges | Runtime fixture `mir-fixture-assert-legacy-effect-icons` in the `factorio-1.1-direct-effects` validation scenario | Locally proven for `1.9.3` | Older rings should define target-line overlay mappings instead of bundling newer core graphics or using effect-row sprites as tile badges |
| Factorio `0.18`/`1.0` lacks separate technology constant/control icon assets and does not document native modifier icon fields for normal effects | Local Factorio `1.0` install scan plus `doc-html/Concepts.html` modifier schema review | Locally disproven for badge simulation | The `1.8.0` bridge uses main technology textures and locale text instead of synthetic badge overlays or native modifier icon metadata |
| Factorio `0.17.79` includes disabled tutorial technologies, and `LuaForce.research_all_technologies()` excludes disabled prototypes unless explicitly requested | Local `0.17.79` base prototypes, shipped `doc-html/LuaForce.html`, and MIR target-binary state probe | Locally proven | Science-pack prerequisite inference must ignore disabled technologies; otherwise `basic-mining` blocks normal generated research |
| `mod-data` prototypes can carry arbitrary prototype-stage data and are readable at runtime through `prototypes.mod_data` | Factorio `ModData` docs | Verified | The data stage can publish the productivity-family adoption signature for runtime migration handling |
| `LuaForce.reset_technology_effects()` reapplies research effects while preserving technology research state | Factorio `LuaForce` docs | Verified | Existing saves can refresh newly adopted recipe effects, but the reset must be signature-guarded because custom force-state changes are lost |
| `script.on_configuration_changed` runs when mod versions, mod lists, startup settings, prototypes, or migrations change | Factorio `LuaBootstrap` docs | Verified | Adding or removing a planet mod can trigger the adoption-signature refresh path |
| `settings.startup` exposes startup mod settings as a read table | Factorio `LuaSettings` docs | Verified | MIR can read startup settings during prototype loading but should not rely on runtime code to rewrite startup generation choices |
| Runtime setting writes are limited to runtime global/player setting tables, not startup settings | Factorio `LuaSettings` docs | Verified | MIR settings-profile import is a startup setting consumed on restart, while runtime commands only export or validate profile strings |
| `helpers.write_file` writes files under `script-output` | Factorio `LuaHelpers` docs | Verified | `/mir-settings-export` writes profile strings to `script-output/more-infinite-research/settings/` |
| `helpers.table_to_json`, `helpers.json_to_table`, `helpers.encode_string`, and `helpers.decode_string` exist | Factorio `LuaHelpers` docs | Verified | MIR settings profiles can use a compact `MIRSET1:` encoded JSON payload without adding external parsers |
| Recipe results can be item or fluid product prototypes | Factorio `ProductPrototype` docs plus runtime fluid-productivity fixtures | Verified | Shared recipe matching can safely inspect fluid outputs as first-class recipe products |
| Thrusters expose `fuel_fluid_box` and `oxidizer_fluid_box` as `FluidBox` prototype fields | Factorio `ThrusterPrototype` docs | Verified | Pipeline extent scanning can reach thruster fluid boxes; thruster productivity remains recipe-output productivity, not thrust mutation |
| Fluid prototypes expose `icon`/`icons` fields | Factorio `FluidPrototype` docs | Verified | Fluid-output productivity streams can use fluid prototypes as icon candidates |
| `change-recipe-productivity` works cleanly for thruster fuel/oxidizer fluid-output recipes | Runtime fixture asserts exact recipe ownership and no duplicate infinite owner on Factorio `2.1.9` | Locally proven | `v2.1.0` has automated release proof for the native recipe-productivity claim; non-default balance recommendations still need save-level soak |
| `change-recipe-productivity` works cleanly for oil/fluid-output recipes | Runtime fixture asserts oil-processing, cracking, lubricant, sulfuric-acid, and Space Age acid-neutralisation ownership on Factorio `2.1.9` | Locally proven | `v2.1.0` has automated release proof for the native recipe-productivity claim; non-default balance recommendations still need save-level soak |

## Unknown Or Requires In-Game Test

| Claim | Required test | Target |
| --- | --- | --- |
| Changing `spoil_time_modifier` affects newly created spoilable items exactly as expected | Create spoilable items before and after research; compare spoil deadlines | v2.0.5 |
| Changing `spoil_time_modifier` affects existing belts/chests/labs/rockets/platform inventories | Use named manual save with existing stacks in each location | v2.0.5 if claiming existing-stack behavior; otherwise document limitation |
| Existing partially spoiled stacks recalculate or keep fixed spoil deadlines | Save with partially spoiled stacks before research | v2.0.5 if claiming existing-stack behavior; otherwise document limitation |
| Newly planted agricultural tower crops receive the growth-speed adjustment | Plant tower crops after research and compare `tick_grown` / observed growth time | v2.0.5 |
| Existing agricultural tower plants can be rescaled safely | Research/reverse growth tech in a large farm and dedupe owned plants | v2.1.0 unless proven small |
| Pipeline extent multiplier has acceptable balance and compatibility impact in large/modded fluid networks | Long-running saves and modpack soak with non-default multiplier values | v2.1.0 if making stronger recommendation than default `100%` |
| Factorio `2.0.x` exposes the agricultural tower events and fields needed by scripted agriculture | Validate on a Factorio `2.0.x` binary during legacy port | v1.9.0 |
| Factorio `2.0.x` supports any later current-line pump/pipeline prototype fields | Validate on a Factorio `2.0.x` binary during the matching legacy port | v1.9.x after the feature ships |

## API Links

- Mod structure: <https://lua-api.factorio.com/latest/auxiliary/mod-structure.html>
- Modifier list: <https://lua-api.factorio.com/latest/types/Modifier.html>
- `TechnologyPrototype`: <https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html>
- `ChangeRecipeProductivityModifier`: <https://lua-api.factorio.com/latest/types/ChangeRecipeProductivityModifier.html>
- `RecipePrototype`: <https://lua-api.factorio.com/latest/prototypes/RecipePrototype.html>
- `EffectReceiver`: <https://lua-api.factorio.com/latest/types/EffectReceiver.html>
- `QualityPrototype`: <https://lua-api.factorio.com/latest/prototypes/QualityPrototype.html>
- `LoaderPrototype`: <https://lua-api.factorio.com/latest/prototypes/LoaderPrototype.html>
- `MiningDrillPrototype`: <https://lua-api.factorio.com/latest/prototypes/MiningDrillPrototype.html>
- `LabPrototype`: <https://lua-api.factorio.com/latest/prototypes/LabPrototype.html>
- `ModData`: <https://lua-api.factorio.com/latest/prototypes/ModData.html>
- `NothingModifier`: <https://lua-api.factorio.com/latest/types/NothingModifier.html>
- Migrations: <https://lua-api.factorio.com/latest/auxiliary/migrations.html>
- Data lifecycle: <https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html>
- Events: <https://lua-api.factorio.com/latest/events.html>
- `LuaEntity`: <https://lua-api.factorio.com/latest/classes/LuaEntity.html>
- `LuaItemStack`: <https://lua-api.factorio.com/latest/classes/LuaItemStack.html>
- `LuaForce`: <https://lua-api.factorio.com/latest/classes/LuaForce.html>
- `LuaBootstrap`: <https://lua-api.factorio.com/latest/classes/LuaBootstrap.html>
- `LuaSettings`: <https://lua-api.factorio.com/latest/classes/LuaSettings.html>
- `LuaHelpers`: <https://lua-api.factorio.com/latest/classes/LuaHelpers.html>
- `DifficultySettings`: <https://lua-api.factorio.com/latest/concepts/DifficultySettings.html>
- `PumpPrototype`: <https://lua-api.factorio.com/latest/prototypes/PumpPrototype.html>
- `FluidBox`: <https://lua-api.factorio.com/latest/types/FluidBox.html>
- `ThrusterPrototype`: <https://lua-api.factorio.com/latest/prototypes/ThrusterPrototype.html>
- `ProductPrototype`: <https://lua-api.factorio.com/latest/types/ProductPrototype.html>
- `FluidPrototype`: <https://lua-api.factorio.com/latest/prototypes/FluidPrototype.html>
- `LuaTechnology`: <https://lua-api.factorio.com/latest/classes/LuaTechnology.html>
- `ModulePrototype`: <https://lua-api.factorio.com/latest/prototypes/ModulePrototype.html>
- `Effect`: <https://lua-api.factorio.com/latest/types/Effect.html>
