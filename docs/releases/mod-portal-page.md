---
title: "More Infinite Research"
status: current
applies_to: "3.0.0+"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: []
superseded_by: []
---
# More Infinite Research

Adds **fully customizable** repeatable late-game research for **productivity,
speed, logistics, combat, player bonuses, robots, spoilage, and cargo
logistics**.

It is built for players who want more *long-term scaling for late-game
megabases*, long-running Space Age saves, and modded playthroughs without
turning the mod into a full content overhaul.

## MIR 3.0.0

MIR 3.0.0 is the compatibility compiler architecture release.

It moves active implementation under `prototypes/mir`, keeps generated
technology IDs stable, keeps compatibility overlays declarative, and continues
to skip unsafe or unavailable research instead of claiming automatic support for
every mod.

The architecture change does not require a new migration by itself. Existing
generated technology IDs are preserved, and the shipped `2.0.5` and `2.1.0`
migrations remain in place.

## At a Glance

- Adds many **configurable infinite productivity researches** for vanilla, Space Age, and compatible modded production chains.
- Adds repeatable player, robot, weapon-speed, cargo-logistics, and selected vanilla technology bonuses.
- Startup **settings let you enable, disable, cap, or rebalance** every generated research.
- Adds a base-game Research productivity chain when Space Age's vanilla `research-productivity` technology is not present.
- Adopts safe mod-added recipes into configured vanilla Space Age productivity families instead of creating parallel research.
- Uses MIR 3 compiler diagnostics to explain generated, skipped, observed, and rejected research decisions.

- Legacy transition releases **`1.9.0`** through **`1.9.2`** target **Factorio `2.0`** and require `base >= 2.0`.
- Version **`3.x.x`**, starting with **`3.0.0`**, targets **Factorio `2.1`**; requires `base >= 2.1.8`. Space Age is optional.

*Recipe productivity researches are infinite, but Factorio's recipe productivity cap still applies. Once a recipe reaches that cap, more levels may no longer improve that recipe.*

## Main Features

The mod adds repeatable recipe productivity for many things vanilla does not fully cover:

- Plates, gears, sticks, copper cable, circuits, batteries, sulfur, explosives, engines, robot frames, plastic, low density structures, and rocket fuel.
- Belts, underground belts, splitters, inserters, rails, walls, gates, landfill, artificial soil, molten metals, concrete, furnaces, mining drills, solar panels, and accumulators.
- Bullets, shotgun shells, cannon shells, artillery shells, railgun ammo, rockets, grenades, cluster grenades, and armor components.
- Modules, science packs, and compatible modded science packs found in active labs.
- Space Age materials such as tungsten, lithium, carbon, carbon fiber, ice, holmium, supercapacitors, superconductors, quantum processors, bioflux, bacteria cultivation, and breeding-related recipes.

Most simple productivity researches give `+10%` productivity per level. Larger grouped researches use smaller bonuses for stronger or higher-tier items.

### More Repeatable Bonuses

The mod can add infinite research for:

- Character mining speed, crafting speed, walking speed, inventory slots, logistic trash slots, and optional reach/build distance.
- Worker robot battery capacity.
- Rocket, cannon, flamethrower, electric, and Space Age Tesla weapon shooting speed.
- Cargo bay unloading distance and optional cargo landing pad count with Space Age.
- Scripted Space Age spoilage preservation and agricultural growth speed as disabled-by-default experimental candidates.

### More Vanilla Tech Continuations

Several vanilla technology chains can continue past their normal final level:

- Braking force.
- Lab research speed.
- Worker robot storage.
- Weapon shooting speed.
- Laser shooting speed.
- Inserter capacity bonus, disabled by default.

## Technology Catalog

Technologies are generated only when their recipes, items, technologies, ammo categories, labs, and science packs exist in the active mod set. "On" means enabled by default when the required prototypes exist. "Off" means available as an opt-in startup setting.

### Recipe Productivity

| Technology | Effect per level | Default | Unique notes |
| --- | --- | --- | --- |
| Copper plate productivity | `+10%` productivity for copper plate recipes | On | Skips hidden and recycling recipes. |
| Iron plate productivity | `+10%` productivity for iron plate recipes | On | Skips hidden and recycling recipes. |
| Iron gear wheel productivity | `+10%` productivity for iron gear wheel recipes | On | Avoids scrap-input recipes. |
| Iron stick productivity | `+10%` productivity for iron stick recipes | On | Avoids scrap-input recipes. |
| Copper cable productivity | `+10%` productivity for copper cable recipes | On | Avoids scrap-input recipes. |
| Electronic circuit productivity | `+10%` productivity for electronic circuit recipes | On | Adds electromagnetic science when available. |
| Advanced circuit productivity | `+10%` productivity for advanced circuit recipes | On | Adds electromagnetic science when available. |
| Processing unit productivity | `+10%` productivity for processing unit recipes | On, skipped when vanilla owns it | Uses processing unit unlock technology art. Space Age's vanilla productivity chain stays authoritative. |
| Plastic productivity | `+10%` productivity for plastic recipes | On, skipped when vanilla owns covered recipes | Adds agricultural science when available. Space Age's vanilla plastic productivity stays authoritative. |
| Sulfur productivity | `+10%` productivity for sulfur recipes | On | Adds metallurgic science when available; avoids asteroid-input recipes. |
| Battery productivity | `+10%` productivity for battery recipes | On | Adds electromagnetic science when available. |
| Explosives productivity | `+10%` productivity for explosives and bio-explosives recipes | On | Adds metallurgic science when available. |
| Engine unit productivity | `+10%` productivity for engine unit recipes | On | Adds metallurgic science when available. |
| Electric engine unit productivity | `+10%` productivity for electric engine unit recipes | On | Adds electromagnetic science when available. |
| Flying robot frame productivity | `+10%` productivity for flying robot frame recipes | On | Adds electromagnetic science when available. |
| Low density structure productivity | `+10%` productivity for low density structure recipes | On, skipped when vanilla owns covered recipes | Space Age's vanilla low density structure productivity stays authoritative. |
| Rocket fuel productivity | `+10%` productivity for rocket fuel recipes | On, skipped when vanilla owns covered recipes | Uses rocket fuel unlock technology art. Space Age's vanilla rocket fuel productivity stays authoritative. |
| Oil processing productivity | `+10%` productivity for basic oil processing, advanced oil processing, and coal liquefaction recipe families | On | Owns multi-output oil-processing recipes as one process family. Adds cryogenic science when available. |
| Oil cracking productivity | `+10%` productivity for heavy oil cracking and light oil cracking | On | Uses oil processing technology art and stays separate from multi-output oil processing. Adds agricultural science when available. |
| Lubricant productivity | `+10%` productivity for lubricant recipes | On | Excludes barrel-emptying recipes. Includes Space Age biolubricant when present. Adds electromagnetic science when available. |
| Sulfuric acid productivity | `+10%` productivity for sulfuric acid and acid neutralization recipes | On | Uses sulfuric acid fluid art and excludes barrel-emptying recipes. Adds metallurgic science when available. |
| Thruster fuel productivity | `+10%` productivity for Space Age thruster fuel recipes | On when fluid exists | Covers basic and advanced thruster fuel recipes when present. |
| Thruster oxidizer productivity | `+10%` productivity for Space Age thruster oxidizer recipes | On when fluid exists | Covers basic and advanced thruster oxidizer recipes when present. |
| Tungsten productivity | `+10%` productivity for tungsten plate and tungsten carbide recipes | On when recipes exist | Adds metallurgic science when available. |
| Lithium productivity | `+10%` productivity for lithium plate recipes; `+5%` for lithium from brine | On when recipes exist | Adds cryogenic science when available. |
| Holmium productivity | `+10%` productivity for holmium plate recipes | On when recipes exist | Adds electromagnetic science when available. |
| Supercapacitor productivity | `+10%` productivity for supercapacitor recipes | On when recipes exist | Adds electromagnetic science when available. |
| Superconductor productivity | `+10%` productivity for superconductor recipes | On when recipes exist | Adds electromagnetic science when available. |
| Quantum processor productivity | `+10%` productivity for quantum processor recipes | On when recipes exist | Adds cryogenic science when available. |
| Carbon productivity | `+10%` productivity for carbonic asteroid crushing and compatible carbon-output recipes; `+5%` for burnt spoilage; `+2%` for coal synthesis | On when recipes exist | Adds space science when available. |
| Carbon fiber productivity | `+10%` productivity for carbon fiber recipes | On when recipes exist | Adds agricultural science when available. |
| Ice productivity | `+10%` productivity for oxide asteroid crushing and compatible ice recipes | On when recipes exist | Adds space science when available. |
| Bioflux productivity | `+10%` productivity for bioflux recipes | On when recipes exist | Adds agricultural science when available. |
| Bacteria cultivation productivity | `+10%` productivity for iron and copper bacteria cultivation recipes | On when recipes exist | Uses bacteria cultivation technology art. Adds agricultural and cryogenic science when available. |
| Breeding productivity | `+10%` productivity for raw fish, biter egg, pentapod egg, and cultivation/culture/breeding recipes except dedicated bacteria cultivation recipes | On when recipes exist | Adds agricultural and cryogenic science when available; avoids broad biochamber category matching so unrelated biochamber recipes are not swept in. |
| Grenade productivity | `+10%` for grenades; `+5%` for cluster grenades | On | Adds military and space science when available. |
| Wall productivity | `+10%` for stone walls; `+5%` for gates | On | Uses the Gate technology art. |
| Landfill productivity | `+10%` for landfill; `+5%` for foundation | On when recipes exist | Uses landfill technology art. Adds metallurgic and space science when available. |
| Artificial soil productivity | `+10%` for artificial soils; `+5%` for overgrowth soils | On when recipes exist | Uses artificial soil technology art. Adds agricultural and space science when available. |
| Molten metals productivity | `+10%` for iron and copper from lava; `+5%` for iron and copper ore melting | On when recipes exist | Uses foundry technology art. Adds metallurgic science when available. |
| Rail productivity | `+10%` productivity for rail recipes; `+5%` for Elevated Rails supports; `+2%` for Elevated Rails ramps when present | On | Uses strict rail matching and prefers Elevated Rails technology art when available. |
| Concrete productivity | `+10%` for stone brick; `+5%` for concrete; `+2%` for refined concrete | On | Includes hazard concrete variants. |
| Furnace productivity | `+20%` for stone furnaces; `+10%` for steel furnaces; `+5%` for electric furnaces; `+2%` for foundries | On | Adds metallurgic science when available. |
| Mining drill productivity | `+20%` for burner drills; `+10%` for electric drills; `+5%` for big, Omega-style, and broader modded drill outputs | On | Covers Omega Drill style `omega-drill` and `omega-tau` recipes. |
| Electric energy productivity | `+10%` for solar panels/accumulators; lower tiers for Advanced Solar HR upgrades | On | Supports advanced, elite, and ultimate solar/accumulator families when visible. |
| Bullet productivity | `+10%` for basic firearm/shotgun ammo; `+5%` piercing; `+2%` uranium; `+1%` plutonium/tungsten patterns | On | Adds military and space science when available. |
| Cannon shell productivity | `+10%` cannon shells; `+5%` explosive shells; `+2%` uranium shells; `+1%` artillery shell, railgun ammo, and modded shell/ammo patterns | On | Player-facing rename from Heavy ammunition productivity. Internal ID is preserved. Covers ammo only, not artillery or railgun buildings. |
| Rocket productivity | `+10%` rockets; `+5%` explosive rockets; `+2%` atomic bombs; `+1%` plutonium bomb patterns | On | Adds agricultural and military science when available. |
| Armor component productivity | `+5%` armor plating patterns; `+2%` armor plate patterns | On when recipes exist | Supports armor/armour spelling variants. |
| Module productivity | `+10%` tier 1 modules; `+5%` tier 2; `+2%` tier 3 | On | Includes quality modules when the Quality mod is active. Quality is a hidden optional load-order dependency. |
| Transport belt productivity | `+10%` yellow; `+5%` red; `+2%` blue; `+1%` turbo; `+0.5%` hyper belt families | On | Covers belts, underground belts, splitters, and compatible loader recipes when visible. |
| Inserter productivity | `+10%` basic/burner; `+5%` fast/long-handed; `+2%` bulk; `+1%` stack inserters | On | Adds space science when available. |
| Science pack productivity | `+10%` productivity for science pack recipes | On | Targets vanilla, Space Age, and compatible modded lab-input science packs, including ATAN-style Nuclear Science packs when visible. Uses Space Age research-productivity art when available and white space-science technology art otherwise. |

### Direct, Scripted, And Bonus Research

| Technology | Effect per level | Default | Unique notes |
| --- | --- | --- | --- |
| Research productivity | `+10%` lab research productivity | On without Space Age; skipped with Space Age | Base-game equivalent of Space Age's vanilla research productivity. Uses the native `laboratory-productivity` modifier. |
| Spoilage preservation | `+1%` global spoil time per level | Off | Experimental Space Age scripted technology. Global/map-wide effect; existing item-stack behavior still needs manual validation before stronger claims. |
| Agricultural growth speed | `+1%` agricultural growth speed per level, capped at `10x` | Off | Experimental Space Age scripted technology. Adds agricultural, electromagnetic, and cryogenic science when available. Applies to newly planted agricultural tower crops; existing planted crops are not globally rescanned. |
| Character inventory slots | `+1` inventory slot and `+1` logistic trash slot | On | Merges the old separate trash-slot research into one combined technology. A migration preserves old trash-slot progress. |
| Worker robot battery | `+10%` worker robot battery capacity | On | Uses a gentler default cost growth than shared productivity streams. Skips when Better Bot Battery-style `worker-robots-battery-6` already exists. |
| Cargo bay unloading distance | `+10` maximum unloading distance tiles | On with Space Age | Requires Space Age unloading bay content. Uses the unloading bay unlock technology art and official base and Space Age science packs. |
| Cargo landing pad count | `+1` landing pad per surface | Off | Sandbox-style Space Age logistics option. Uses Space platform technology art. Very expensive by default. |
| Rocket shooting speed | `+10%` shooting speed for rocket ammo category | On | Separate dedicated speed research using electromagnetic science when available. |
| Cannon shooting speed | `+10%` shooting speed for cannon-shell ammo category | On | Separate dedicated speed research using electromagnetic science when available. |
| Flamethrower shooting speed | `+10%` flamethrower shooting speed | On | Includes flamethrower turret-style weapons. |
| Electric shooting speed | `+10%` shooting speed for electric and Tesla ammo categories | On when prerequisites exist | Affects discharge defense in vanilla and Tesla guns/turrets in Space Age. Uses speed badge, not damage badge. |
| Character mining speed | `+5%` mining speed | On | Uses late-game utility/military/agricultural/electromagnetic science when available. |
| Character crafting speed | `+5%` crafting speed | On | Direct character bonus. |
| Character walking speed | `+5%` running speed | On | Direct character bonus. |
| Character reach bonus | `+10` reach, build distance, resource reach, and item drop distance | Off | Disabled by default because large reach bonuses can change normal play. Uses the pickaxe/mining-speed icon. |

### Vanilla Technology Continuations

| Technology | Effect | Default | Unique notes |
| --- | --- | --- | --- |
| Braking force | Continues vanilla braking-force bonuses infinitely | On | Inherits the vanilla chain and adds space science when available. |
| Lab research speed | Continues vanilla lab research speed infinitely | On | Can add all active lab science packs depending on settings. |
| Worker robot storage | Continues vanilla robot cargo capacity infinitely | On | Skips when an equivalent infinite extension already exists. |
| Inserter capacity bonus | Continues inserter stack/bulk capacity bonuses | Off | Default increments are `+2` non-bulk and `+4` bulk/stack. Disabled because it can change factory assumptions. |
| Weapon shooting speed | Continues vanilla general weapon shooting speed infinitely | On | Finite vanilla tank cannon and rocket bonuses are preserved. Optional cleanup can separate rocket/cannon bonuses into dedicated MIR technologies. |
| Laser shooting speed | Continues vanilla laser shooting speed infinitely | On | Copies vanilla laser-speed effects. |

## Settings Worth Knowing

All settings are startup settings, so Factorio must restart after changing them.

For most generated research you can change:

- Whether the research is enabled.
- The first-level cost.
- The cost growth per level.
- The maximum level, where `0` means infinite.
- The research unit time.

Other useful settings:

- Require finishing the game before generated technologies: optional, off by default.
- Extra science packs for generated technologies: keep configured packs, add fixed late-game packs, infer missing official or modded progression packs from selected packs, use all official science packs, or use all active lab science packs.
- What to do when no lab can research a technology: reduce to compatible science packs by default, or skip incompatible technologies.
- Use MIR when another mod adds the same infinite research: lets this mod remove selected overlapping infinite technologies when MIR generated replacements exist.
- Remove duplicate rocket/cannon speed from general weapon speed: optional cleanup; off by default.
- Diagnostics: log generated/skipped technologies, recipe matches, or scripted effects for troubleshooting.

## Compatibility

The mod scans your active mod set and only creates research when the needed recipes, items, technologies, ammo categories, labs, and science packs exist.

This helps it work with:

- Base Factorio and optional Space Age content.
- Space Age installs without Quality.
- Custom science-pack and custom lab mods.
- Castra and PlanetLib-style planet or science-pack mods.
- Air Scrubbing clean-filter recipes, with scrubbing and cleaning recipes deliberately excluded.
- ATAN Ash separation, with landfill, brick, nutrient, foundation, tile, and recovery-style ash sinks deliberately excluded.
- Exact `atan-ash_2.2.1` Factorio `2.1` loader-schema repair when ATAN Ash is loaded with MIR.
- ATAN-style Nuclear Science packs through science-pack productivity.
- Exact `atan-nuclear-science_0.3.3` Factorio `2.1` loader-schema repair when ATAN Nuclear Science is loaded with MIR.
- AAI-style loader crafting recipes through Transport belt productivity.
- Standalone big mining drill mods through Mining drill productivity.
- Advanced Solar HR.
- Better Robots Extended.
- OCs Ammo and Armor.
- OCs Stone Casting.
- Fluid Quality Imprinting.
- Plates n Circuit Productivity, with replacement limited to exact known infinite technologies that MIR can fully replace with matching recipe productivity values and no other blocking owner.
- Panglia-style planet mods that add alternate rocket fuel or low density structure recipes.
- Omega Drill style drill mods.

When this mod is set to prefer its own overlapping research, it only removes known competing infinite technologies that are fully covered by generated More Infinite Research effects. Finite upgrade chains from other mods are left alone. Vanilla Space Age productivity families remain authoritative where safe, so mod-added rocket fuel or low density structure recipes can be appended to the vanilla infinite technology instead of receiving duplicate-looking MIR research.

Compatibility is broad, but not guaranteed for every overhaul. Mods that change
recipes or labs very late in loading may still need load-order compatibility.
MIR 3 public claims are deliberately narrow: a page may claim a named recipe
family, a diagnostic observation, or coexistence behavior, but not full overhaul
support unless that claim is explicitly recorded.

For maintainers and pack authors, the repository includes an extended local audit workflow. With a Factorio binary and Mod Portal credentials, it can run top-download audits; with read-only local mod zip libraries, it can also run offline individual-root, curated-combination, and generated local-library stress sweeps. The workflow supports curated overhaul scenarios, local modpack zip roots, safe unattended local sweep and morning summary helpers, parsed MIR diagnostics, checkpointed load results, missing-dependency summaries, grouped expected/unexpected failure reports, explicit official-DLC mod-list isolation, blank-log-line-tolerant audit parsing, and review-only compatibility profile stubs. Exploratory runs collect all scenarios for triage; strict runs can fail on unexpected grouped failures. These tools are for evidence collection; they do not automatically enable new compatibility profiles.

Known 3.0.0 publication notes:

- Portal-backed full-catalog checks were not run in the release environment
  because `FACTORIO_TOKEN` was not set.
- Local supported-zip isolation still finds `atan-ash_2.2.1` and `atan-nuclear-science_0.3.3` failing without MIR on the tested Factorio `2.1` setup, but MIR `3.0.0` applies exact-version loader-schema repairs when those zips are loaded with MIR.

## Troubleshooting

If a technology is missing:

- Check that the technology is enabled in startup settings.
- Check that the required content exists, especially for Space Age-only research.
- Check that at least one active lab can use the required science packs.
- Check whether another mod already provides the same kind of infinite research.
- Enable `Log generated and skipped technologies` for more detail in `factorio-current.log`.

If a recipe did not receive productivity:

- The recipe may be hidden, recycled, or outside the matched item group.
- Another mod may have changed the recipe after this mod scanned it.
- The recipe may already be at Factorio's productivity cap.
- Enable `Log recipes matched by productivity technologies` to see which recipes were matched.

## Save Compatibility

Version `3.0.0` preserves generated technology IDs through the MIR architecture move and does not need a new migration.

Version `2.1.0` preserves generated technology IDs except for documented intentional migrations:

- Old generated trash-slot progress migrates into the combined Character inventory slots technology.
- Old generated Stone product productivity progress migrates into the new Landfill productivity technology. Artificial soil productivity and Molten metals productivity are new separate research lines.

Existing saves receive the `2.0.5` and `2.1.0` JSON migrations automatically when the mod loads.

Scripted spoilage and agriculture effects are disabled by default in `3.0.0`.
