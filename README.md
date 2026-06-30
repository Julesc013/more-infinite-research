# More Infinite Research

Trickle down economics bring productivity gains to all industries.

More Infinite Research adds configurable infinite productivity and bonus researches for intermediate items, logistics chains, combat bonuses, player bonuses, and Space Age gaps that vanilla Factorio does not cover.

Version `2.0.0` targets Factorio `2.1` and requires:

- `base >= 2.1.8`
- optional `elevated-rails >= 2.1.8`
- optional `recycler >= 2.1.8`
- optional `quality >= 2.1.8`
- optional `space-age >= 2.1.8`

The mod is built around graceful compatibility: it discovers recipes, science packs, labs, and optional prototypes from the active mod set, generates technologies late in `data-final-fixes.lua`, and skips unsafe or unavailable streams instead of requiring compatibility mods on the mod portal page.

## Quick Summary

- Adds infinite recipe-productivity researches for many intermediate, logistics, combat, infrastructure, science-pack, and Space Age production chains.
- Adds direct-effect infinite researches for cargo landing logistics, weapon shooting speed, character bonuses, inventory, trash slots, and worker robot battery.
- Extends selected vanilla finite technology chains into infinite continuations.
- Discovers science packs from active lab inputs, not from the old `tool` prototype type.
- Validates generated research ingredients against real labs so technologies stay researchable.
- Supports Factorio 2.1 recipe `categories` as well as legacy single `category`.
- Keeps official DLC mods optional and guards DLC-shaped research behind concrete prototype checks.
- Keeps third-party compatibility-mod dependencies out of `info.json`.
- Preserves existing generated prototype IDs for v2.0.0. No migration is required.

Recipe productivity researches are infinite, but Factorio's recipe productivity cap still applies. Additional levels can eventually have no practical effect after a recipe reaches its cap.

## Installation

Install the mod through the Factorio mod portal or place the release zip in your Factorio mods directory.

The packaged release archive is:

```text
dist/more-infinite-research_2.0.0.zip
```

## How Generation Works

More Infinite Research generates prototypes in `data-final-fixes.lua`:

1. Generated stream technology creation.
2. Known competing recipe-productivity cleanup based on actual generated MIR effects.
3. Known competing base-extension cleanup when MIR's matching base extension is enabled.
4. Base technology infinite extensions.
5. Optional vanilla weapon shooting speed adjustment.
6. Max-level enforcement.
7. Optional diagnostics report flush.

This gives the mod a late view of recipes, items, labs, science packs, ammo categories, and technologies created by other mods.

No mod can see another mod's later `data-final-fixes.lua` mutations unless load order makes that possible. If a mod creates or mutates relevant recipes after MIR has already scanned, explicit load-order compatibility may still be needed.

## Cost Model

Generated stream technologies use:

```text
base_cost * growth_factor^(L-1)
```

where `L` is the research level.

Shared stream defaults are:

| Field | Default |
| --- | --- |
| Enabled | `true` |
| Base cost | `8000` |
| Growth factor | `2` |
| Max level | `0`, meaning infinite |
| Research time | `60` seconds |

Base-technology extensions use the same formula, but their first generated level starts after the vanilla chain. A setting value of `0` for base cost, growth factor, or research time means "derive this from the vanilla chain" for base extensions.

If a positive base-extension max level is below the first generated continuation level, MIR skips that extension instead of creating an impossible capped technology.

## Science Packs and Labs

Factorio 2.1 changed science packs to ordinary item prototypes. MIR therefore treats labs as the source of truth:

- It reads `data.raw.lab[*].inputs`.
- It resolves each input through generic item prototype lookup.
- It orders known vanilla and Space Age packs first.
- It appends modded lab inputs alphabetically.
- It validates the final ingredient set against real lab input sets.

If no lab accepts the full selected science-pack set, MIR follows `mir-lab-incompatibility-policy`. The default `reduce` mode chooses the largest deterministic lab-compatible subset. The `skip` mode skips the technology instead. If no valid subset exists, it skips the generated technology and logs the reason.

Two startup settings control late-game progression and global science-pack pressure:

- `ips-require-space-gate` is disabled by default. When enabled, generated technologies require the end-game science unlock as a prerequisite, but their science-pack ingredients are not changed.
- `mir-science-pack-ingredient-policy` is `configured` by default. It can instead add the end-game science pack to every generated technology, or add every active lab science pack, including compatible modded science packs.

For the end-game science gate, MIR uses promethium science in Space Age when available. Otherwise it uses space science when available.

## Generated Prototype Names

Generated stream technologies use stable prototype names:

```text
recipe-prod-<stream-key>-1
```

This naming is preserved for v2.0.0 even for non-recipe direct-effect streams to avoid migrations.

Generated base-technology extensions use the vanilla technology chain name and next level:

```text
<vanilla-technology-name>-<next-level>
```

## Research Catalog

### Recipe Productivity Streams

These streams generate `change-recipe-productivity` effects for matching recipes. Unless stated otherwise, they use the shared cost defaults, are enabled by default, and match visible non-hidden, non-recycling recipes that output the listed items.

| Stream key | Player-facing research | Targets | Per-level productivity | Notes |
| --- | --- | --- | --- | --- |
| `research_copper` | Copper plate productivity | `copper-plate` | `+10%` | Excludes hidden and recycling recipes. |
| `research_iron` | Iron plate productivity | `iron-plate` | `+10%` | Excludes hidden and recycling recipes. |
| `research_gears` | Iron gear wheel productivity | `iron-gear-wheel` | `+10%` | Excludes recipes with scrap ingredients. |
| `research_iron_sticks` | Iron stick productivity | `iron-stick` | `+10%` | Excludes recipes with scrap ingredients. |
| `research_copper_cable` | Copper cable productivity | `copper-cable` | `+10%` | Excludes recipes with scrap ingredients. |
| `research_electronic_circuit` | Electronic circuit productivity | `electronic-circuit` | `+10%` | Adds electromagnetic science when available; excludes scrap inputs. |
| `research_advanced_circuit` | Advanced circuit productivity | `advanced-circuit` | `+10%` | Adds electromagnetic science when available; excludes scrap inputs. |
| `research_processing_unit` | Processing unit productivity | `processing-unit` | `+10%` | Generates when matching visible recipes exist, including without Space Age. |
| `research_plastic` | Plastic productivity | `plastic-bar` | `+10%` | Adds agricultural science when available. |
| `research_sulfur` | Sulfur productivity | `sulfur` | `+10%` | Adds metallurgic science when available; excludes asteroid ingredients. |
| `research_batteries` | Battery productivity | `battery` | `+10%` | Adds electromagnetic science when available; excludes scrap inputs. |
| `research_explosives` | Explosives productivity | `explosives`, `bio-explosives` | `+10%` | Adds metallurgic science when available. |
| `research_engine` | Engine unit productivity | `engine-unit` | `+10%` | Adds metallurgic science when available. |
| `research_electric_engine` | Electric engine unit productivity | `electric-engine-unit` | `+10%` | Adds electromagnetic science when available. |
| `research_flying_robot_frame` | Flying robot frame productivity | `flying-robot-frame` | `+10%` | Adds electromagnetic science when available. |
| `research_low_density_structure` | Low density structure productivity | `low-density-structure` | `+10%` | Adds metallurgic science when available. |
| `research_rocket_fuel` | Rocket fuel productivity | `rocket-fuel` | `+10%` | Adds agricultural science when available. |
| `research_tungsten` | Tungsten productivity | `tungsten-plate`, `tungsten-carbide` | `+10%` | Adds metallurgic science when available. |
| `research_lithium` | Lithium productivity | `lithium-plate` | `+10%` | Adds cryogenic science when available. |
| `research_holmium` | Holmium productivity | `holmium-plate` | `+10%` | Generates when matching visible recipes exist; adds electromagnetic science when available. |
| `research_supercapacitor` | Supercapacitor productivity | `supercapacitor` | `+10%` | Generates when matching visible recipes exist; adds electromagnetic science when available. |
| `research_superconductor` | Superconductor productivity | `superconductor` | `+10%` | Generates when matching visible recipes exist; adds electromagnetic science when available. |
| `research_quantum_processor` | Quantum processor productivity | `quantum-processor` | `+10%` | Generates when matching visible recipes exist; adds cryogenic science when available. |
| `research_carbon_fiber` | Carbon fiber productivity | `carbon-fiber` | `+10%` | Adds agricultural science when available. |
| `research_bioflux` | Bioflux productivity | `bioflux` | `+10%` | Generates when matching visible recipes exist; adds agricultural science when available. |
| `research_breeding` | Breeding productivity | `raw-fish`, `biter-egg`, `pentapod-egg`; recipe names matching cultivation, culture, or breeding | `+10%` | Generates when matching visible recipes exist. Category-only biochamber matching is intentionally avoided. |
| `research_grenades` | Grenade productivity | `grenade`; `cluster-grenade` | `+10%`; `+5%` | Adds military and space science when available. |
| `research_walls` | Wall productivity | `stone-wall`; `gate` | `+10%`; `+5%` | Adds military and space science when available. |
| `research_stone_products` | Stone product productivity | `stone`, `landfill`; `foundation` and artificial soil patterns | `+10%`; `+5%` | Adds metallurgic and space science when available; excludes scrap inputs. |
| `research_rails` | Rail productivity | `rail` | `+10%` | Rail matching is strict so rail-like unrelated outputs are not caught. |
| `research_concrete` | Concrete productivity | `stone-brick`; concrete/hazard concrete; refined concrete/refined hazard concrete | `+10%`; `+5%`; `+2%` | Adds space science when available; excludes scrap inputs. |
| `research_furnace` | Furnace productivity | stone furnace; steel furnace; electric furnace; foundry | `+20%`; `+10%`; `+5%`; `+2%` | Adds metallurgic science when available. |
| `research_mining_drill` | Mining drill productivity | burner mining drill; electric mining drill; big mining drill | `+20%`; `+10%`; `+5%` | Adds metallurgic science when available. |
| `research_electric_energy` | Electric energy productivity | solar panel/accumulator; Advanced Solar HR advanced, elite, and ultimate tiers | `+10%`; `+5%`; `+2%`; `+1%` | Adds electromagnetic science when available. |
| `research_bullets` | Bullet productivity | firearm magazine/shotgun shell; piercing ammo; uranium ammo; plutonium/tungsten patterns | `+10%`; `+5%`; `+2%`; `+1%` | Adds military and space science when available. |
| `research_heavy_ammo` | Heavy ammunition productivity | cannon shell; explosive cannon shell; uranium shells; artillery, railgun, and modded shell patterns | `+10%`; `+5%`; `+2%`; `+1%` | Adds military, metallurgic, and space science when available. |
| `research_rockets` | Rocket productivity | rocket; explosive rocket; atomic bomb; plutonium bomb patterns | `+10%`; `+5%`; `+2%`; `+1%` | Adds agricultural and military science when available. |
| `research_armor_components` | Armor component productivity | armor/armour plating and plate patterns | `+5%`; `+2%` | Adds military, metallurgic, and space science when available. |
| `research_modules` | Module productivity | tier 1 modules; tier 2 modules; tier 3 modules, including quality modules when present | `+10%`; `+5%`; `+2%` | Adds cryogenic science when available. |
| `research_belts` | Transport belt productivity | yellow, red, blue, turbo, and hyper belt/underground/splitter families | `+10%`; `+5%`; `+2%`; `+1%`; `+0.5%` | Adds space science when available. |
| `research_inserters` | Inserter productivity | basic/burner; fast/long-handed; bulk; stack inserters | `+10%`; `+5%`; `+2%`; `+1%` | Adds space science when available. |
| `research_science_pack_productivity` | Science pack productivity | vanilla and Space Age science packs, plus active modded lab inputs | `+10%` | Uses dynamic lab-input targets. Research time default is `120` seconds. |

### Direct-Effect Streams

These streams generate infinite technologies with direct Factorio technology modifiers.

| Stream key | Research | Effect | Default | Gates and notes |
| --- | --- | --- | --- | --- |
| `research_cargo_bay_unloading_distance` | Cargo bay unloading distance | `max-cargo-bay-unloading-distance` | `+10` tiles per level | Requires Space Age plus the `landing-pad-unloading-bay` item and technology. Uses all active lab science packs. Base cost `100000`, growth `3`. |
| `research_cargo_landing_pad_count` | Cargo landing pad count | `cargo-landing-pad-count` | `+1` landing pad per surface per level | Requires Space Age plus the `cargo-landing-pad` item. Disabled by default. Uses all active lab science packs. Base cost `1000000`, growth `10`. |
| `research_rocket_shooting_speed` | Rocket shooting speed | `gun-speed` for `rocket` ammo category | `+10%` speed per level | Base cost `60`, growth `1.5`. Uses a base-game rocketry icon. |
| `research_cannon_shooting_speed` | Cannon shooting speed | `gun-speed` for `cannon-shell` ammo category | `+10%` speed per level | Base cost `60`, growth `1.5`. Uses the cannon shell item icon. |
| `research_flamethrower_shooting_speed` | Flamethrower shooting speed | `gun-speed` for `flamethrower` | `+10%` speed per level | Base cost `60`, growth `1.5`. |
| `research_electric_shooting_speed` | Electric shooting speed | `gun-speed` for `electric` | `+10%` speed per level | Requires the `tesla-weapons` technology and the `electric` ammo category. Base cost `60`, growth `1.5`. |
| `research_character_mining_speed` | Character mining speed | `character-mining-speed` | `+5%` per level | Uses utility, military, agricultural, and electromagnetic science when available. |
| `research_character_crafting_speed` | Character crafting speed | `character-crafting-speed` | `+5%` per level | Uses utility, military, agricultural, and electromagnetic science when available. |
| `research_character_walking_speed` | Character walking speed | `character-running-speed` | `+5%` per level | Uses utility, military, agricultural, and electromagnetic science when available. |
| `research_character_reach` | Character reach bonus | reach, build distance, resource reach, and item drop distance | `+10` each per level | Disabled by default. Uses a base-game-safe icon and available late-game science packs. |
| `research_character_trash_slots` | Character logistic trash slots | `character-logistic-trash-slots` | `+1` slot per level | Growth factor default `1.10`. |
| `research_inventory_capacity` | Character inventory slots | `character-inventory-slots-bonus` | `+1` slot per level | Disabled by default. Growth factor default `1.10`. |
| `research_robot_battery` | Worker robot battery | `worker-robot-battery` | `+10%` per level | Growth factor default `1.2`. |

### Vanilla Base-Technology Extensions

These extend selected finite vanilla chains into infinite continuations.

| Base technology | Enabled by default | Base cost | Growth | Time | Science behavior | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `braking-force` | Yes | `115` | `1.333333333333` | `60` | Inherit vanilla chain and add space science when available. | Copies vanilla braking effects. |
| `research-speed` | Yes | `60` | `1.5` | `120` | Inherit vanilla chain and add all active lab science packs. | Extends lab research speed. |
| `worker-robots-storage` | Yes | `200` | `1.5` | `60` | Inherit vanilla chain and add electromagnetic science when available. | Skips if an equivalent infinite extension already exists. |
| `inserter-capacity-bonus` | No | `200` | `3.333333333333` | `60` | Inherit vanilla chain and add agricultural science when available. | Uses `+2` non-bulk and `+4` bulk/stack increments by default. |
| `weapon-shooting-speed` | Yes | `60` | `1.5` | `120` | Inherit vanilla chain and add military and space science when available. | Vanilla rocket/cannon-shell bonuses can be removed when MIR owns them. |
| `laser-shooting-speed` | Yes | `60` | `1.5` | `120` | Inherit vanilla chain and add military and space science when available. | Copies vanilla laser speed effects. |

## Startup Settings

All settings are startup settings.

### Global Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `ips-require-space-gate` | bool | `false` | Adds the end-game science unlock as a prerequisite without changing science-pack ingredients. Uses promethium science in Space Age when available, otherwise space science. |
| `mir-science-pack-ingredient-policy` | string | `configured` | Controls extra science packs added to every generated technology. Allowed values: `configured`, `end-game`, `all`. |
| `mir-prefer-this-mod-for-competing-techs` | bool | `true` | Lets MIR remove selected competing infinite technologies when MIR has generated or will generate matching replacement behavior. Disable to keep competing technologies from other mods. |
| `mir-adjust-vanilla-weapon-speed-techs` | string | `off` | Controls whether MIR removes rocket and cannon-shell speed bonuses from vanilla weapon shooting speed technologies. Allowed values: `off`, `only-when-dedicated-tech-enabled`, `always`. |
| `mir-debug-generation-report` | bool | `false` | Writes structured generated/skipped rows to the Factorio log, including science packs, prerequisites, effect counts, lab compatibility, and icon source. |
| `mir-debug-recipe-matches` | bool | `false` | Writes matched recipe names for each generated productivity stream. Useful for mod compatibility reports, but noisy in large mod packs. |
| `mir-lab-incompatibility-policy` | string | `reduce` | Controls incompatible science-pack selections. `reduce` uses the largest lab-compatible subset; `skip` skips the technology. |

### Per-Stream Settings

Every generated stream receives:

| Setting pattern | Type | Default source | Meaning |
| --- | --- | --- | --- |
| `ips-enable-<stream-key>` | bool | stream/defaults/shared | Enables or disables the stream. |
| `ips-cost-base-<stream-key>` | int, min `1` | stream/defaults/shared | First-level research unit base cost. |
| `ips-cost-growth-<stream-key>` | double, min `1` | stream/defaults/shared | Multiplier between levels. `1` means flat cost. |
| `ips-max-level-<stream-key>` | int, min `0` | stream/defaults/shared | `0` means infinite; positive values cap the stream. |
| `ips-research-time-<stream-key>` | int, min `0` | stream/defaults/shared | Seconds per research unit. `0` uses the configured default for that stream. |

Per-stream default exceptions:

| Stream | Enabled | Base cost | Growth | Time | Max |
| --- | --- | --- | --- | --- | --- |
| Shared stream default | Yes | `8000` | `2` | `60` | Infinite |
| `research_inventory_capacity` | No | shared | `1.10` | shared | Infinite |
| `research_character_trash_slots` | Yes | shared | `1.10` | shared | Infinite |
| `research_robot_battery` | Yes | shared | `1.2` | shared | Infinite |
| `research_cargo_bay_unloading_distance` | Yes | `100000` | `3` | `60` | Infinite |
| `research_cargo_landing_pad_count` | No | `1000000` | `10` | `60` | Infinite |
| `research_science_pack_productivity` | Yes | shared | shared | `120` | Infinite |
| `research_character_reach` | No | shared | shared | shared | Infinite |
| `research_rocket_shooting_speed` | Yes | `60` | `1.5` | shared | Infinite |
| `research_cannon_shooting_speed` | Yes | `60` | `1.5` | shared | Infinite |
| `research_flamethrower_shooting_speed` | Yes | `60` | `1.5` | shared | Infinite |
| `research_electric_shooting_speed` | Yes | `60` | `1.5` | shared | Infinite |

### Base-Extension Settings

Every base extension receives:

| Setting pattern | Type | Meaning |
| --- | --- | --- |
| `mir-enable-<technology>` | bool | Enables or disables the infinite continuation. |
| `mir-cost-base-<technology>` | int, min `0` | `0` derives the level 1 base term from the vanilla chain; positive values override it. |
| `mir-cost-growth-<technology>` | double, min `0` | `0` derives growth from the vanilla chain; positive values override it. |
| `mir-max-level-<technology>` | int, min `0` | `0` means infinite; positive values cap the generated continuation. |
| `mir-research-time-<technology>` | int, min `0` | `0` reuses vanilla research time; positive values override seconds per unit. |

## Compatibility Specification

### General Compatibility Model

MIR tries to support unknown mods without declaring them as dependencies:

- It generates in `data-final-fixes.lua`.
- It scans actual visible prototypes.
- It uses optional prototype gates instead of hard dependencies.
- It validates lab compatibility.
- It skips unavailable streams.
- It keeps known integration cleanup opportunistic.

This keeps the mod page clean and avoids requiring optional compatibility mods to load MIR.

### Known Opportunistic Integrations

These are handled when their prototypes are visible:

| Mod | Integration |
| --- | --- |
| Advanced Solar HR (`Advanced-Electric-Revamped-v16`) | Advanced, elite, and ultimate solar/accumulator recipes are covered by electric energy productivity tiers. |
| Better Robots Extended (`Better_Robots_Extended`) | Competing worker robot storage infinite research is removed when MIR preference is enabled and MIR's `worker-robots-storage` base extension is enabled. |
| OCs Ammo and Armor (`OCs_ammo_casting`) | Covered ammunition, explosive, and armor component outputs are picked up by output and pattern matching. |
| OCs Stone Casting (`OCs_stone_casting`) | Covered stone, brick, wall, concrete, landfill, foundation, rail, gate, and furnace outputs are picked up by output matching. |
| Fluid Quality Imprinting (`fluid-quality-imprinting`) | Covered plate and intermediate outputs are picked up when the recipes output standard items. |
| Plates n Circuit Productivity (`plates-n-circuit-productivity`) | Selected competing infinite productivity technologies are removed only after MIR has generated replacement recipe effects. |
| Castra and PlanetLib-style science packs | Custom science packs can be discovered as lab inputs and receive science-pack productivity when their recipes are visible. |

Generic competing recipe-productivity cleanup is intentionally limited to known infinite technologies whose recipe-productivity effects are all covered by generated MIR effects. Finite upgrade chains from other mods are not removed by the generic cleanup path.

### Known Limits

- MIR cannot see recipes or labs mutated by another mod later in `data-final-fixes.lua` unless load order puts MIR after that mod.
- Lab-compatible reduction prevents unresearchable technologies, but it cannot infer every overhaul's intended progression.
- Broad support for unknown overhaul mods is opportunistic, not a guarantee.
- Recipe productivity remains capped by Factorio's recipe productivity limit.
- Generated stream prototype IDs were intentionally kept stable for v2.0.0.

## Developer Specification

### Main Files

| File | Purpose |
| --- | --- |
| `data.lua` | Loads stable shared config and utility facades only. |
| `data-updates.lua` | Reserved for future pre-final compatibility hooks. |
| `data-final-fixes.lua` | Runs generation, cleanup, extensions, adjustments, max-level control, and diagnostics. |
| `defaults.lua` | Shared stream defaults, per-stream overrides, and base-extension defaults. |
| `settings.lua` | Startup settings generated from streams and base-extension defaults. |
| `prototypes/config.lua` | Assembles shared config and stream table. |
| `prototypes/tech-gen.lua` | Generates stream technologies. |
| `prototypes/base-tech-extensions.lua` | Extends finite vanilla technology chains. |
| `prototypes/weapon-speed-adjustments.lua` | Optionally removes vanilla rocket/cannon-shell speed bonuses. |
| `prototypes/max-level-control.lua` | Applies stream max levels after generation. |
| `prototypes/diagnostics.lua` | Structured generation report logging. |
| `prototypes/streams/productivity.lua` | Recipe-productivity stream definitions. |
| `prototypes/streams/direct-effects.lua` | Direct-effect stream definitions. |
| `prototypes/lib/science-packs.lua` | Lab input discovery, science-pack ordering, lab validation, prerequisite lookup. |
| `prototypes/lib/recipe-matching.lua` | Recipe output matching, pattern matching, category filters, hidden/recycling skips. |
| `prototypes/lib/technology-icons.lua` | Icon resolution and constant overlay construction. |
| `prototypes/lib/table-utils.lua` | Small shared table helpers such as deterministic sorted keys. |
| `prototypes/lib/technology-cleanup.lua` | Removes technologies and cleans prerequisite references from remaining technologies. |
| `prototypes/compat/profiles.lua` | Mod-specific stream patch scaffolding. |
| `prototypes/compat/competing-productivity.lua` | Known competing recipe-productivity cleanup. |
| `prototypes/compat/competing-base-extensions.lua` | Known competing base-extension cleanup. |

### Stream Schema

Productivity and direct-effect streams are Lua tables keyed by stream ID. Common fields include:

| Field | Meaning |
| --- | --- |
| `required_mods` | Skips the stream unless all listed mods are active. |
| `items` | Exact output item names to match. |
| `item_patterns` | Lua patterns for output item names. |
| `groups` | Tiered recipe-productivity buckets with their own `change`, `items`, and patterns. |
| `change` | Per-level recipe productivity amount for a bucket. |
| `extra_outputs` | Additional output names accepted by recipe matching. |
| `recipe_patterns` | Lua patterns for recipe names. |
| `exclude_recipe_patterns` | Lua patterns for recipe names to skip. |
| `exclude_ingredient_patterns` | Lua patterns for ingredient names to skip. |
| `include_hidden` | Allows hidden recipes when true. |
| `include_recycling` | Allows recycling recipes when true. |
| `mode` | Match mode, including category/name-pattern support. |
| `match` | Match filters such as `categories` and `name_patterns`. |
| `direct_effects` | Technology effects for non-recipe infinite research. |
| `science_packs` | Explicit science-pack list, `"all"`, or omitted for default selection. |
| `dynamic_items_from_lab_inputs` | Appends active lab inputs to the first recipe-productivity group. Used by science-pack productivity. |
| `required_items` | Skips the stream unless all items exist. |
| `required_technologies` | Skips the stream unless all technologies exist and appends them as prerequisites. |
| `required_ammo_categories` | Skips direct effects unless ammo categories exist. |
| `icon`, `icon_size`, `icon_tech`, `icon_item`, `overlay` | Technology icon resolution hints. |
| `localised_name`, `localised_description`, `description_locale_key` | Locale overrides. |

### Compatibility Profiles

`prototypes/compat/profiles.lua` supports append-style fields so future mod profiles can extend base stream definitions without replacing arrays:

- `append_items`
- `append_item_patterns`
- `append_recipe_patterns`
- `append_exclude_recipe_patterns`
- `append_exclude_ingredient_patterns`
- `append_groups`

Direct assignment remains available for intentional overrides.

### Diagnostics

Enable `mir-debug-generation-report` to log rows like:

```text
[more-infinite-research] report kind=stream key=research_science_pack_productivity status=generated reason=recipe_productivity science=... prerequisites=... effects=13 lab_status=reduced icon=tech:research-productivity
```

Use diagnostics when reporting compatibility issues. It tells whether a stream generated, skipped, reduced science packs, or found no matching recipes.

Enable `mir-debug-recipe-matches` to log matched recipe rows like:

```text
[more-infinite-research] matches key=research_belts change=0.01 recipes=turbo-transport-belt,turbo-underground-belt,turbo-splitter
```

When either diagnostics setting is enabled, MIR also reports duplicate recipe matches across streams as warnings in the log. These reports do not block generation; they are for compatibility triage.

## Validation and Release Workflow

Static validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Runtime fixture validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Build the package:

```powershell
.\scripts\Build-MIRPackage.ps1
```

The validation script checks:

- `info.json` parses.
- Release metadata avoids compatibility-mod dependencies.
- Docs match the opportunistic compatibility policy.
- No old `data.raw.tool` science-pack authority remains.
- Generated icons do not use `icon_mipmaps`.
- Locale files match the English fallback.
- `changelog.txt` uses Factorio's 99-dash changelog section format.
- The committed release zip has the expected root, metadata, required files, and no forbidden artifacts.
- Key packaged source, documentation, and locale files match the repository copy, so stale release zips with correct metadata are rejected.
- `git diff --check` passes.
- Runtime fixture loading reaches save creation when a Factorio binary is supplied.
- Runtime logs contain the expected generation diagnostics.
- The default `reduce` lab incompatibility policy keeps science-pack productivity generated with a custom item-based science pack included.
- The `skip` lab incompatibility policy skips an intentionally incompatible science-pack set.
- Post-MIR assertion fixtures prove both runtime lab-policy outcomes.

## Documentation Map

- `docs/architecture.md`: data-stage flow, utility modules, stream config, compatibility profiles, diagnostics, and validation.
- `docs/compatibility.md`: compatibility model, known integrations, manual test matrix, fixture designs, and release checklist.
- `docs/roadmap.md`: v2.0.0 implementation baseline and longer-term v2.x roadmap.
- `docs/test-results.md`: local release-candidate validation evidence.
- `changelog.txt`: release history and user-facing changes.

## Troubleshooting

If a technology is missing:

1. Enable `mir-debug-generation-report`.
2. Load the save or start a controlled test map.
3. Check `factorio-current.log` for the stream key.
4. Look for `skipped`, `no_matching_recipes`, `missing required item`, `missing required technology`, or `no_lab_compatible_science`.

If a recipe did not receive productivity:

1. Enable `mir-debug-recipe-matches` and inspect the stream's matched recipe list.
2. Confirm the recipe outputs one of the stream's exact items or matches one of its patterns.
3. Confirm the recipe is not hidden or recycling unless the stream opts in.
4. Confirm the recipe exists before MIR reaches `data-final-fixes.lua`.
5. Confirm another mod did not mutate the recipe after MIR scanned.

If a generated technology is unresearchable:

1. Check that at least one active lab accepts the full ingredient set.
2. Check the diagnostics row for `lab_status=reduced` or `no_lab_compatible_science`.
3. Verify custom science packs are real item prototypes and are present in at least one lab's `inputs`.

## Save Compatibility

No generated prototype IDs were renamed for v2.0.0. No migration is currently required.
