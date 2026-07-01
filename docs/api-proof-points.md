# API Proof Points

Updated: 2026-07-01

This ledger records API claims that affect release planning. Use it to avoid turning Reddit ideas or memory into implementation assumptions.

Official Factorio API references should be rechecked before a release if the local Factorio version changes.

Latest official API docs checked on 2026-07-01: `2.1.9`. Local runtime validation evidence in `docs/test-results.md` is still from Factorio `2.1.8`.

## Verified Or Locally Proven

| Claim | Proof source | Status | Release impact |
| --- | --- | --- | --- |
| Mod zip names follow `{mod-name}_{version}` and `info.json` controls Factorio compatibility | Factorio mod structure docs | Verified | Package validation must match `info.json` and zip filename |
| `factorio_version = "2.0"` and `factorio_version = "2.1"` are separate release targets | Factorio mod structure docs | Verified | Main `v2.x` line targets Factorio `2.1.x`; legacy `v1.9.0` targets Factorio `2.0.x` |
| `gun-speed` modifiers use `ammo_category` | Factorio modifier docs plus local prototype files | Verified | Electric shooting speed must include `tesla` for Tesla weapons |
| Space Age Tesla gun/ammo/turret use `ammo_category = "tesla"` | Local Factorio `2.1.8` Space Age prototypes | Verified | Tesla turret speed is covered by `tesla`, not `electric` |
| Base discharge defense uses `ammo_category = "electric"` | Local Factorio `2.1.8` base prototypes | Verified | Keep `electric` effect for discharge-defense-style equipment |
| Vanilla tank cannon fire-rate bonuses are `gun-speed` effects for `cannon-shell` on finite `weapon-shooting-speed` technologies | Local Factorio `2.1.8` base prototypes | Verified | MIR overlap handling must preserve finite vanilla `cannon-shell` speed effects |
| Base game locale does not provide every generated shooting-speed modifier string MIR needs | Local Factorio `2.1.8` base and Space Age locale files | Verified | MIR ships `flamethrower`, `electric`, and `tesla` shooting speed modifier descriptions |
| Hidden optional dependencies use the `(?)` prefix and affect load order | Factorio mod structure docs | Verified | The main line declares `(?) quality >= 2.1.8` so module productivity can see Quality module recipes |
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
| Technology modifier list includes cargo landing pad count, cargo bay unloading distance, and recipe productivity | Factorio modifier docs | Verified | These are native modifier candidates where supported |

## Unknown Or Requires In-Game Test

| Claim | Required test | Target |
| --- | --- | --- |
| Changing `spoil_time_modifier` affects newly created spoilable items exactly as expected | Create spoilable items before and after research; compare spoil deadlines | v2.0.5 |
| Changing `spoil_time_modifier` affects existing belts/chests/labs/rockets/platform inventories | Use named manual save with existing stacks in each location | v2.0.5 if claiming existing-stack behavior; otherwise document limitation |
| Existing partially spoiled stacks recalculate or keep fixed spoil deadlines | Save with partially spoiled stacks before research | v2.0.5 if claiming existing-stack behavior; otherwise document limitation |
| Newly planted agricultural tower crops receive the growth-speed adjustment | Plant tower crops after research and compare `tick_grown` / observed growth time | v2.0.5 |
| Existing agricultural tower plants can be rescaled safely | Research/reverse growth tech in a large farm and dedupe owned plants | v2.1.0 unless proven small |
| `change-recipe-productivity` works cleanly for thruster fuel/oxidizer fluid recipes | Throwaway recipe-productivity test and runtime fixture | v2.1.x spike |
| `change-recipe-productivity` works cleanly for oil/fluid-output recipes | Throwaway oil productivity test and runtime fixture | v2.1.x spike |
| Factorio `2.0.x` exposes the agricultural tower events and fields needed by scripted agriculture | Validate on a Factorio `2.0.x` binary during legacy port | v1.9.0 |
| Factorio `2.0.x` supports any later current-line pump/pipeline prototype fields | Validate on a Factorio `2.0.x` binary during the matching legacy port | v1.9.x after the feature ships |

## API Links

- Mod structure: <https://lua-api.factorio.com/latest/auxiliary/mod-structure.html>
- Modifier list: <https://lua-api.factorio.com/latest/types/Modifier.html>
- `NothingModifier`: <https://lua-api.factorio.com/latest/types/NothingModifier.html>
- Migrations: <https://lua-api.factorio.com/latest/auxiliary/migrations.html>
- Data lifecycle: <https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html>
- Events: <https://lua-api.factorio.com/latest/events.html>
- `LuaEntity`: <https://lua-api.factorio.com/latest/classes/LuaEntity.html>
- `LuaItemStack`: <https://lua-api.factorio.com/latest/classes/LuaItemStack.html>
- `DifficultySettings`: <https://lua-api.factorio.com/latest/concepts/DifficultySettings.html>
- `PumpPrototype`: <https://lua-api.factorio.com/latest/prototypes/PumpPrototype.html>
- `FluidBox`: <https://lua-api.factorio.com/latest/types/FluidBox.html>
- `LuaTechnology`: <https://lua-api.factorio.com/latest/classes/LuaTechnology.html>
- `ModulePrototype`: <https://lua-api.factorio.com/latest/prototypes/ModulePrototype.html>
- `Effect`: <https://lua-api.factorio.com/latest/types/Effect.html>
