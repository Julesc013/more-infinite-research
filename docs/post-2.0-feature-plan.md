# Post-2.0 Feature Plan

Updated: 2026-07-01

This document records the feature triage from the first public v2.0.0 discussion and turns it into a bounded plan for More Infinite Research after v2.0.0.

The core conclusion is:

> More Infinite Research should stay focused on research-driven scaling, but add a small scripted-tech framework and a few carefully scoped optional prototype/entity unlocks. It should not become a full Gleba overhaul, refrigeration mod, greenhouse mod, or space-platform overhaul.

The Reddit thread was not one feature request. It was a roadmap dump. The useful split is:

1. Core More Infinite Research features: infinite or configurable research sinks.
2. Core-adjacent logistics QoL: late-game entities or settings unlocked by research.
3. Companion mods: refrigeration, greenhouses, new biology loops, unusual quality/spoilage mechanics.
4. Compatibility and UX work: presets, backports, modpack testing, duplicate-tech detection.

The major constraint is UPS. Anything requiring per-tick inventory scanning or constant entity mutation should be treated as a separate mod or disabled-by-default experiment. MIR's default policy should be no per-tick scanning for generated research effects.

## Scope Rule

Use this table as the product boundary.

| Category | Belongs in MIR? | Reason |
| --- | ---: | --- |
| Native technology modifiers | Yes | This is the mod's core purpose. |
| Generated recipe productivity | Yes | Already core to the mod. |
| Scripted effects with event hooks only | Yes, carefully | Good for spoilage/growth if no per-tick scans are needed. |
| Late-game finite unlocks that solve megabase bottlenecks | Maybe / optional | Pumps fit better than thrusters. |
| Startup prototype tweaks | Maybe, disabled by default | Useful, but not really research. |
| New production chains | Usually no | Better as companion mods. |
| Refrigeration/freezing/cold-chain logistics | Separate mod | Too much new gameplay and potential UPS risk. |
| Greenhouses / off-world Gleba farming | Separate mod | This is an agriculture overhaul. |
| Super-bacteria / new ore biology | Separate mod | Content expansion, not research extension. |

The mod should not become "Everything Infinite and Also Every Cool New Building." It should become the research-sink framework that other late-game scaling ideas can plug into.

## Performance Policy

MIR should document and follow this policy:

```text
More Infinite Research avoids per-tick scanning.
Scripted technologies are event-based where possible.
Experimental features that require active scanning are disabled by default or moved to companion mods.
```

Feature descriptions should label implementation risk:

- Native.
- Recipe productivity.
- Scripted event-only.
- Prototype/global.
- Sandbox.
- Experimental.
- May affect existing builds.

This matters most for spoilage. Slower spoilage can help megabases, but it can also break factories that intentionally consume spoilage or depend on spoilage timing.

## Priority Roadmap

### P0: Architecture And Settings

These should come before or alongside new content.

| Feature | Add? | Notes |
| --- | ---: | --- |
| Scripted-tech framework | Yes | Required for spoilage/growth and future non-native effects. |
| Settings presets | Yes | The thread shows users want "add more infinite research like vanilla" as well as sandbox behavior. |
| Feature categories in settings | Yes | Group by Productivity, Character, Logistics, Cargo, Agriculture, Scripted, Sandbox. |
| Compatibility matrix | Yes | Users asked about Maraxis and Krastorio 2 Spaced Out. |
| Duplicate-effect detection | Yes | Especially for cargo landing pad techs if other mods add similar modifiers. |
| Factorio 2.0 backport branch | Yes, gated | Do not assume 2.1 APIs exist in 2.0. |

### Settings Presets

Presets are the most important UX improvement because the mod already has many raw settings.

Recommended presets:

```text
Preset: Vanilla-respectful
- Add new infinite researches.
- Do not uncap vanilla capped techs by default.
- Disable heavily game-changing scripted techs by default.

Preset: Megabase-balanced
- Enable most generated productivity techs.
- Enable cargo/logistics/agriculture techs.
- Keep strong sandbox features capped or expensive.

Preset: Unlimited sandbox
- Current philosophy.
- Everything configurable and mostly infinite.
```

Preset first, advanced toggles second.

### P1: v2.0.5 Agriculture And Preservation

Ship:

- Scripted-tech framework.
- Spoilage preservation.
- Agricultural growth speed.
- Settings presets, if small enough to land safely.
- Better feature descriptions.
- Compatibility diagnostics for scripted effects.

Maybe ship:

- Agricultural yield, disabled by default.
- Thruster fuel and oxidizer productivity if validation is clean and the scope stays small.

Do not ship:

- Refrigeration.
- Greenhouses.
- Quality module odds.
- Thruster variants.
- Biter egg chaos.
- High-throughput pumps.

### P2: v2.0.6 Logistics QoL

Ship:

- High-throughput pump, optional.
- Pipeline extent startup setting, disabled by default.
- Fluid train unloading notes/docs.
- Thruster fuel/oxidizer productivity coverage if not already included in v2.0.5.

Maybe ship:

- "Der Pump" as a large late-game pump variant if it does not dilute MIR's identity.

### P3: v2.0.7 Productivity Coverage And Compatibility

Ship:

- Engine/electric engine productivity verification.
- Oil processing productivity test result.
- Biochamber recipe productivity support where valid.
- Modded recipe diagnostics.
- Maraxis and Krastorio 2 Spaced Out compatibility testing when those targets are available for the active Factorio line.

### P4: v2.1.0 Or Companion Mods

Split out if needed:

```text
More Infinite Logistics
- high-throughput pumps
- pipeline settings
- thruster variants

Cold Chain / CryoPants
- freezer chest
- freeze/thaw recipes
- freshness penalty
- refrigerated transport

Advanced Agriculture
- greenhouses
- off-world fruit
- super-bacteria
- optional agricultural yield loops

Advanced Quality Research
- quality module tiers
- quality odds tuning
- quality-based spoilage multipliers
```

## Actionable Feature List

| Feature | Add to MIR? | Method | Priority |
| --- | ---: | --- | ---: |
| Settings presets | Yes | Startup setting plus derived defaults | P0 |
| Scripted-tech framework | Yes | `control/scripted-techs.lua` | P0 |
| Duplicate-effect detection | Yes | Data-stage effect overlap scan | P0 |
| Maraxis compatibility | Yes | Detect duplicate cargo techs | P0/P1 |
| K2 Spaced Out compatibility | Yes | Test matrix | P0/P1 |
| Factorio 2.0 backport | Yes, gated | Separate branch/release | P0 |
| Spoilage preservation | Yes | `spoil_time_modifier` | P1 |
| Agricultural growth speed | Yes | `on_tower_planted_seed` plus `tick_grown` | P1 |
| Engine unit productivity | Already yes | Generated recipe productivity | Existing |
| Electric engine productivity | Already yes | Generated recipe productivity | Existing |
| Flying robot frame productivity | Already yes | Generated recipe productivity | Existing |
| Rail/concrete/inserter/furnace productivity | Already yes | Generated recipe productivity | Existing |
| Robot battery/carrying capacity | Already yes | Native worker robot modifiers/base extensions | Existing |
| Agricultural yield | Maybe | `on_tower_mined_plant` buffer | P2 |
| Harvest/plant crane speed | No for now | Prototype/runtime unclear | Later |
| Thruster fuel productivity | Yes | Generated recipe productivity | P2 |
| Thruster oxidizer productivity | Yes | Generated recipe productivity | P2 |
| Oil processing productivity | Investigate | Test recipe productivity on fluid outputs | P2 |
| Biochamber oil/productivity incentives | Investigate | Prefer recipe streams over new MIR recipes | P2 |
| High-throughput pump | Optional/core-adjacent | New pump prototype | P2 |
| Pipeline extent multiplier | Optional | Startup prototype setting | P2 |
| Fluid train unloading | Mostly covered | Stronger pump plus docs | P2 |
| More thrust research | No | No clean native modifier | Later/separate |
| Efficient thruster | Separate/addon | New thruster prototype | Later |
| High-thrust thruster | Separate/addon | New thruster prototype | Later |
| Quality module odds | Maybe addon | New module tiers/prototype tuning | Later |
| Quality-based spoilage multiplier | Maybe addon | `QualityPrototype.spoil_ticks_multiplier` | Later |
| Roboport range | Not core | New roboport tier/startup setting | Later/addon |
| Equipment roboport radius | Not core | Investigate only if native modifier exists | Later/addon |
| Assembler innate productivity | Not as stated | Prefer recipe productivity | Later |
| Foundry/EM engine recipes | Separate | Recipe/content mod | Separate |
| Refrigeration/freezer/CryoPants | Separate | Cold-chain mod | Separate |
| Barrel-aged or quality-aged science | Separate | Item lifecycle experiment | Separate |
| Greenhouse anywhere | Separate | Agriculture content mod | Separate |
| Super-bacteria ores | Separate | Agriculture/resource overhaul | Separate |
| Biter egg accelerator | Separate/disabled | Experimental/challenge mod | Separate |

## Implementation Architecture

Add a feature registry so every new idea has a clear implementation kind.

```lua
{
  name = "spoilage-preservation",
  kind = "scripted-effect",
  default_enabled = "preset-dependent",
  required_mods = {"space-age"},
  min_factorio_version = "2.1.0",
  science_pack_policy = "space-age-late",
  effect = {
    type = "spoil-time-multiplier",
    per_level = 0.01,
    formula = "compound",
    cap = 100
  }
}
```

Use five feature kinds:

| Kind | Example | Runtime |
| --- | --- | --- |
| `native-modifier` | cargo landing pad count | None |
| `recipe-productivity` | engine unit productivity | None |
| `scripted-effect` | spoilage preservation | Event-only |
| `entity-unlock` | high-throughput pump | None |
| `prototype-setting` | pipeline extent multiplier | None |

Keep control-stage code small:

```text
control.lua
control/scripted-techs.lua
control/effects/spoilage-preservation.lua
control/effects/agricultural-growth-speed.lua
control/effects/agricultural-yield.lua
```

The scripted manager should handle:

- `on_init`
- `on_configuration_changed`
- `on_research_finished`
- `on_research_reversed`
- `on_technology_effects_reset`
- `on_runtime_mod_setting_changed`, only if runtime toggles are added

When `control.lua` is introduced, update `docs/architecture.md` with a control-stage architecture section and update validation for existing-save loads.

## Feature Notes

### Spoilage Preservation

This is viable because Factorio exposes `game.difficulty_settings.spoil_time_modifier` as a writable runtime difficulty setting. The field is global to the map, not force-local.

Recommended behavior:

- Add `research_spoilage_preservation`.
- Generate an infinite technology with a visible `nothing` effect description.
- Require Space Age and spoilage-relevant science.
- Use `spoil_time_multiplier = 1.01 ^ completed_levels`.
- Use player-facing wording: `Spoilage time: +1% per level`.
- Clamp to the engine range, especially the documented maximum `100`.
- Store the original map value as a baseline and multiply from that baseline.
- Use the highest researched level across non-neutral player forces.
- Reapply on init, configuration change, research finish, research reversal, and technology effect reset.
- Do not scan inventories, belts, labs, containers, or item stacks.

Do not use a flat `-1% spoilage speed per level` formula. It eventually reaches zero/negative speed and is harder to explain.

Existing stack behavior must be tested before promising it. `LuaItemStack.spoil_tick` is a writable absolute tick, so existing items may already have fixed spoil deadlines depending on how the engine recalculates them.

Changelog-safe wording:

```text
Adds scripted spoilage preservation research that increases the global spoil time modifier. Existing stack behavior is tested against the supported Factorio version.
```

Recommended default:

- Enabled in Megabase-balanced or Unlimited sandbox.
- Disabled or very expensive in Vanilla-respectful.
- Effective cap at `100x` spoil time.

### Agricultural Growth Speed

This is viable if it remains event-driven. Factorio exposes agricultural tower events, and plant entities expose writable `tick_grown`, the tick when the plant becomes fully grown.

Recommended behavior:

- Add `research_agricultural_growth_speed`.
- Generate an infinite technology with a visible `nothing` effect description.
- Use `on_tower_planted_seed`, then adjust `plant.tick_grown`.
- Use `+1% plant growth speed per level`, compounded.
- Avoid `on_tick`.
- Rescale existing tower-owned plants on research finish/reversal if the operation stays bounded.
- Dedupe existing plants during rescale because one plant can be registered in multiple agricultural towers.
- Default cap around `10x` growth speed.
- Enable in Space Age/Megabase presets.

Implementation shape:

```lua
local function accelerate_plant_remaining_growth(plant, now, multiplier)
  if not plant.valid or multiplier <= 1 then return end

  local remaining = plant.tick_grown - now
  if remaining <= 1 then return end

  plant.tick_grown = now + math.max(1, math.floor(remaining / multiplier))
end
```

On research change:

```lua
new_remaining = old_remaining * old_multiplier / new_multiplier
```

That keeps reversals and level changes understandable.

Open tests:

- Confirm exact event payload shape for `on_tower_planted_seed`.
- Confirm whether the plant entity is available before or after planting, or whether delayed handling is required.
- Confirm `tower.owned_plants` is available and cheap enough for research-change rescaling.

### Agricultural Yield

This is feasible but balance-heavy, so it should not be bundled with the first agriculture patch unless it proves simple.

Recommended behavior:

- Add `research_agricultural_yield` or `research_harvest_productivity`.
- Use `on_tower_mined_plant`.
- Add extra fruit/plant products into the mining result buffer.
- Modify results once per harvest, not per tick.
- Keep disabled by default until benchmarked and balanced.

Growth speed is "faster farming." Yield is "more output per farm," which is closer to productivity and more likely to change Gleba balance.

### Thruster Fuel And Oxidizer Productivity

This is the clean near-term answer to "thruster efficiency" because it improves effective fuel economy without changing platform physics.

Recommended behavior:

- Add exact recipe-productivity streams for `thruster-fuel` and `thruster-oxidizer`.
- Gate on Space Age and the relevant fluid/recipe prototypes.
- Add fluid-aware icon lookup or explicit technology icons, because the current icon helper is item-oriented.
- Validate whether `change-recipe-productivity` applies cleanly to the target recipes and products in a Space Age runtime test.

Avoid:

- Runtime platform speed manipulation.
- Fake thrust modifiers.
- Per-platform fuel accounting scripts.

### High-Throughput Pump

The pump complaint is real and the prototype path is clean. `PumpPrototype.pumping_speed` is the amount of fluid transferred per tick.

Recommended feature:

| Property | Recommendation |
| --- | --- |
| Name | `High-throughput pump` or `Industrial pump` |
| Type | Finite unlock, not infinite tech |
| Throughput | Configurable; likely `6000 fluid/s` target |
| Prototype value | `pumping_speed = 100` at 60 ticks/s for `6000 fluid/s` |
| Power | Much higher than normal pump |
| Recipe | Pump plus processing units plus Space Age materials |
| Default | Optional enabled |
| UPS impact | None beyond normal entity behavior |

This is borderline for MIR. Prefer one of:

```text
Option A:
Include it in MIR as an optional late-game unlock.

Option B:
Create More Infinite Logistics as a companion mod.
```

If included in MIR, keep it behind a setting and do not combine it with pipeline extent changes in the same first release.

### Pipeline Extent

This is a startup setting, not research. `FluidBox.max_pipeline_extent` is prototype-stage behavior, and pipeline extent is determined by the minimum extent of all fluid boxes in the pipeline.

Recommended setting:

```text
Startup setting: pipeline extent multiplier
Values: 1x, 2x, 5x, 10x
Default: 1x
```

Do not make this infinite research.

### Fluid Train Unloading

Do not create special train-unloading scripts. A stronger pump entity already improves station throughput without active control code.

### Oil Processing Productivity

Investigate, then add if clean.

Test:

- Basic oil processing productivity.
- Advanced oil processing productivity.
- Coal liquefaction productivity.
- Biochamber oil-related recipes.
- Recipes with only fluid outputs.
- Recipes with mixed item/fluid outputs.

If `change-recipe-productivity` applies cleanly to fluid-output recipes, add streams. If it does not, do not script fluid production every tick.

### Quality Module Odds

This is interesting but not clean as true infinite runtime research. Quality is mostly prototype-defined through module effects and quality prototype fields.

Better options:

| Option | Fit |
| --- | --- |
| Generate finite higher-tier quality modules | Good companion/addon feature |
| Startup setting to globally tune quality odds | Possible, but not research |
| Infinite tech that changes module behavior at runtime | Avoid |
| Infinite tech that unlocks finite module tiers every N levels | Awkward; finite prototypes only |

Do not add this to v2.0.5. Consider a later optional Advanced Quality Research add-on.

### Quality-Based Spoilage Preservation

This was missing from the first pass. `QualityPrototype.spoil_ticks_multiplier` suggests a clean prototype-stage option:

```text
Higher-quality spoilable items last longer.
```

This is not an infinite technology effect, but it ties together quality and spoilage in a clean way.

Possible setting:

```text
Quality affects spoil time:
- Disabled
- Mild
- Vanilla/default
- Strong
```

Keep this separate from scripted global spoilage preservation.

### Robot And Roboport Ideas

Robot battery and carrying capacity belong in MIR because Factorio has native worker robot technology modifiers and vanilla/base-extension paths. MIR already covers this category.

Roboport range and equipment roboport radius are not clean infinite techs unless a native modifier exists.

Better options:

| Option | Recommendation |
| --- | --- |
| New roboport tier | Companion feature |
| Startup setting to increase roboport logistics/construction radius | Possible, disabled by default |
| Quality effects for roboport charging behavior | Investigate |
| Runtime infinite research for all roboports | Avoid unless a native modifier exists |

### Refrigeration And Cold Chain

This should be a separate mod. The thread had a substantial refrigeration/freezing subdiscussion: stopping or slowing spoilage in space, freezer chests with ice, cold transport, CryoPants, and concerns about removing Gleba's challenge.

Best separate-mod design:

```text
Cold Chain / CryoPants
- Freezer chest
- Maybe refrigerated cargo bay / wagon
- Ice or coolant cost
- Freshness penalty on freeze/thaw
- No per-tick scanning if avoidable
- Strong drawbacks so it does not replace normal Gleba design
```

The most UPS-safe design is likely packaging/conversion recipes:

```text
fresh item -> frozen item
frozen item -> thawed item at reduced freshness
```

That avoids calculating every stack in every container every tick.

### Barrel-Aged Science And Reverse Spoilage

This is a separate joke/experimental mod. It is an item-lifecycle mechanic, not MIR.

Possible later shape:

```text
Aged science packs:
- Put science into barrels/vats.
- Wait.
- Output higher-quality science with chance/freshness penalty.
```

### Greenhouse Anywhere

This is a strong idea, but it is a full content mod: sun lamps, heating on Aquilo, overgrowth soil, off-world yumako/jellynut, biochamber chains, and restrictions around pentapod/biter eggs.

Possible companion mod:

```text
Advanced Agriculture / Greenhouse Logistics
- Late-game greenhouse
- Works off Gleba
- High power cost
- Heating requirement on Aquilo
- Soil or artificial soil input
- Worse than agricultural towers
- Does not allow full agricultural science off Gleba by default
```

### Super-Bacteria For Ores

This is a separate agriculture/resource overhaul. It changes resource acquisition and planet identity.

### Foundry/EM Plant Engine Recipes

Engine productivity belongs in MIR. New foundry/electromagnetic plant recipes for engines belong elsewhere. MIR should support those recipes if present by detecting them and generating productivity techs where appropriate.

### Efficient And High-Thrust Thrusters

Thruster fuel/oxidizer productivity belongs in MIR. New thruster entities probably do not.

Possible companion feature:

```text
Efficient thruster
- Same thrust
- Lower fluid usage
- Expensive recipe

High-thrust thruster
- More thrust
- More fuel usage
- Expensive recipe
```

Avoid a scripted "multiply platform speed" hack.

### Biter Egg Accelerator

This is a separate chaos mod or disabled experiment. The idea could be funny, but the UPS and balance risk are too high for MIR core.

## Duplicate-Tech Policy

For mods such as Maraxis that may add cargo landing pad research, use one of these behaviors:

- Detect overlapping native modifiers and skip MIR's version.
- Keep both but warn in diagnostics.
- Add setting: `Allow duplicate overlapping infinite technologies`.

Safest default:

```text
Skip or disable MIR's duplicate if another infinite technology already modifies the same stat.
```

This is roadmap work, not polish, because public feedback already includes compatibility questions about overlapping cargo landing pad research.

## Compatibility And Validation Plan

Minimum new matrix:

```text
Vanilla 2.1 + Space Age
Vanilla 2.1 without Space Age
2.0 legacy branch
Maraxis when updated
Krastorio 2 Spaced Out
Popular science-pack mods
Popular quality/module mods
Popular refrigeration/spoilage mods
```

New v2.0.5 validation should add:

- Space Age with spoilage preservation enabled.
- Space Age with agricultural growth speed enabled.
- Research-level-change test for spoilage modifier recalculation.
- Research-level-change test for tower-planted growth adjustment.
- Existing-save load with new `control.lua`.
- Disable/remove mod behavior for spoilage baseline restoration.
- Runtime fixture or manual test for `thruster-fuel` and `thruster-oxidizer` productivity.
- Space Age without Quality where Factorio permits it.
- Maraxis or other cargo-pad mods when updated to Factorio 2.1.
- Krastorio 2 Spaced Out or equivalent large overhaul once compatible with the target Factorio version.

## Factorio 2.0 Backport Reality

Be careful with the backport promise. The current 2.1 path can use clean agricultural tower events and cargo landing pad APIs. The 2.0 line may not have those APIs.

Do not assume in Factorio 2.0:

- Cargo landing pad modifiers exist.
- Agricultural tower events exist.
- Newer quality prototype fields exist.

Best backport plan:

```text
2.1 main branch:
- Full feature set.

2.0 legacy branch:
- Generated productivity techs.
- Older native modifiers.
- No cargo landing pad count/unloading distance unless supported.
- No agricultural growth speed unless the event exists.
- No scripted agriculture if it needs polling.
```

A Factorio 2.0 backport should be a best-compatible subset on `legacy`, not a promise of full feature parity.

## Missing Work Before Implementation

Before writing feature code:

1. Decide defaults for spoilage preservation and agricultural growth speed in each preset.
2. Verify `NothingModifier` display shape in Factorio 2.1.8+.
3. Confirm event payloads for agricultural tower planting and harvesting.
4. Confirm whether `change-recipe-productivity` works as expected for thruster fluid recipes.
5. Confirm whether `change-recipe-productivity` works for oil/fluid-output recipes.
6. Add a control-stage architecture section when `control.lua` is introduced.
7. Add release notes that clearly distinguish MIR features from companion-mod ideas.
8. Add duplicate-tech detection for overlapping native modifiers.
9. Add performance labels to docs and setting descriptions for scripted/global/sandbox features.

## API References

- Technology modifiers: <https://lua-api.factorio.com/latest/types/Modifier.html>
- `NothingModifier`: <https://lua-api.factorio.com/latest/types/NothingModifier.html>
- Difficulty settings and `spoil_time_modifier`: <https://lua-api.factorio.com/latest/concepts/DifficultySettings.html>
- Item stack spoil ticks: <https://lua-api.factorio.com/latest/classes/LuaItemStack.html>
- Plant `tick_grown`: <https://lua-api.factorio.com/latest/classes/LuaEntity.html#tick_grown>
- Agricultural tower events: <https://lua-api.factorio.com/latest/events.html#on_tower_planted_seed>
- Pump prototype `pumping_speed`: <https://lua-api.factorio.com/latest/prototypes/PumpPrototype.html>
- Fluid box pipeline extent: <https://lua-api.factorio.com/latest/types/FluidBox.html>
- Thruster prototype performance: <https://lua-api.factorio.com/latest/prototypes/ThrusterPrototype.html>
- Module prototypes: <https://lua-api.factorio.com/latest/prototypes/ModulePrototype.html>
- Effects: <https://lua-api.factorio.com/latest/types/Effect.html>
- Quality prototypes: <https://lua-api.factorio.com/latest/prototypes/QualityPrototype.html>
- Prototype data lifecycle: <https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html>
