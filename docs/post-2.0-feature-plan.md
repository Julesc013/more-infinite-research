# Post-2.0 Feature Plan

Updated: 2026-07-01

This document records the feature triage from the first public v2.0.0 discussion and turns it into a bounded plan for More Infinite Research after v2.0.0.

The core conclusion is:

> More Infinite Research should stay focused on research-driven scaling, but add a small scripted-tech framework and a few carefully scoped optional prototype/entity unlocks. It should not become a full Gleba overhaul, refrigeration mod, greenhouse mod, or space-platform overhaul.

Release discipline update:

```text
v2.0.5 = quick feedback patch: small/easy fixes, scripted agriculture/spoilage if manual proof passes, docs, validation, package parity.
v2.1.0 = larger feature wave: presets, broader scripted refinements, pump/fluid/logistics/productivity work that passes proof.
v1.9.0 = Factorio 2.0 compatible subset backported from the tested v2.1.0 snapshot.
v2.1.5 = quick feedback patch after v2.1.0.
v1.9.5 = Factorio 2.0 compatible subset backported from the tested v2.1.5 snapshot.
v2.2.0 = next larger feature wave.
v1.9.9 = final planned Factorio 2.0 backport from the latest tested v2.x.x snapshot at the Factorio 2.1 stable cutoff target around the end of March.
```

The scripted technology implementation exists in `dev` as a `v2.0.5` ship candidate. Public release claims should be made only for the specific behaviors proven by the manual save matrix. Anything that fails proof moves to `v2.1.0`.

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

## Hard Feature Gate

A feature belongs in More Infinite Research only if at least one of these is true:

1. It is a native Factorio technology modifier.
2. It is generated recipe productivity.
3. It is a bounded, event-driven scripted research effect.
4. It is a small optional unlock that directly supports megabase scaling and does not introduce a new gameplay loop.

Otherwise, classify it as `Document only`, `Companion mod`, or `Reject for now`.

The mod should not become "Everything Infinite and Also Every Cool New Building." It should become the research-sink framework that other late-game scaling ideas can plug into.

## Performance Policy

MIR should document and follow this policy:

```text
More Infinite Research avoids per-tick scanning.
Scripted technologies are event-based where possible.
Experimental features that require active scanning are disabled by default or moved to companion mods.
```

The implementation plan must identify every runtime event handler and prove it does not scan:

- all inventories;
- all belts;
- all containers;
- all item stacks;
- all surfaces per tick;
- all entities per tick.

Any feature requiring this kind of broad scan is not eligible for a normal enabled-by-default MIR release.

Feature descriptions should label implementation risk:

- Native.
- Recipe productivity.
- Scripted event-only.
- Prototype/global.
- Sandbox.
- Experimental.
- May affect existing builds.

This matters most for spoilage. Slower spoilage can help megabases, but it can also break factories that intentionally consume spoilage or depend on spoilage timing.

## Release Candidate Ladder

Use these buckets for every idea from the thread. Avoid "maybe" unless it is attached to a concrete spike.

| Bucket | Meaning | Release rule |
| --- | --- | --- |
| Ship | Implement now | API path known, bounded, testable, and in scope. |
| Spike | Investigate with a throwaway test mod or save | API or balance is uncertain. |
| Document only | Capture for future discussion | Useful idea, wrong release. |
| Companion mod | Separate gameplay loop or content expansion | Not MIR core. |
| Reject for now | Too hacky, UPS-heavy, or scope-breaking | Do not revisit without new API support or a specific proof. |

## Priority Roadmap

### P0: Architecture And Settings

These should come before or alongside new content.

| Feature | Add? | Notes |
| --- | ---: | --- |
| Scripted-tech framework | Started in `dev`; v2.0.5 ship candidate | Required for spoilage/growth and future non-native effects. |
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

### P1: v2.0.5 Quick Agriculture And Preservation

Ship:

- Scripted-tech framework.
- Spoilage preservation if manual proof passes.
- Agricultural growth speed for newly planted tower crops if manual proof passes.
- Electric Shooting Speed vanilla/no-Space-Age icon and description fix plus `tesla` ammo-category correction.
- Flamethrower, electric, and Tesla shooting-speed locale coverage.
- Hidden optional Quality load ordering for quality module productivity.
- Omega Drill style mining drill productivity matching.
- Duplicate recipe-productivity skipping so vanilla Space Age productivity techs stay authoritative.
- Better feature descriptions and setting labels.
- Compatibility diagnostics for scripted/global effects.
- Documentation of global/per-force behavior, caps, and removal behavior.

Spike only:

- Existing agricultural plant rescale.
- Agricultural yield, disabled by default.
- Thruster fuel and oxidizer productivity if validation is clean and the scope stays small.
- Oil/fluid recipe productivity.
- Quality module odds.
- Roboport range.
- High-throughput pump prototype feasibility.

Document only, defer, or split:

- Refrigeration.
- Greenhouses.
- Super-bacteria.
- Thruster variants.
- Biter egg chaos.
- Full fluid logistics expansion.

This release should be treated as:

```text
v2.0.5 theme:
Quick feedback patch for easy, bounded, validated improvements.
```

### P2: v2.1.0 Larger Feature Wave

Ship:

- Settings presets.
- High-throughput pump, optional.
- Pipeline extent startup setting, disabled by default.
- Fluid train unloading notes/docs.
- Thruster fuel/oxidizer productivity coverage if recipe-productivity tests pass in a later v2.1.x spike.
- Existing agricultural plant rescale if bounded and deduplicated.
- Duplicate native modifier detection.

Maybe ship:

- "Der Pump" as a large late-game pump variant if it does not dilute MIR's identity.

### P3: v2.1.5 Quick Feedback Patch

Ship:

- Bug fixes and compatibility feedback from v2.1.0.
- Engine/electric engine productivity verification.
- Oil processing productivity test result.
- Biochamber recipe productivity support where valid.
- Modded recipe diagnostics.
- Maraxis and Krastorio 2 Spaced Out compatibility testing when those targets are available for the active Factorio line.

### P4: v2.2.0 Or Companion Mods

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
| Scripted-tech framework | Started | `control/scripted-techs.lua` | P0/P1 |
| Duplicate-effect detection | Yes | Data-stage effect overlap scan | P0 |
| Maraxis compatibility | Yes | Detect duplicate cargo techs | P0/P1 |
| K2 Spaced Out compatibility | Yes | Test matrix | P0/P1 |
| Factorio 2.0 backport | Yes, gated | Separate branch/release | P0 |
| Spoilage preservation | Started | `spoil_time_modifier` | P1 |
| Agricultural growth speed | Started | `on_tower_planted_seed` plus `tick_grown` | P1 |
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

## Feature Ownership Table

Use this table as the product boundary when converting feedback into work.

| User idea | MIR core | MIR optional | Companion mod | Reject for now |
| --- | ---: | ---: | ---: | ---: |
| Spoilage preservation | Yes |  |  |  |
| Agricultural growth speed | Yes |  |  |  |
| Agricultural yield / fruit yield |  | Spike |  |  |
| Settings presets | Yes |  |  |  |
| Diagnostics for scripted/global effects | Yes |  |  |  |
| Engine/electric-engine productivity verification | Yes |  |  |  |
| Thruster fuel/oxidizer productivity |  | Spike |  |  |
| Oil processing productivity |  | Spike |  |  |
| High-throughput pump / Der Pump |  | Yes | Maybe |  |
| Pipeline extent setting |  | Yes | Maybe |  |
| Quality module odds |  | Spike | Maybe |  |
| Innate assembler productivity |  | Spike | Maybe |  |
| Robot battery/carrying capacity | Yes |  |  |  |
| Roboport range |  | Spike | Maybe |  |
| True thruster thrust research |  |  | Maybe | Likely |
| Efficient/high-thrust thruster entities |  |  | Yes |  |
| Refrigeration / CryoPants / cold chain |  |  | Yes |  |
| Greenhouse anywhere / off-world farming |  |  | Yes |  |
| Super-bacteria ores |  |  | Yes |  |
| Foundry/EM plant engine recipes |  |  | Yes |  |
| Biter egg production chaos |  |  | Maybe | Likely |

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

`control.lua` was introduced in the first scripted runtime implementation slice on `dev`. The public release plan treats it as a v2.0.5 ship candidate, with each claimed behavior gated by manual save validation. Keep `docs/architecture.md`, package validation, and existing-save validation aligned as the scripted manager grows.

## Scripted Feature Lifecycle Requirements

Every scripted technology must specify:

- technology name strategy;
- visible `nothing` effect text;
- events used;
- storage keys;
- `on_init` behavior;
- `on_configuration_changed` behavior;
- `on_research_finished` behavior;
- `on_research_reversed` behavior;
- `on_technology_effects_reset` behavior;
- how disabling the setting behaves;
- how multiple forces behave;
- how other mods changing the same global state are handled;
- why no per-tick broad scan is required.

Initial lifecycle table:

| Feature | State touched | Events | Disable/reversal behavior | Other-mod interaction |
| --- | --- | --- | --- | --- |
| Spoilage preservation | `storage.mir.spoilage.baseline`, applied multiplier, per-force levels if needed | Init, configuration changed, research finished/reversed, technology effects reset | Recompute from baseline; disabled setting restores or stops applying MIR multiplier | Must not blindly overwrite unrelated global `spoil_time_modifier` changes; document baseline limitations. |
| Agricultural growth speed | Per-force effective multiplier; optional rescale bookkeeping | Init, configuration changed, tower planted seed, research finished/reversed, technology effects reset | New plants use current multiplier; bounded rescale only if proved safe | Must not mutate non-agricultural plants or scan all surfaces per tick. |
| Agricultural yield | Per-force effective yield multiplier if spiked | Tower mined plant, research finished/reversed | Disabled by default until balance/UPS proof exists | Must avoid duplicating results from other harvest-changing mods unless explicitly compatible. |

For scripted global effects, prefer recomputation over incremental mutation. The code should be able to rebuild applied values after load, configuration change, and research reversal without depending on event history.

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

Recent request: "quality module enrichment" where each research level adds about `+0.1%`, `+0.2%`, and `+0.25%` quality chance to quality module tiers 1/2/3, doubling vanilla modules around level 10.

Better options:

| Option | Fit |
| --- | --- |
| Generate finite higher-tier quality modules | Good companion/addon feature |
| Startup setting to globally tune quality odds | Possible, but not research |
| Infinite tech that changes module behavior at runtime | Avoid |
| Infinite tech that unlocks finite module tiers every N levels | Awkward; finite prototypes only |

Do not add this to v2.0.5. Treat it as a v2.1.x spike or later optional Advanced Quality Research add-on unless Factorio adds a native module-effect technology modifier. A prototype-stage startup setting could boost quality module effects, but that would not be research and should not be presented as More Infinite Research core behavior.

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

## Acceptance Criteria For v2.0.5 Scripted Runtime Candidates

### Scripted-Tech Framework

- `control.lua` loads on fresh and existing saves without migration errors.
- Scripted features are registered through one manager instead of scattered handlers.
- Research finish, reversal, technology effects reset, init, and configuration changed all route through the same recomputation path.
- Each scripted feature declares settings, required prototypes/mods, event handlers, and diagnostics.
- No `on_tick` handler is added for v2.0.5 scripted features.

### Spoilage Preservation

- Technology appears only when Space Age spoilage support is available.
- The technology uses a visible `nothing` effect with localized description.
- Research completion, reversal, and configuration changes recompute the effective modifier.
- Existing saves load cleanly from earlier MIR releases to v2.0.5.
- Multiple-force behavior is documented and manually tested.
- The feature can be disabled via startup setting or preset-derived default.
- Disabling the feature restores or stops applying MIR's own multiplier as far as the stored baseline allows.
- Existing spoilable item behavior is tested before release notes make a stronger claim.

### Agricultural Growth Speed

- Technology appears only when agricultural tower planting support is available.
- New tower-planted seeds receive the current researched growth multiplier through event-driven handling.
- Research completion and reversal either safely rescale known tower-owned plants or explicitly document that only future planting is affected.
- Duplicate plant references from multiple towers are deduplicated during any bounded rescale.
- No surface-wide plant scan or per-tick growth scan is used.
- Cap and per-level formula are visible in settings/docs.

### Settings Presets

- Presets map to explicit setting keys and default values.
- `Vanilla-respectful`, `Megabase-balanced`, and `Unlimited sandbox` are documented.
- Advanced toggles still exist for users who do not want presets.
- Preset behavior is stable across fresh install and existing-save configuration changes.

### Diagnostics And Docs

- Scripted/global effects report enabled/skipped/unsupported states in diagnostics.
- Docs distinguish `Ship`, `Spike`, `Document only`, `Companion mod`, and `Reject for now`.
- Changelog separates player-facing features from compatibility notes and experimental caveats.
- Stable generated technology IDs are preserved unless a migration is documented.

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

New v2.0.5 validation should add for the quick scripted candidates:

- Space Age with spoilage preservation enabled.
- Space Age with agricultural growth speed enabled.
- Research-level-change test for spoilage modifier recalculation.
- Research-level-change test for tower-planted growth adjustment.
- Existing-save load with new `control.lua`.
- Disable/remove mod behavior for spoilage baseline restoration.
- Space Age without Quality where Factorio permits it.

New v2.1.0 validation should add for larger features:

- Runtime fixture or manual test for `thruster-fuel` and `thruster-oxidizer` productivity.
- Maraxis or other cargo-pad mods when updated to Factorio 2.1.
- Krastorio 2 Spaced Out or equivalent large overhaul once compatible with the target Factorio version.

Required named test saves/scenarios:

- Fresh Space Age save, no other mods.
- Existing v2.0.0 MIR save upgraded to v2.0.5.
- Save with spoilable items already on belts, in chests, in labs, in rockets, and on platforms.
- Save with multiple player forces.
- Large Gleba farm with thousands of tower-owned plants.
- Save with MIR scripted feature enabled, researched, then disabled.
- Save with Maraxis-like duplicate cargo landing pad technology.
- Save with custom science packs and custom labs.
- Save without Space Age.
- Factorio 2.0 legacy-branch subset save.

## Factorio 2.0 Backport Reality

The first backport target is the finished More Infinite Research v2.1.0 codebase for Factorio `2.1.x`, not v2.0.0 or v2.0.5 reconstructed commit-by-commit. Later backports should repeat the same snapshot-port model.

Backport rule:

```text
legacy should be current MIR code, minus Factorio 2.1-only surface area, with Factorio 2.0 metadata and validation.
```

The planned mapping is:

```text
More Infinite Research v2.1.0 on Factorio 2.1.x -> More Infinite Research v1.9.0 on Factorio 2.0.x
More Infinite Research v2.1.5 on Factorio 2.1.x -> More Infinite Research v1.9.5 on Factorio 2.0.x
Latest tested MIR v2.x.x at the Factorio 2.1 stable cutoff target around the end of March -> final MIR v1.9.9 on Factorio 2.0.x
```

Be careful with the backport promise. The current 2.1 path can use clean agricultural tower events, cargo landing pad APIs, and any new v2.1.0 prototype unlocks. The 2.0 line may not have those APIs.

Do not assume in Factorio 2.0:

- Cargo landing pad modifiers exist.
- Agricultural tower events exist.
- Newer quality prototype fields exist.
- Future v2.1.0 pump, pipeline, or logistics prototype fields exist.

Best backport plan:

```text
2.1 dev/main branch:
- Full current-line feature set after validation.

2.0 legacy branch:
- Merge/snapshot the exact tested current-line source point.
- Keep shared generator, diagnostics, recipe matching, science-pack handling, compatibility cleanup, docs, locale, and validation infrastructure.
- Restore Factorio 2.0 metadata and build as the matching v1.9.x legacy release.
- Remove or guard cargo landing pad count/unloading distance.
- Keep scripted agriculture, pump/pipeline features, and new recipe-productivity streams only when Factorio 2.0 validation proves support.
```

Legacy metadata should be explicit:

```json
{
  "version": "1.9.0",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0",
    "? space-age"
  ]
}
```

Do not carry Factorio `2.1.x` dependency floors into legacy. Validation should fail if legacy direct-effect stream definitions still contain `max-cargo-bay-unloading-distance` or `cargo-landing-pad-count`.

A Factorio 2.0 backport should be a best-compatible subset on `legacy`, not a promise of full feature parity. The success criterion is that the diff from v2.1.0 to legacy is mostly metadata, docs, validation branching, and explicit removal of Factorio 2.1-only technology surfaces.

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
10. Produce a no-code proof for each scripted feature before claiming it in v2.0.5 or carrying it into v2.1.0.
11. Identify exact setting keys and preset-derived defaults.
12. Preserve stable generated technology names/IDs or document a migration.
13. Split the work into reviewable task chunks or GitHub issues before coding.
14. Draft public update wording for Reddit and the mod portal.

## Browser Planning Prompt

Use this prompt when asking a browser-capable planning model to turn the roadmap into an implementation plan. The expected output is a release-gated plan, not code.

````text
You are helping plan the next implementation phase for the Factorio mod More Infinite Research.

Read the repository documentation first. If you cannot access local files directly, ask me to upload or paste these files before planning:
- README.md
- docs/post-2.0-feature-plan.md
- docs/roadmap.md
- docs/architecture.md
- docs/compatibility.md
- docs/test-results.md
- changelog.txt

Primary source of truth:
- docs/post-2.0-feature-plan.md

Repository state:
- Work should be on local branch `dev`.
- Refresh this block before planning:
  - `git rev-parse HEAD`
  - `git status --short --branch`
  - `git rev-list --left-right --count origin/dev...HEAD`
- Baseline roadmap commit when this prompt was added: 6c12075eb7f23562b96178fa6c26dfc41f82ed4a (`docs: capture post-2.0 feature roadmap`).
- Do not assume anything has been pushed unless git status proves it.

Goal:
Create a release-gated implementation plan for the next post-v2.0.0 work, especially v2.0.5 quick-patch completion and v2.1.0 larger feature planning. Do not write code yet.

Hard product boundaries:
- More Infinite Research must remain focused on research-driven scaling.
- Do not turn the main mod into a refrigeration mod, greenhouse mod, Gleba overhaul, space-platform overhaul, fluid overhaul, quality overhaul, or broad content expansion.
- Prefer native Factorio technology modifiers and generated recipe productivity.
- Allow scripted technologies only when event-driven, bounded, reversible, and save-safe.
- Avoid per-tick inventory, belt, lab, container, surface, item-stack, or broad entity scanning.
- Any feature needing active scanning must be classified as `defer`, `disabled-by-default experiment`, or `companion mod`.
- Preserve compatibility-first behavior.
- Avoid optional third-party dependencies unless truly required.
- Preserve stable generated technology names/IDs unless there is a documented migration.
- Factorio 2.1 is the main target.
- Factorio 2.0 backport work is a best-compatible subset on the legacy branch and must not block the current Factorio 2.1 release line.

Feature eligibility rule:
A feature belongs in More Infinite Research only if at least one is true:
1. It uses a native Factorio technology modifier.
2. It is generated recipe productivity.
3. It is a bounded, event-driven scripted research effect.
4. It is a small optional unlock that directly supports megabase scaling and does not introduce a new gameplay loop.
Otherwise classify it as a companion mod or defer it.

Use browser research only for current official Factorio API documentation and official wiki pages when verifying API claims. Cite sources. Do not rely on Reddit, search snippets, or memory for API behavior.

Plan specifically around these candidate ideas:
- Spoilage preservation
- Agricultural growth speed
- Agricultural yield / fruit yield
- High-throughput pump / Der Pump
- Pipeline extent setting
- Thruster fuel/oxidizer productivity
- True thruster thrust or fuel-efficiency research
- Engine/electric-engine productivity
- Oil processing productivity
- Quality module odds research
- Robot battery/carrying capacity
- Roboport range
- Innate assembler productivity
- Refrigeration / CryoPants / cold chain
- Greenhouses / off-world Gleba farming
- Super-bacteria
- Biter egg production chaos
- Settings presets
- Maraxis compatibility
- Krastorio 2 Spaced Out compatibility
- Factorio 2.0 legacy branch compatibility

Produce the following, in order:

1. Executive decision
   - What should v2.0.5 actually ship?
   - What should move to v2.1.0?
   - What should be spiked?
   - What should be deferred?
   - What should become companion mods?

2. Feature classification table
   Columns:
   - Feature
   - Ship/Spike/Defer/Companion/Reject
   - MIR fit reason
   - Implementation type: native modifier / recipe productivity / scripted event / prototype unlock / startup setting / companion content
   - API confidence
   - UPS risk
   - Save-compat risk
   - Mod-compat risk
   - Default enabled?
   - Target release

3. v2.0.5 completion ladder and v2.1.0 implementation ladder
   - Step-by-step order.
   - Each step must leave the mod loadable.
   - Separate infrastructure from content.
   - Identify rollback points.

4. File-by-file change plan
   Include expected changes to:
   - control.lua
   - any new control/ files
   - prototypes/streams/direct-effects.lua
   - prototypes/tech-gen.lua
   - settings files
   - locale files
   - diagnostics files
   - README.md
   - docs/post-2.0-feature-plan.md
   - docs/roadmap.md
   - docs/architecture.md
   - docs/compatibility.md
   - docs/test-results.md
   - changelog.txt

5. Scripted-tech architecture
   For each scripted tech, specify:
   - technology name strategy
   - UI `nothing` effect text
   - events used
   - storage keys
   - init/configuration/research-finished/research-reversed/technology-effects-reset behavior
   - how disabling the setting behaves
   - how multiple forces behave
   - how other mods changing the same global state are handled
   - why no per-tick scan is required

6. Acceptance criteria
   For each v2.0.5 and v2.1.0 feature, define measurable done criteria.

7. Validation and test matrix
   Include:
   - fresh Space Age save
   - existing v2.0.0 MIR save upgraded to v2.0.5 and then v2.1.0 where relevant
   - save with existing spoilable items in belts/chests/labs/rockets/platforms
   - save with many agricultural towers and plants
   - multi-force save
   - feature disabled after being enabled
   - no Space Age
   - custom science packs
   - custom labs
   - Maraxis-like duplicate cargo landing pad tech
   - Krastorio 2 Spaced Out, if available
   - Factorio 2.0 legacy branch subset

8. Open technical questions requiring in-game verification
   Do not answer these by guessing. For each question, specify:
   - minimal test setup
   - expected observation
   - what implementation decision depends on it

9. Performance policy
   - List every event handler.
   - List any scan.
   - State when scans happen.
   - State worst-case expected scan size.
   - Identify any batching needed.

10. Save and mod compatibility risks
    Include migration/reversal behavior and interaction with other mods.

11. Release-note/changelog outline
    Separate:
    - player-facing features
    - compatibility notes
    - experimental caveats
    - known limitations
    - disabled-by-default features

12. Public update plan
    Draft a short Reddit/mod-portal update paragraph explaining:
    - what is coming next;
    - what is being investigated;
    - what is intentionally out of scope;
    - why refrigeration/greenhouses may become separate mods.

Do not write code.
Do not broaden the mod scope.
Do not recommend features that require per-tick broad scanning.
Where API support is uncertain, classify as Spike, not Ship.
````

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
