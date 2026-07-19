# More Infinite Research

[![Factorio Mod Portal downloads](https://img.shields.io/factorio-mod-portal/dt/more-infinite-research?style=flat-square&label=downloads)](https://mods.factorio.com/mod/more-infinite-research) [![Factorio Mod Portal version](https://img.shields.io/factorio-mod-portal/v/more-infinite-research?style=flat-square&label=mod%20version)](https://mods.factorio.com/mod/more-infinite-research) [![Factorio version](https://img.shields.io/factorio-mod-portal/factorio-version/more-infinite-research?style=flat-square&label=Factorio)](https://mods.factorio.com/mod/more-infinite-research) [![Last updated](https://img.shields.io/factorio-mod-portal/last-updated/more-infinite-research?style=flat-square)](https://mods.factorio.com/mod/more-infinite-research) [![Issues](https://img.shields.io/github/issues/Julesc013/more-infinite-research?style=flat-square)](https://github.com/Julesc013/more-infinite-research/issues) [![Validate](https://img.shields.io/github/actions/workflow/status/Julesc013/more-infinite-research/validate.yml?branch=main&style=flat-square&label=validate)](https://github.com/Julesc013/more-infinite-research/actions/workflows/validate.yml)

*Trickle down economics bring productivity gains to all industries.*

More Infinite Research adds **configurable infinite productivity** and **bonus research** for intermediate items, logistics chains, combat bonuses, player bonuses, and Space Age gaps that vanilla Factorio does not cover on supported modern target lines.

**MIR `3.x.x`** targets **Factorio `2.1`** and requires `base >= 2.1.8`.

**MIR `2.x.x`** targets **Factorio `2.0`** starting with **`2.3.0`**.

**MIR `1.x.x`** targets **Factorio `1.1`** and earlier as reduced backports.

The mod is built around **graceful compatibility**: it discovers recipes, science packs, labs, and optional prototypes from the active mod set, validates the candidate research, generates technologies late in **`data-final-fixes.lua`**, and *skips unsafe or unavailable streams* instead of requiring compatibility mods on the mod portal page.

## Quick Summary

- **Recipe productivity:** adds infinite research for intermediate, logistics, combat, infrastructure, science-pack, and Space Age production chains.
- **Fluid-output productivity:** adds process-family recipe productivity for oil processing, oil cracking, lubricant, sulfuric acid, acid neutralization, and Space Age thruster propellant fluids where those recipes exist.
- **Direct-effect bonuses:** adds infinite research for cargo logistics, weapon speed, character bonuses, combined character inventory/trash slots, and worker robot battery.
- **Fluid and prototype tuning:** includes opt-in startup-only pipeline extent, recipe productivity, energy-use, pollution, speed, and quality limit controls.
- **Settings profiles:** exports full MIR startup profiles by default, with optional compact export that omits unchanged defaults.
- **Vanilla continuations:** extends selected finite vanilla technology chains into infinite continuations.
- **Science-pack discovery:** reads active lab inputs, not the old `tool` prototype type.
- **Lab validation:** checks generated research ingredients against real labs so technologies stay researchable.
- **MIR compiler architecture:** keeps active generation under `prototypes/mir/`, with declarative stream data in `prototypes/streams/`.
- **Compiler diagnostics:** indexes typed prototype facts, compiler decisions, lab matrices, loop risks, rule surfaces, and cap estimates for audits.
- **Factorio 2.1 recipes:** supports recipe `categories` as well as legacy single `category`.
- **Optional DLC:** keeps official DLC mods optional and gates DLC-shaped research behind concrete prototype checks.
- **Scripted Space Age scaling:** bounded event-driven spoilage preservation remains opt-in, while agricultural growth speed is enabled as a special Space Age technology for newly planted tower crops; broader existing-save claims still require the named manual save matrix.
- **Clean mod portal metadata:** keeps third-party compatibility-mod dependencies out of `info.json`.
- **Save compatibility:** preserves existing generated prototype IDs across the MIR `3.0.0` architecture move. Scripted runtime storage is namespaced and must be validated before the scripted features are enabled by default or described with measured runtime behavior.

Recipe productivity researches are infinite, and this mod allows you to modify Factorio's recipe productivity cap/limit.

## New Design

**MIR 3** is the compatibility compiler architecture release. It keeps the player-facing generated technology IDs stable while moving active implementation under the MIR compiler namespace, replacing old compatibility helper paths with bounded discovery, policy, report, and emission layers.

It is the release that makes the generation architecture durable:

- active shipped implementation lives under `prototypes/mir/`;
- required Factorio root lifecycle files remain thin wrappers;
- `prototypes/streams/` stays as declarative stream data;
- generated IDs are manifest-backed and stable;
- compatibility behavior is described through narrow claim records and policy overlays;
- only emission/platform code creates or mutates generated technologies;
- diagnostic rows explain skipped, rejected, observed, and emitted behavior;
- package hygiene excludes docs, fixtures, scripts, tests, task ledgers, build outputs, and distribution outputs from the release zip.

## Installation

Install the mod through the **Factorio mod portal** or place the **release zip** in your Factorio mods directory.

Packaged release archives are in `dist/` named:

```text
more-infinite-research_<version>.zip
```

## Branch Policy

The repository has **three permanent branches** on `origin`:

- **`main`**: latest stable release line for **Factorio `2.1`**.
- **`dev`**: experimental and development branch for the **Factorio `2.1` main line**.
- **`legacy`**: backport branch for **Factorio `2.0`** players.

Normal development should target **`dev`** first. Release-ready hotfixes can target **`main`**. Backports that must remain compatible with Factorio `2.0.x` belong on **`legacy`**. Legacy releases are snapshot ports of tested current-line releases with unsupported newer Factorio surfaces removed, not commit-by-commit rebuilds of old development history.

See **`CONTRIBUTING.md`** for pull request expectations, branch routing, and validation commands.

## How it Works

More Infinite Research mutates and generates prototypes in **`data-final-fixes.lua`**:

1. **Startup-only prototype extensions** such as the opt-in pipeline extent multiplier.
2. **Exact-version compatibility schema repairs** for known upstream loader-schema breaks such as ATAN `2.1` recipe fields.
3. **Known competing recipe-productivity preparation** for removable third-party owners that MIR can fully replace.
4. **Generated stream technology creation.**
5. **Known competing recipe-productivity cleanup** after generated MIR effects prove the replacement.
6. **Known competing base-extension cleanup** when MIR's matching base extension is enabled.
7. **Base technology infinite extensions.**
8. **Optional weapon shooting speed overlap adjustment.**
9. **Max-level enforcement.**
10. **Compiler diagnostics and compatibility planner reporting.**
11. **Generated-technology effect safety validation.**
12. **Optional diagnostics report flush.**

This gives the mod a **late view** of recipes, items, labs, science packs, ammo categories, and technologies created by other mods.

*No mod can see another mod's later `data-final-fixes.lua` mutations unless load order makes that possible.* If a mod creates or mutates relevant recipes after MIR has already scanned, explicit load-order compatibility may still be needed.

## Cost Model

Generated stream technologies use:

```text
base_cost * growth_factor^(L-1)
```

where `L` is the research level.

**Shared stream defaults** are:

| Field | Default |
| --- | --- |
| Enabled | `true` |
| Base cost | `8000` |
| Growth factor | `2` |
| Max level | `0` (infinite) |
| Research unit time | `60` seconds |

**Base-technology extensions** use the same formula, but their first generated level starts after the vanilla chain. A setting value of **`0`** for base cost, growth factor, or research unit time means *derive this from the vanilla chain*.

When Space Age or another mod already owns a recognized infinite productivity technology, MIR keeps the same stream settings instead of hiding them. Default values preserve the final external owner exactly; disabling the stream leaves it untouched. Changing either cost base or growth applies both displayed values as one cost model, and changing startup costs preserves the currently researched owner, its level, and fractional progress. Explicit cost changes are rejected for unknown formulas instead of guessing, while safe MIR generation remains the fallback when no eligible owner exists.

If a positive base-extension max level is below the first generated continuation level, MIR **skips that extension** instead of creating an impossible capped technology.

## Science Packs and Labs

Factorio 2.1 changed science packs to ordinary item prototypes. MIR therefore treats **labs as the source of truth**:

- **Lab inputs:** reads `data.raw.lab[*].inputs`.
- **Item lookup:** resolves each input through generic item prototype lookup.
- **Official ordering:** orders known vanilla and Space Age packs first.
- **Modded inputs:** appends modded lab inputs alphabetically.
- **Researchability:** validates the final ingredient set against real lab input sets.

If no lab accepts the full selected science-pack set, MIR follows **`mir-lab-incompatibility-policy`**. The default **`reduce`** mode chooses the largest deterministic lab-compatible subset. The **`skip`** mode skips the technology instead. If no valid subset exists, MIR skips the generated technology and logs the reason.

Two startup settings control late-game progression and global science-pack pressure:

- **`ips-require-space-gate`** is **disabled by default**. When enabled, generated technologies require the end-game science unlock as a prerequisite, but their science-pack ingredients are not changed.
- **Science packs for generated technologies** (`mir-science-pack-ingredient-policy`) is **`configured` by default**. It can instead add fixed late-game packs, infer missing official or modded progression packs from the selected science packs, add every official base and Space Age science pack, or add every active lab science pack including compatible modded science packs. Options are ordered from conservative to broad.

For the end-game science gate, MIR uses **promethium science** in Space Age when available. Otherwise it uses **space science** when available.

## Generated Prototype Names

Generated stream technologies use **stable prototype names**:

```text
recipe-prod-<stream-key>-1
```

This naming was preserved for **v2.0.0** even for non-recipe direct-effect streams to avoid migrations. `v2.0.5` intentionally consolidates the old character logistic trash slot stream into character inventory slots and ships a tested JSON migration for that generated technology ID. `v2.1.0` intentionally splits the old stone-product productivity stream into separate landfill, artificial-soil, and molten-metal streams; the old generated stone-product technology ID migrates to the new landfill productivity technology as the closest successor.

Generated base-technology extensions use the **vanilla technology chain name** and **next level**:

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
| `research_processing_unit` | Processing unit productivity | `processing-unit` | `+10%` | Generates when matching visible recipes exist, including without Space Age. Uses the processing unit unlock technology art when available. In Space Age, covered recipes stay with vanilla `processing-unit-productivity`; additional productivity-allowed family recipes are adopted into that vanilla tech when safe. |
| `research_plastic` | Plastic productivity | `plastic-bar` | `+10%` | Adds agricultural science when available. In Space Age, covered recipes stay with vanilla `plastic-bar-productivity`; additional productivity-allowed family recipes are adopted into that vanilla tech when safe. |
| `research_sulfur` | Sulfur productivity | `sulfur` | `+10%` | Adds metallurgic science when available; excludes asteroid ingredients. |
| `research_batteries` | Battery productivity | `battery` | `+10%` | Adds electromagnetic science when available; excludes scrap inputs. |
| `research_explosives` | Explosives productivity | `explosives`, `bio-explosives` | `+10%` | Adds metallurgic science when available. |
| `research_engine` | Engine unit productivity | `engine-unit` | `+10%` | Adds metallurgic science when available. |
| `research_electric_engine` | Electric engine unit productivity | `electric-engine-unit` | `+10%` | Adds electromagnetic science when available. |
| `research_flying_robot_frame` | Flying robot frame productivity | `flying-robot-frame` | `+10%` | Adds electromagnetic science when available. |
| `research_low_density_structure` | Low density structure productivity | `low-density-structure` | `+10%` | Adds metallurgic science when available. In Space Age, covered recipes stay with vanilla `low-density-structure-productivity`; additional productivity-allowed family recipes are adopted into that vanilla tech when safe. |
| `research_rocket_fuel` | Rocket fuel productivity | `rocket-fuel` | `+10%` | Uses the rocket fuel unlock technology art. Adds agricultural science when available. In Space Age, covered recipes stay with vanilla `rocket-fuel-productivity`; additional productivity-allowed family recipes are adopted into that vanilla tech when safe. |
| `research_thruster_fuel_productivity` | Thruster fuel productivity | Recipes outputting `thruster-fuel`, including Space Age basic and advanced thruster fuel | `+10%` | Requires the `thruster-fuel` fluid. Excludes barrel-emptying recipes. Adds space and agricultural science when available. |
| `research_thruster_oxidizer_productivity` | Thruster oxidizer productivity | Recipes outputting `thruster-oxidizer`, including Space Age basic and advanced thruster oxidizer | `+10%` | Requires the `thruster-oxidizer` fluid. Excludes barrel-emptying recipes. Adds space and agricultural science when available. |
| `research_oil_processing_productivity` | Oil processing productivity | `basic-oil-processing`, `advanced-oil-processing`, `coal-liquefaction`, `simple-coal-liquefaction` | `+10%` | Owns multi-output oil-processing recipes as a single process family so heavy oil, light oil, and petroleum gas are not split into competing owners. Adds cryogenic science when available. |
| `research_oil_cracking_productivity` | Oil cracking productivity | `heavy-oil-cracking`, `light-oil-cracking` | `+10%` | Separate from oil processing because cracking recipes are single conversion steps. Uses the oil processing unlock technology art. Adds agricultural science when available. |
| `research_lubricant_productivity` | Lubricant productivity | Recipes outputting `lubricant`, including Space Age `biolubricant` when present | `+10%` | Requires the `lubricant` fluid and excludes barrel-emptying recipes. Adds electromagnetic science when available. |
| `research_sulfuric_acid_productivity` | Sulfuric acid productivity | Recipes outputting `sulfuric-acid`, plus Space Age `acid-neutralisation` and compatible `acid-neutralization` recipes when present | `+10%` | Requires the `sulfuric-acid` fluid, uses sulfuric acid fluid art, and excludes barrel-emptying recipes. Adds metallurgic science when available. |
| `research_air_scrubbing_clean_filter` | Air Scrubbing clean-filter productivity | Exact `atan-pollution-filter` and `atan-spore-filter` recipes | `+5%` | Uses unlock-derived science and prerequisites. Scrubbing, cleaning, recovery, recycling, and environmental-removal recipes are not targeted. |
| `research_ash_separation` | Ash separation productivity | Exact `atan-ash-seperation` recipe | `+5%` | Uses unlock-derived science and prerequisites. Landfill, stone brick, nutrient, foundation, tile, and recovery-style ash sink recipes are not targeted. |
| `research_tungsten` | Tungsten productivity | `tungsten-plate`, `tungsten-carbide` | `+10%` | Adds metallurgic science when available. |
| `research_lithium` | Lithium productivity | `lithium-plate`; lithium from brine | `+10%`; `+5%` | Adds cryogenic science when available. |
| `research_holmium` | Holmium productivity | `holmium-plate` | `+10%` | Generates when matching visible recipes exist; adds electromagnetic science when available. |
| `research_supercapacitor` | Supercapacitor productivity | `supercapacitor` | `+10%` | Generates when matching visible recipes exist; adds electromagnetic science when available. |
| `research_superconductor` | Superconductor productivity | `superconductor` | `+10%` | Generates when matching visible recipes exist; adds electromagnetic science when available. |
| `research_quantum_processor` | Quantum processor productivity | `quantum-processor` | `+10%` | Generates when matching visible recipes exist; adds cryogenic science when available. |
| `research_carbon` | Carbon productivity | carbonic asteroid crushing, advanced carbonic asteroid crushing, and compatible carbon-output recipes; burnt spoilage; coal synthesis | `+10%`; `+5%`; `+2%` | Generates when matching visible recipes exist; adds space science when available. |
| `research_carbon_fiber` | Carbon fiber productivity | `carbon-fiber` | `+10%` | Adds agricultural science when available. |
| `research_ice` | Ice productivity | oxide asteroid crushing, advanced oxide asteroid crushing, and compatible ice-output recipes | `+10%` | Generates when matching visible recipes exist; adds space science when available. |
| `research_bioflux` | Bioflux productivity | `bioflux` | `+10%` | Generates when matching visible recipes exist; adds agricultural science when available. |
| `research_bacteria_cultivation` | Bacteria cultivation productivity | iron bacteria cultivation; copper bacteria cultivation | `+10%` | Uses bacteria cultivation technology art. Adds agricultural and cryogenic science when available. Excluded from Breeding productivity so it has a dedicated owner. |
| `research_breeding` | Breeding productivity | `raw-fish`, `biter-egg`, `pentapod-egg`; recipe names matching cultivation, culture, or breeding, except dedicated bacteria cultivation recipes | `+10%` | Adds agricultural and cryogenic science when available. Category-only biochamber matching is intentionally avoided. |
| `research_grenades` | Grenade productivity | `grenade`; `cluster-grenade` | `+10%`; `+5%` | Adds military and space science when available. |
| `research_walls` | Wall productivity | `stone-wall`; `gate` | `+10%`; `+5%` | Uses the gate technology art. Adds military and space science when available. |
| `research_landfill` | Landfill productivity | `landfill`; `foundation` | `+10%`; `+5%` | Uses landfill technology art. Adds metallurgic and space science when available; excludes scrap inputs. |
| `research_artificial_soil` | Artificial soil productivity | artificial yumako/jellynut soil and compatible artificial soil patterns; overgrowth yumako/jellynut soil and compatible overgrowth soil patterns | `+10%`; `+5%` | Uses artificial soil technology art. Adds agricultural and space science when available. |
| `research_molten_metals` | Molten metals productivity | molten iron/copper from lava; iron/copper ore melting | `+10%`; `+5%` | Uses foundry technology art. Adds metallurgic science when available; excludes scrap inputs. |
| `research_rails` | Rail productivity | `rail`; Elevated Rails `rail-support`; Elevated Rails `rail-ramp` when present | `+10%`; `+5%`; `+2%` | Rail matching is strict so rail-like unrelated outputs are not caught. Prefers Elevated Rails technology art when available, with the rail item as fallback. |
| `research_concrete` | Concrete productivity | `stone-brick`; concrete/hazard concrete; refined concrete/refined hazard concrete | `+10%`; `+5%`; `+2%` | Adds space science when available; excludes scrap inputs. |
| `research_furnace` | Furnace productivity | stone furnace; steel furnace; electric furnace; foundry | `+20%`; `+10%`; `+5%`; `+2%` | Adds metallurgic science when available. |
| `research_mining_drill` | Mining drill productivity | burner mining drill; electric mining drill; big mining drill; Omega-style and broader modded `*-mining-drill` / `*-drill` outputs | `+20%`; `+10%`; `+5%` | Adds metallurgic science when available. Modded drill outputs fall into the high-tier `+5%` bucket unless matched by an earlier exact tier. |
| `research_electric_energy` | Electric energy productivity | solar panel/accumulator; Advanced Solar HR advanced, elite, and ultimate tiers | `+10%`; `+5%`; `+2%`; `+1%` | Adds electromagnetic science when available. |
| `research_bullets` | Bullet productivity | firearm magazine/shotgun shell; piercing ammo; uranium ammo; plutonium/tungsten patterns | `+10%`; `+5%`; `+2%`; `+1%` | Adds military and space science when available. |
| `research_heavy_ammo` | Cannon shell productivity | cannon shell; explosive cannon shell; uranium shells; artillery shell, railgun ammo, and modded shell/ammo patterns | `+10%`; `+5%`; `+2%`; `+1%` | Adds military, metallurgic, and space science when available. Covers ammo recipes only; artillery turrets, artillery wagons, railgun turrets, and other machines are intentionally left for a separate future systems/productivity decision. |
| `research_rockets` | Rocket productivity | rocket; explosive rocket; atomic bomb; plutonium bomb patterns | `+10%`; `+5%`; `+2%`; `+1%` | Adds agricultural and military science when available. |
| `research_armor_components` | Armor component productivity | armor/armour plating and plate patterns | `+5%`; `+2%` | Adds military, metallurgic, and space science when available. |
| `research_modules` | Module productivity | tier 1 modules; tier 2 modules; tier 3 modules, including quality modules when present | `+10%`; `+5%`; `+2%` | Adds cryogenic science when available. |
| `research_belts` | Transport belt productivity | yellow, red, blue, turbo, and hyper belt/underground/splitter/loader families, including AAI-style loader recipe IDs when visible | `+10%`; `+5%`; `+2%`; `+1%`; `+0.5%` | Adds space science when available. Loader recipes are treated as logistics crafting productivity, not loader behavior or operating-mode changes. |
| `research_inserters` | Inserter productivity | basic/burner; fast/long-handed; bulk; stack inserters | `+10%`; `+5%`; `+2%`; `+1%` | Adds space science when available. |
| `research_science_pack_productivity` | Science pack productivity | vanilla and Space Age science packs, plus active modded lab inputs such as ATAN-style Nuclear Science packs | `+10%` | Recipe productivity for producing science packs. Uses dynamic lab-input targets and unlock-derived prerequisites for modded science-pack recipes. Uses vanilla `research-productivity` art when present and the white space-science technology art as the base-game fallback. Research unit time default is `120` seconds. |

### Direct-Effect And Scripted Streams

These streams generate infinite technologies with direct Factorio technology modifiers or visible scripted-effect placeholders. Scripted effects are handled in `control.lua` and remain event-driven.

Spoilage preservation remains disabled by default. Agricultural growth speed is enabled by default after event-path coverage, but its bounded first slice applies only to newly planted agricultural tower crops. Stronger existing-save, reversal, disabling, and multi-force claims still require the named manual save matrix.

| Stream key | Research | Effect | Default | Gates and notes |
| --- | --- | --- | --- | --- |
| `research_spoilage_preservation` | Spoilage preservation | Scripted global spoil time modifier through a `nothing` technology effect | `+1%` spoil time per completed level, capped by Factorio's global spoil-time range | Disabled by default until manual validation is recorded. Requires Space Age and spoilage; its research cost includes space, agricultural, and cryogenic science. Uses the highest completed level across non-enemy/non-neutral forces. No inventory or item-stack scan. |
| `research_agricultural_growth_speed` | Agricultural growth speed | Scripted `on_tower_planted_seed` adjustment of plant `tick_grown` through a `nothing` technology effect | `+1%` growth speed per completed level, capped at `10x` | Enabled by default as a special Space Age technology. Requires Space Age and agricultural science; its research cost also includes electromagnetic and cryogenic science when available. Applies to newly planted agricultural tower plants in this first slice; existing farms are not globally rescanned. |
| `research_lab_productivity` | Research productivity | `laboratory-productivity` | `+10%` lab research productivity per level | Base-game equivalent of Space Age's native `research-productivity` chain. Generates only when no effect-proven infinite `research-productivity` or `laboratory-productivity-4` lab-productivity owner is present, so existing native lab-productivity owners keep their chain. Uses Military science pack technology art as the base-game icon. |
| `research_cargo_bay_unloading_distance` | Cargo bay unloading distance | `max-cargo-bay-unloading-distance` | `+10` tiles per level | Requires Space Age plus the `landing-pad-unloading-bay` item and technology. Uses the unloading bay unlock technology art. Uses all official base and Space Age science packs, not modded science packs. Base cost `100000`, growth `3`, time `120`. |
| `research_cargo_landing_pad_count` | Cargo landing pad count | `cargo-landing-pad-count` | `+1` landing pad per surface per level | Requires Space Age plus the `cargo-landing-pad` item and `rocket-silo` technology. Disabled by default. Uses Space platform technology art. Uses all official base and Space Age science packs, not modded science packs. Base cost `1000000`, growth `10`, time `240`. |
| `research_rocket_shooting_speed` | Rocket shooting speed | `gun-speed` for `rocket` ammo category | `+10%` speed per level | Base cost `60`, growth `1.5`. Uses a base-game rocketry icon and electromagnetic science when available. |
| `research_cannon_shooting_speed` | Cannon shooting speed | `gun-speed` for `cannon-shell` ammo category | `+10%` speed per level | Base cost `60`, growth `1.5`. Uses the cannon shell item icon and electromagnetic science when available. |
| `research_flamethrower_shooting_speed` | Flamethrower shooting speed | `gun-speed` for `flamethrower` | `+10%` speed per level | Base cost `60`, growth `1.5`. |
| `research_electric_shooting_speed` | Electric shooting speed | `gun-speed` for `electric` and, when Space Age is active, `tesla` | `+10%` speed per level | Uses the Space Age electric-weapons-damage texture when available and falls back to discharge defense in vanilla so it has a valid icon and description without Space Age. The generator filters unavailable ammo categories, so vanilla keeps discharge-defense-style `electric` coverage and Space Age also covers Tesla guns and Tesla turrets through `tesla`. Base cost `60`, growth `1.5`. |
| `research_character_mining_speed` | Character mining speed | `character-mining-speed` | `+5%` per level | Uses utility, military, agricultural, and electromagnetic science when available. |
| `research_character_crafting_speed` | Character crafting speed | `character-crafting-speed` | `+5%` per level | Uses utility, military, agricultural, and electromagnetic science when available. |
| `research_character_walking_speed` | Character walking speed | `character-running-speed` | `+5%` per level | Uses utility, military, agricultural, and electromagnetic science when available. |
| `research_character_reach` | Character reach bonus | reach, build distance, resource reach, and item drop distance | `+10` each per level | Disabled by default. Uses the character mining speed pickaxe icon and available late-game science packs. |
| `research_inventory_capacity` | Character inventory slots | `character-inventory-slots-bonus`; `character-logistic-trash-slots` | `+1` inventory slot and `+1` logistic trash slot per level | Growth factor default `1.10`. |
| `research_robot_battery` | Worker robot battery | `worker-robot-battery` | `+10%` per level | Growth factor default `1.2`. Skips when Better Bot Battery-style `worker-robots-battery-6` exists as an infinite native `worker-robot-battery` owner with its expected value. |

### Vanilla Base-Technology Extensions

These extend selected finite vanilla chains into infinite continuations.

| Base technology | Enabled by default | Base cost | Growth | Time | Science behavior | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `braking-force` | Yes | `115` | `1.333` | `60` | Inherit vanilla chain and add space science when available. | Copies vanilla braking effects. |
| `research-speed` | Yes | `60` | `1.5` | `120` | Inherit vanilla chain and add all active lab science packs. | Extends lab research speed. |
| `worker-robots-storage` | Yes | `200` | `1.5` | `60` | Inherit vanilla chain and add electromagnetic science when available. | Skips if an equivalent infinite extension already exists. |
| `inserter-capacity-bonus` | No | `200` | `3.333` | `60` | Inherit vanilla chain and add agricultural science when available. | Uses `+2` non-bulk and `+4` bulk/stack increments by default. |
| `weapon-shooting-speed` | Yes | `60` | `1.5` | `120` | Inherit vanilla chain and add military and space science when available. | Vanilla rocket/cannon-shell bonuses can be removed when MIR owns them. |
| `laser-shooting-speed` | Yes | `60` | `1.5` | `120` | Inherit vanilla chain and add military and space science when available. | Copies vanilla laser speed effects. |

## Startup Settings

All settings are **startup settings**. Changing them requires a restart and affects all players in multiplayer.

### Settings Guide

Recommended default:

- Leave technology enable checkboxes as shipped.
- Stable generated research lines are enabled.
- Spoilage preservation stays disabled by default; agricultural growth speed is enabled for newly planted tower crops.
- Diagnostics stay disabled unless you are troubleshooting a report.

Conservative setup:

- Generated productivity streams stay enabled where their recipes and labs are valid.
- Disable MIR vanilla-chain continuations you do not want to extend.
- Keep Cargo landing pad count disabled unless you want sandbox-style Space Age logistics.
- Keep Spoilage preservation disabled; disable Agricultural growth speed if you do not want its newly planted crop adjustment.
- Use science pack policy `configured`.

Megabase setup:

- Keep most generated streams enabled.
- Keep max level at `0` for infinite progression.
- Consider **Science packs for generated technologies** values `space-age-progression`, `official-progression`, `mod-progression`, or `all-official` if you want higher-end science sinks without forcing every active modded pack into every technology.
- Use **Lab compatibility for generated technologies** value `reduce` for broad modpack compatibility.

Modpack compatibility setup:

- Start with **Science packs for generated technologies** value `configured`.
- Use **Lab compatibility for generated technologies** value `reduce`.
- Enable `Log generated and skipped technologies` only while troubleshooting.
- Enable `Log recipes matched by productivity technologies` only when reporting missing or duplicate productivity chains.

Debug/reporting setup:

- Enable `Log generated and skipped technologies`, load once, then attach the Factorio log.
- Enable `Log recipes matched by productivity technologies` for recipe-productivity matching issues.
- Enable `Log scripted spoilage and agriculture effects` only for scripted spoilage/agriculture issues.

### Technology Enablement

Each generated stream or base-game continuation has one enable checkbox. That checkbox is the source of truth for both data-stage technology generation and control-stage scripted effects. Future preset work should use an import/export or shareable configuration flow rather than adding another override setting beside every technology.

### What `0` Means

Generated research lines:

- Max level `0` means infinite.
- Research unit time `0` means use MIR's default for that generated technology.
- First-level cost and cost multiplier must be positive.

Vanilla continuations:

- First-level cost `0` means inherit from the vanilla chain when possible.
- Cost multiplier `0` means inherit from the vanilla chain when possible.
- Research unit time `0` means inherit from the vanilla chain when possible.
- Max level `0` means infinite.

`Research unit time` is Factorio's seconds-per-research-unit value. It is not total completion time; total time also depends on research units, labs, lab speed, and modules.

### Global Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `ips-require-space-gate` | bool | `false` | Adds the end-game science unlock as a prerequisite without changing science-pack ingredients. Uses promethium science in Space Age when available, otherwise space science. |
| `mir-science-pack-ingredient-policy` | string | `configured` | Chooses how MIR adds science packs to generated technologies. Options are ordered from conservative to broad: `configured`, `space`, `space-and-promethium`, `space-age-progression`, `official-progression`, `mod-progression`, `all-official`, `all`. |
| `mir-prefer-this-mod-for-competing-techs` | bool | `true` | Lets MIR remove selected competing infinite technologies when MIR has generated or will generate matching replacement behavior. Disable to keep competing technologies from other mods. |
| `mir-adjust-vanilla-weapon-speed-techs` | string | `only-when-dedicated-tech-enabled` | Removes rocket and cannon-shell bonuses from MIR's generated general continuation only when an enabled, reachable infinite technology provides the exact replacement effect. Finite vanilla technologies are never stripped. Existing saved startup choices are not rewritten. Allowed values: `off`, `only-when-dedicated-tech-enabled`, `always`. |
| `mir-pipeline-extent-multiplier` | string/dropdown | `100%` | Strictly opt-in startup-only multiplier for recognized fluid box pipeline extent fields across prototypes, not only pipe entities. At `100%`, MIR does not load the pipeline pass, scan fluid boxes, or change prototypes. Allowed values: `50%`, `75%`, `100%`, `125%`, `150%`, `200%`, `250%`, `300%`, `400%`, `500%`. Non-`100%` values are experimental and can affect machines, tanks, thrusters, and modded prototypes that define fluid boxes. |
| `mir-debug-generation-report` | bool | `false` | Writes structured generated/skipped rows to the Factorio log, including science packs, prerequisites, effect counts, lab compatibility, and icon source. |
| `mir-debug-recipe-matches` | bool | `false` | Writes matched recipe names for each generated productivity stream. Useful for mod compatibility reports, but noisy in large mod packs. |
| `mir-debug-scripted-effects` | bool | `false` | Writes runtime log entries when scripted technologies recompute global or event-driven effects. |
| `mir-lab-incompatibility-policy` | string | `reduce` | Chooses what MIR does when the selected science packs cannot be researched by any active lab. `reduce` uses the largest researchable subset; `skip` skips the technology. |

### Per-Stream Settings

Every generated stream receives:

| Setting pattern | Type | Default source | Meaning |
| --- | --- | --- | --- |
| `ips-enable-<stream-key>` | bool | stream/defaults/shared | Enables or disables generation for the stream. Scripted streams use the same checkbox for their runtime effect. |
| `ips-cost-base-<stream-key>` | int, min `1` | stream/defaults/shared | First-level research unit base cost. |
| `ips-cost-growth-<stream-key>` | double, min `1` | stream/defaults/shared | Multiplier between levels. `1` means flat cost. |
| `ips-max-level-<stream-key>` | int, min `0` | stream/defaults/shared | `0` means infinite; positive values cap the stream. |
| `ips-research-time-<stream-key>` | int, min `0` | stream/defaults/shared | Seconds per research unit. `0` uses the configured default for that stream. |

Per-stream default exceptions:

| Stream | Enabled | Base cost | Growth | Time | Max |
| --- | --- | --- | --- | --- | --- |
| Shared stream default | Yes | `8000` | `2` | `60` | Infinite |
| `research_spoilage_preservation` | No | `50000` | `1.5` | `120` | Infinite |
| `research_agricultural_growth_speed` | No | `40000` | `1.5` | `90` | Infinite |
| `research_inventory_capacity` | Yes | shared | `1.10` | shared | Infinite |
| `research_robot_battery` | Yes | shared | `1.2` | shared | Infinite |
| `research_cargo_bay_unloading_distance` | Yes | `100000` | `3` | `120` | Infinite |
| `research_cargo_landing_pad_count` | No | `1000000` | `10` | `240` | Infinite |
| `research_lab_productivity` | Yes | `1000` | `1.2` | `120` | Infinite |
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
| `mir-research-time-<technology>` | int, min `0` | `0` reuses vanilla research unit time; positive values override seconds per unit. |

## Compatibility Specification

### General Compatibility Model

MIR tries to support unknown mods **without declaring them as dependencies**:

- **Late generation:** generates in `data-final-fixes.lua`.
- **Visible prototypes:** scans actual visible prototypes.
- **Optional gates:** uses prototype gates instead of hard dependencies.
- **Lab safety:** validates lab compatibility.
- **Safe skips:** skips unavailable streams.
- **Opportunistic cleanup:** keeps known integration cleanup opportunistic.

This keeps the mod page clean and avoids requiring optional compatibility mods to load MIR.

### Known Opportunistic Integrations

These are handled when their **prototypes are visible**:

| Mod | Integration |
| --- | --- |
| Advanced Solar HR (`Advanced-Electric-Revamped-v16`) | Advanced, elite, and ultimate solar/accumulator recipes are covered by electric energy productivity tiers. |
| Better Robots Extended (`Better_Robots_Extended`) | Competing worker robot storage infinite research is removed when MIR preference is enabled and MIR's `worker-robots-storage` base extension is enabled. |
| OCs Ammo and Armor (`OCs_ammo_casting`) | Covered ammunition, explosive, and armor component outputs are picked up by output and pattern matching. |
| OCs Stone Casting (`OCs_stone_casting`) | Covered stone, brick, wall, concrete, landfill, foundation, rail, gate, and furnace outputs are picked up by output matching. |
| Fluid Quality Imprinting (`fluid-quality-imprinting`) | Covered plate and intermediate outputs are picked up when the recipes output standard items. |
| Plates n Circuit Productivity (`plates-n-circuit-productivity`) | Selected competing infinite productivity technologies are prepared before MIR generation and removed only after MIR has generated matching replacement recipe effects with the same productivity value and no other blocking owner. |
| Castra and PlanetLib-style science packs | Custom science packs can be discovered as lab inputs and receive science-pack productivity when their recipes are visible. |
| Air Scrubbing (`atan-air-scrubbing`) | Exact clean-filter crafting recipes are covered by Air Scrubbing clean-filter productivity; scrubbing, cleaning, recovery, and environmental-removal recipes are deliberately excluded. |
| ATAN Ash (`atan-ash`) | Exact ash separation is covered by ash separation productivity; landfill, brick, nutrient, foundation, tile, and recovery-style ash sink recipes are deliberately excluded. MIR also applies an exact `atan-ash_2.2.1` Factorio `2.1` loader-schema repair when that version is loaded with MIR. |
| AAI Loaders style loader mods | Recipes outputting AAI-style or tier-named loader items are covered by transport belt productivity when their recipes are visible. |
| Big Mining Drill and Omega Drill style drill mods | Recipes outputting `big-mining-drill`, `omega-drill`, `omega-tau`, or broader modded `*-mining-drill` / `*-drill` items are covered by mining drill productivity. |
| ATAN Nuclear Science style science-pack mods | Lab-input science-pack items with visible recipes are covered by science-pack productivity; non-science buildings such as atom-forge recipes are not included in the science-pack stream. MIR also applies an exact `atan-nuclear-science_0.3.3` Factorio `2.1` loader-schema repair when that version is loaded with MIR. |

Generic competing recipe-productivity cleanup is intentionally limited to **known infinite technologies** whose recipe-productivity effects are all covered by enabled MIR streams and then by generated MIR effects. **Finite upgrade chains** from other mods are not removed by the generic cleanup path.

### Known Limits

- **Late mutations:** MIR cannot see recipes or labs changed later in `data-final-fixes.lua` unless load order puts MIR after that mod.
- **Progression intent:** lab-compatible reduction prevents unresearchable technologies, but it cannot infer every overhaul's intended progression.
- **Unknown overhauls:** broad support is opportunistic, not a guarantee.
- **Productivity cap:** recipe productivity remains capped by Factorio's recipe productivity limit.
- **Vanilla Space Age productivity:** MIR skips recipe-productivity effects already owned by another infinite recipe-productivity technology. For configured vanilla Space Age productivity families, residual productivity-allowed recipes can be adopted into the existing vanilla infinite technology instead of generating a parallel MIR technology.
- **Existing saves:** when configured vanilla productivity-family adoption changes the actual adopted `owner|recipe|change` signature, MIR resets technology effects once so already-researched vanilla family technologies apply the new recipe effects.
- **Stable IDs:** generated stream prototype IDs are intentionally kept stable unless a tested migration is provided.
- **Scripted agriculture scope:** the current implementation applies agricultural growth speed to newly planted tower crops. Existing farm rescaling remains a later manual test/spike item to avoid broad scans.

## Developer Specification

### Main Files

| File | Purpose |
| --- | --- |
| `control.lua` | Thin runtime wrapper for bounded scripted effects; not part of prototype generation. |
| `prototypes/mir/runtime/scripted_techs.lua` | Registers scripted technology lifecycle and event handlers. |
| `prototypes/mir/runtime/settings_profile.lua` | Exports current effective MIR startup settings, validates pasted profile strings, and exposes a small remote interface. |
| `prototypes/mir/runtime/effects/spoilage_preservation.lua` | Applies and restores the global spoilage preservation multiplier. |
| `prototypes/mir/runtime/effects/agricultural_growth_speed.lua` | Adjusts newly planted agricultural tower crops from researched growth speed. |
| `migrations/more-infinite-research_2.0.5.json` | Maps the removed generated trash-slot technology ID into the combined inventory/trash technology ID. |
| `migrations/more-infinite-research_2.1.0.json` | Maps the retired generated stone-product productivity technology ID into the new landfill productivity technology ID. |
| `data.lua` | Thin data-stage wrapper into `prototypes/mir/stage/data.lua`. |
| `data-updates.lua` | Thin data-updates wrapper into `prototypes/mir/stage/data_updates.lua`; reserved for future pre-final compatibility hooks. |
| `data-final-fixes.lua` | Thin final-fixes wrapper into `prototypes/mir/stage/data_final_fixes.lua`. |
| `prototypes/mir/settings/catalog.lua` | Canonical setting IDs, defaults, allowed values, bounds, and profile-validation metadata. |
| `prototypes/mir/settings/defaults.lua` | Shared stream defaults, per-stream overrides, and base-extension defaults. |
| `settings.lua` | Thin settings-stage wrapper into `prototypes/mir/stage/settings.lua`; startup settings are generated by `prototypes/mir/settings/stage_builder.lua`. |
| `prototypes/mir/settings/pipeline_extent.lua` | Owns pipeline extent dropdown values and parsing. |
| `prototypes/mir/pipeline/extent.lua` | Applies the opt-in startup-only pipeline extent multiplier to fluid boxes. |
| `prototypes/mir/streams/registry.lua` | Assembles shared stream config and compatibility profile overlays. |
| `prototypes/mir/planner/stream_compiler.lua` | Owns the generated stream loop. |
| `prototypes/mir/emit/base_extensions.lua` | Extends finite vanilla technology chains. |
| `prototypes/mir/emit/effect_safety.lua` | Blocks unsafe native effect types from MIR-generated technologies. |
| `prototypes/mir/emit/mod_data.lua` | Emits MIR mod-data prototypes used by runtime state reconciliation. |
| `prototypes/mir/policy/weapon_speed.lua` | Removes rocket/cannon-shell overlap from MIR's generated weapon speed continuation only under the configured coverage policy. |
| `prototypes/mir/policy/native_effect_coverage.lua` | Identifies exact, enabled, reachable infinite native-effect owners for ownership and overlap decisions. |
| `prototypes/mir/policy/max_level.lua` | Applies stream max levels after generation. |
| `prototypes/mir/report/diagnostics_sink.lua` | Structured generation report logging. |
| `prototypes/streams/productivity.lua` | Recipe-productivity stream definitions. |
| `prototypes/streams/direct-effects.lua` | Direct-effect stream definitions. |
| `prototypes/mir/platform/factorio/prototype_lookup.lua` | Shared prototype lookup helpers for items, fluids, technologies, ammo categories, mods, and labs. |
| `prototypes/mir/capabilities/science_integration/science_packs.lua` | Lab input discovery, science-pack ordering, lab validation, and prerequisite lookup. |
| `prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua` | Item/fluid recipe output matching, pattern matching, category filters, hidden/recycling skips. |
| `prototypes/mir/emit/icon_builder.lua` | Technology, item, fluid, and explicit icon resolution plus constant overlay construction. |
| `prototypes/mir/core/table.lua` | Small shared table helpers such as deterministic sorted keys. |
| `prototypes/mir/emit/technology_replacement.lua` | Commits graph-safe technology replacement only after emitted coverage exists, rewiring and deduplicating prerequisite edges transactionally. |
| `prototypes/mir/compatibility/profiles.lua` | Mod-specific stream patch scaffolding. |
| `prototypes/mir/policy/competing_productivity.lua` | Known competing recipe-productivity cleanup. |
| `prototypes/mir/policy/competing_base_extensions.lua` | Known competing base-extension cleanup. |

The shipped MIR 3 layout intentionally has no `prototypes/compat/`, `prototypes/lib/`, `prototypes/mir/legacy/`, root `defaults.lua`, or broad root helper shims such as `prototypes/util.lua`, `prototypes/config.lua`, `prototypes/diagnostics.lua`, or `prototypes/tech-gen.lua`. Factorio root entrypoints remain as required one-line lifecycle wrappers.

### Stream Schema

Productivity and direct-effect streams are Lua tables keyed by stream ID. Common fields include:

| Field | Meaning |
| --- | --- |
| `required_mods` | Skips the stream unless all listed mods are active. |
| `items` | Exact output item names to match. |
| `item_patterns` | Lua patterns for output item names. |
| `fluids` | Exact output fluid names to match. |
| `fluid_patterns` | Lua patterns for output fluid names. |
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
| `required_fluids` | Skips the stream unless all fluids exist. |
| `required_technologies` | Skips the stream unless all technologies exist and appends them as prerequisites. |
| `required_ammo_categories` | Skips direct effects unless ammo categories exist. |
| `icon`, `icon_size`, `icon_tech`, `icon_item`, `icon_fluid`, `overlay` | Technology icon resolution hints. |
| `localised_name`, `localised_description`, `description_locale_key` | Locale overrides. |

### Compatibility Profiles

`prototypes/mir/compatibility/profiles.lua` supports append-style fields so future mod profiles can extend base stream definitions without replacing arrays:

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
[more-infinite-research] report kind=stream key=research_science_pack_productivity status=generated reason=recipe_productivity science=... prerequisites=... effects=13 lab_status=reduced icon=tech:space-science-pack
```

Use diagnostics when reporting compatibility issues. It tells whether a stream generated, skipped, reduced science packs, or found no matching recipes. For direct-effect technologies, the report also includes non-blocking `native_modifier_overlap` rows when another infinite non-MIR technology already has the same native modifier target. Compatibility audits also capture planner rows, recipe-cap rows, typed fact summaries, compiler decisions, lab matrices, loop risks, and rule-surface observations in `compat-observations.*`.

MIR 3 compatibility claims are intentionally narrow. A target page can claim that a named recipe family is supported, that a mod has been observed, or that MIR deliberately avoids a conflict. It should not be read as full overhaul support unless a compatibility page and claim record explicitly say so.

Known 3.0.0 publication notes:

- portal-backed full-catalog checks were not run in this environment because `FACTORIO_TOKEN` was not set;
- local supported-zip isolation still finds `atan-ash_2.2.1` and `atan-nuclear-science_0.3.3` failing without MIR on the tested Factorio `2.1` setup, but MIR `3.0.0` applies exact-version loader-schema repairs when those zips are loaded with MIR;
- MIR's ATAN claims remain the narrow ash separation and nuclear-science-pack recipe productivity behavior documented under `docs/compatibility/targets/`.

Enable `mir-debug-recipe-matches` to log matched recipe rows like:

```text
[more-infinite-research] matches key=research_belts change=0.01 recipes=turbo-transport-belt,turbo-underground-belt,turbo-splitter
```

When either diagnostics setting is enabled, MIR also reports duplicate recipe matches across streams as warnings in the log. These reports do not block generation; they are for compatibility triage.

## Validation and Release Workflow

**Static validation:**

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

**Runtime fixture validation:**

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

**Build the package:**

```powershell
.\scripts\Build-MIRPackage.ps1
```

**Preferred developer CLI:**

```powershell
.\scripts\mir.ps1 release gate
.\scripts\mir.ps1 release docs-only
.\scripts\mir.ps1 overnight local
.\scripts\mir.ps1 audit local
.\scripts\mir.ps1 report latest
.\scripts\mir.ps1 local-index build --mods C:\Projects\Factorio\testmods_2.1
```

`mir.ps1` is the normal human front door. It delegates to the existing scripts, loads JSON run profiles from `fixtures/run-profiles/`, and accepts common overrides such as `--factorio`, `--factorio-line`, `--mods`, `--output`, `--timeout`, and `--link-mode`. Use `docs/maintainer/developer-tools.md` for the command map and script roles.

**Release gate with local smoke scenarios:**

```powershell
.\scripts\mir.ps1 release gate
```

This is the short release command. It runs:

- the strict `Static,Runtime,AuditSmoke` gate;
- optional local smoke mods;
- one representative local scenario;
- package rebuild, whitespace check, and clean-git-status check.

Defaults live in `fixtures/run-profiles/release-targeted.json`. Use `--profile`, `--factorio-line`, `--factorio`, `--mods`, `--output`, or `--timeout` for a different local setup. Use the overnight local sweep separately for broad compatibility evidence.

**Docs-only release refresh after a clean full gate:**

```powershell
.\scripts\mir.ps1 release docs-only
```

Use this only after the same release candidate has already passed the full gate and the remaining edits are documentation, release-note, changelog, or package-refresh changes. It rebuilds the package, runs static/package validation, checks whitespace, and fails if code, prototype, script, fixture, locale, or other non-doc files changed.

Stable direct script equivalent:

```powershell
.\scripts\Invoke-MIRReleaseTargetedGate.ps1
```

**Credentialed exploratory compatibility audits:**

```powershell
.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Top25Base,Top25SpaceAge,ManualScenarios -CollectAll
```

Set `FACTORIO_BIN`, `FACTORIO_USERNAME`, and `FACTORIO_TOKEN` before running download/load tiers. Audit scenarios time out after `900` seconds by default; override with `-ScenarioTimeoutSeconds` for unusually slow modsets. Full `downloads_count >= 10000` audits are intentionally opt-in through `-IncludeFullAudit` and can be sharded with `-StartIndex`, `-ShardSize`, and optionally `-FromLockfile`.

Local modpack zips can be included with the `LocalModZips` tier and `-LocalModZipDirs .\tmp`. Local zip roots are copied from disk, while any missing third-party dependencies are resolved from `-LocalModLibraryDirs` first and then, unless `-Offline` is set, through the Mod Portal cache when credentials are supplied. The local zip tier includes `+` recommended dependencies because many modpack wrapper mods use them as the pack contents.

For offline local testing, keep root candidates and dependency libraries separate. `LocalModZipDirs` is the set of mods that may become one-mod, curated, or generated scenarios. `LocalModLibraryDirs` is dependency inventory only, so generated scenarios do not accidentally become rooted in support libraries. Use a writable dependency-cache directory for downloaded prerequisites and keep read-only mod collections unchanged. Broad local runs can use `--link-mode Hardlink` on same-drive inputs to reduce copy overhead, or `--link-mode Copy` for the safest cross-drive behavior.

Use read-only local mod libraries for large offline sweeps:

```powershell
.\scripts\mir.ps1 overnight local
```

`mir.ps1 overnight local` uses a line-specific run profile and delegates to `Start-MIROvernightLocalSweep.ps1`. The default profile targets Factorio `2.1`; use `--factorio-line 2.0` or `--profile overnight-local-2.0` for a legacy-line sweep after selecting a real Factorio `2.0.x` binary and a matching local zip library. The bedtime script verifies the configured local library, disables AC sleep/hibernate for the current machine, runs the strict `Static,Runtime,AuditSmoke` gate first, then runs the prioritized local sweep with a transcript at `artifacts/overnight-local-<line>-*/overnight.log`. Each run also writes `run-manifest.json`, `events.jsonl`, `artifact-index.json`, and `index.html`. Use `--mods <path>` when your downloaded zip library is elsewhere. In the morning, run `.\scripts\mir.ps1 report latest` or `.\scripts\Show-MIROvernightSummary.ps1 -OutputRoot <overnight-output-dir>` to print the log tail, artifact paths, release/local summaries, grouped failures, missing dependencies, profile-candidate counts, and compatibility observation counts.

Run local-library tiers in priority order: `LocalLibraryScenarios` covers curated high-value combinations, `GeneratedLocalScenarios` creates generated mega and metadata-cluster stress cases, and `LocalModZips` tests each local root zip as an individual scenario. Add `-IncludeGeneratedLocalPairwise -GeneratedLocalPairwiseLimit 40` when you want capped pairwise cluster coverage. Add `-ShardLocalModZips -StartIndex N -ShardSize M` to resume local-root sweeps in chunks.

`LocalLibraryScenarios` runs curated local combinations from `fixtures/compat-matrix/local-library-scenarios.json` for Factorio `2.1` or `fixtures/compat-matrix/local-library-scenarios-2.0.json` for Factorio `2.0`. `GeneratedLocalScenarios` builds all-local, planet, resource, Bob, Krastorio, production/fluid, and logistics/transport clusters from local zip metadata. Factorio `2.0` archives should be tested with a matching Factorio/mod line; with a Factorio `2.1.x` MIR package and binary, `2.0`-only archives are useful as inventory evidence but are not a substitute for a true `2.0` runtime gate.

Use `-CollectAll` for overnight exploration so one failing modset does not stop the run. Use `-FailFast -FailOnAuditFailures` for strict CI-style gates; that mode fails when grouped unexpected audit failures remain after the converter runs.

Load-test tiers print per-scenario start/result lines with scenario index, type, root mods, dependency-failure count, pass/skip/timeout status, exit code, parsed audit-row count, and elapsed seconds. `load-results.json` is checkpointed after every scenario so partial results remain readable if a long run is interrupted. Extended-wrapper runs write their own manifest, event log, artifact index, and static HTML report under the selected output root. Pipe all streams through `Tee-Object` when you want a live VS Code terminal view and a durable overnight log. The grouped converter also writes `missing-dependencies.md`, `missing-dependencies.json`, and `missing-dependencies.csv` for local-library completion work, plus `compat-observations.md/json/csv` for diagnostics that are useful but not failures.

The audit runner writes an explicit isolated `mod-list.json`: official built-ins are disabled unless required by the scenario. If a scenario requests `space-age`, the runner enables `space-age` plus the official companion mods that actually exist beside the selected Factorio binary. Blank lines in Factorio logs are ignored by the MIR audit parser, so partial overnight runs remain convertible even when third-party logs contain empty lines.

`AuditSmoke` is line-aware and deterministic: Factorio `2.1` uses the committed `space-age-baseline` scenario, while Factorio `2.0` uses the base-only `base-baseline` scenario. It proves the audit wrapper and grouped-result converter are wired, but broad external-mod confidence still comes from the credentialed top-25/manual/full audit tiers.

The validation script checks:

- **Metadata:** `info.json` parses and release metadata avoids compatibility-mod dependencies.
- **Docs policy:** docs match the opportunistic compatibility policy.
- **Science-pack authority:** no old `data.raw.tool` science-pack authority remains.
- **Icons:** generated icons do not use `icon_mipmaps`.
- **Locale:** all 50 Factorio-supported locale files have exact English-key parity, source-hash-bound translation memory, protected placeholders and rich text, UI prose budgets, and stale-English/script checks.
- **PowerShell tooling:** scripts parse, duplicate parameters are rejected, generated output paths stay ignored, and obvious secret output is blocked.
- **Changelog:** `changelog.txt` uses Factorio's 99-dash format with one-line bullets capped at 132 characters.
- **Generated package:** validation builds an ignored archive from the current source tree and checks its root, metadata, load-critical files, and forbidden artifacts.
- **Package parity:** the generated archive's runtime source directories, locale, migrations, and root mod files match the repository copy. Developer docs, fixtures, scripts, and task ledgers are not shipped in the release zip.
- **Compatibility automation:** the Mod Portal audit runner, manual scenario execution, sharding/resume, scenario timeout, dependency-failure skipping, grouped failure converter, expected-failure fixture, profile-stub generator, and self-hosted extended workflow stay wired.
- **Whitespace:** `git diff --check` passes.
- **Runtime load:** fixture loading reaches save creation when a Factorio binary is supplied.
- **Runtime diagnostics:** logs contain the expected generation diagnostics.
- **Reduce policy:** science-pack productivity stays generated with a custom item-based science pack included.
- **Skip policy:** an intentionally incompatible science-pack set is skipped.
- **Post-MIR assertions:** fixtures prove both runtime lab-policy outcomes.
- **Native modifier overlap diagnostics:** a Maraxis-like duplicate cargo fixture proves cargo modifier overlaps are reported without changing MIR generation.
- **Fluid productivity:** post-MIR fixtures prove oil, lubricant, sulfuric acid, acid neutralization, and Space Age thruster propellant recipes have exactly one infinite productivity owner where those recipes exist.
- **Pipeline extent:** a post-MIR fixture proves the opt-in startup multiplier dropdown mutates common fluid boxes when enabled.

## Documentation Map

- **`todo.md`:** root executable future-work ledger. Keep the durable task list, release gates, future plans, recurring checklist, companion backlog, and rejected/deferred work here so the plan survives even if derivative docs are reorganized.
- **`docs/architecture/README.md`:** data-stage flow, utility modules, stream config, compatibility profiles, diagnostics, and validation.
- **`docs/architecture/compatibility-compiler-charter.md`:** 3.0 architecture charter, compiler pipeline, invariants, release ladder, non-goals, and acceptance gates.
- **`docs/architecture/module-boundaries.md`:** 3.0 Factorio shell, `prototypes/mir` compiler namespace, layer rules, no-shim shipped layout, package boundary, and architecture lint targets.
- **`docs/capabilities/README.md`:** capability resolver lanes, productivity/native-modifier split, confidence model, and settings posture.
- **`docs/compatibility/policy-overlays.md`:** declarative compatibility-policy model, overlay fields, modes, and lint rules.
- **`docs/reference/schemas/decision-record.md`:** planned `DecisionRecord` and `StreamSpec` schemas for explainable generation.
- **`docs/reference/schemas/stream-manifest.md`:** generated technology ID manifest and migration rules.
- **`docs/compatibility/claim-levels.md`:** claim levels, claim manifest shape, public wording rules, and claim linting.
- **`docs/maintainer/testing.md`:** 3.0 fixture, negative-test, report-diff, and release-gate strategy.
- **`docs/maintainer/README.md`:** workflow for adding capabilities, policies, fixtures, and bug-report proof cases.
- **`docs/adr/`:** architecture decision records for the 3.0 compatibility compiler.
- **`docs/reference/factorio-api-proof-points.md`:** API claims, proof status, and open in-game verification questions.
- **`docs/compatibility/README.md`:** compatibility model, known integrations, manual test matrix, fixture designs, and release checklist.
- **`docs/maintainer/developer-tools.md`:** preferred developer commands, run profiles, script roles, and PowerShell tooling checks.
- **`docs/releases/2.4.0-roadmap.md`:** published Factorio 2.0 port scope, target cuts, and sequencing.
- **`docs/releases/2.4.9-stability-backport.md`:** active Factorio 2.0 stability-patch scope, qualification gates, and release boundary.
- **`docs/releases/notes/release-notes-2.4.9.md`:** current player-facing Factorio 2.0 stability changes.
- **`docs/releases/2.5.0-verification-backport.md`:** planned Factorio 2.0 compiler and verification backport after the 2.4.9 release.
- **`docs/releases/2.4.5-validation-summary.md`:** immutable prior-release identity and validation evidence.
- **`docs/releases/2.2.0-validation-record.md`:** local release validation evidence.
- **`docs/maintainer/manual-test-plan.md`:** named manual saves/scenarios for release validation.
- **`docs/releases/mod-portal-page.md`:** mod-portal-ready public description, technology catalog, settings summary, compatibility notes, and troubleshooting text.
- **`docs/archive/superseded/release-plan-2.1.0.md`:** historical release-gated implementation plan for the Factorio `2.1` feature wave.
- **`docs/archive/superseded/post-2.0-feature-plan.md`:** historical post-v2.0.0 feature triage and staged implementation archive.
- **`docs/releases/notes/release-notes-2.1.0.md`:** player-facing `2.1.0` release-note summary derived from the detailed changelog.
- **`docs/archive/superseded/`:** superseded plans and reports retained as historical context. `changelog.txt` remains the authoritative past-change ledger.
- **`CONTRIBUTING.md`:** branch policy, pull request expectations, validation commands, and mod portal changelog rules.
- **`changelog.txt`:** release history and user-facing changes.

## Troubleshooting

If a technology is missing:

1. Enable **`mir-debug-generation-report`**.
2. Load the save or start a controlled test map.
3. Check **`factorio-current.log`** for the stream key.
4. Look for **`skipped`**, **`no_matching_recipes`**, **`missing required item`**, **`missing required technology`**, or **`no_lab_compatible_science`**.

If a recipe did not receive productivity:

1. Enable **`mir-debug-recipe-matches`** and inspect the stream's matched recipe list.
2. Confirm the recipe outputs one of the stream's exact items or matches one of its patterns.
3. Confirm the recipe is not hidden or recycling unless the stream opts in.
4. Confirm the recipe exists before MIR reaches `data-final-fixes.lua`.
5. Confirm another mod did not mutate the recipe after MIR scanned.

If a generated technology is unresearchable:

1. Check that at least one **active lab** accepts the full ingredient set.
2. Check the diagnostics row for **`lab_status=reduced`** or **`no_lab_compatible_science`**.
3. Verify custom science packs are real item prototypes and are present in at least one lab's **`inputs`**.

## Save Compatibility

No generated prototype IDs were renamed for **`v3.0.5`**. The convergence work preserves existing generated IDs and persisted-state schemas and does not require a new migration.

No generated prototype IDs were renamed for **`v2.0.0`**. **No migration is required** from `v1.2.9`.

`v2.0.5` includes a JSON migration from `recipe-prod-research_character_trash_slots-1` to `recipe-prod-research_inventory_capacity-1` so old trash-slot progress moves into the *combined inventory/trash research*.

`v2.1.0` includes a JSON migration from `recipe-prod-research_stone_products-1` to `recipe-prod-research_landfill-1` so old stone-product progress moves to the closest successor after landfill, artificial soil, and molten metals become *separate research lines*.
