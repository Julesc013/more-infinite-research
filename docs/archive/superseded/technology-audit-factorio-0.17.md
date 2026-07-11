---
title: "Factorio 0.17 Technology Availability Audit"
status: archived
applies_to: "0.17"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../maintainer/backporting.md"]
---
# Factorio 0.17 Technology Availability Audit

This report explains the MIR `1.7.0` technology graph, why some technologies
were red and unavailable during RC testing, and whether the fixes follow or
work around the Factorio `0.17` engine.

## Verdict

The unavailable group was a MIR prerequisite inference bug, not intended
gameplay and not an engine limitation.

Factorio `0.17.79` includes a disabled tutorial technology named
`basic-mining`. That tutorial technology lists the normally enabled Automation
science recipe as an unlock. MIR previously selected it as the Automation
science progression gate. Every generated stream using Automation science then
depended on a technology that normal freeplay never enables or researches.

The correction follows engine rules:

- A visible recipe already enabled without research needs no unlock
  prerequisite.
- An inferred unlock technology must have `enabled ~= false`.
- MIR does not enable or research `basic-mining`.
- MIR does not bypass legitimate pack, equipment, weapon, or vehicle unlocks.
- MIR continues to emit only native Factorio `0.17` technology modifiers.

## Direct-Effect Technology Audit

All eleven direct-effect streams are enabled by default in the reduced `0.17`
package. Science-pack unlock technologies remain prerequisites except when the
pack already has a visible enabled recipe.

| Generated technology | Native effect | Intended progression gate | RC finding |
| --- | --- | --- | --- |
| `recipe-prod-research_inventory_capacity-1` | Inventory and logistic trash slots | Military and Utility science unlocks | Intended late-game gate; not affected by `basic-mining` |
| `recipe-prod-research_robot_battery-1` | Worker robot battery | Logistic, Chemical, Production, and Space science unlocks | Previously blocked by the false Automation gate; fixed |
| `recipe-prod-research_lab_productivity-1` | Laboratory productivity | Logistic, Military, Chemical, Production, Utility, and Space science unlocks | Previously blocked by the false Automation gate; fixed |
| `recipe-prod-research_rocket_shooting_speed-1` | Rocket gun speed | `rocketry` plus Logistic, Chemical, Production, and Military science unlocks | Explicit weapon unlock is intended; false Automation gate removed |
| `recipe-prod-research_cannon_shooting_speed-1` | Cannon-shell gun speed | `tanks`, `weapon-shooting-speed-5`, and Logistic, Chemical, Production, and Military science unlocks | Tank and finite cannon-speed gates are intended; false Automation gate removed |
| `recipe-prod-research_flamethrower_shooting_speed-1` | Flamethrower gun speed | `flamethrower` plus Logistic, Chemical, Production, Military, and Space science unlocks | Weapon gate is intended; false Automation gate removed |
| `recipe-prod-research_electric_shooting_speed-1` | Electric gun speed | `discharge-defense-equipment` plus Logistic, Chemical, Production, and Military science unlocks | Equipment gate is intended; false Automation gate removed |
| `recipe-prod-research_character_mining_speed-1` | Character mining speed | Military and Utility science unlocks | Intended late-game gate; not affected by `basic-mining` |
| `recipe-prod-research_character_crafting_speed-1` | Character crafting speed | Military and Utility science unlocks | Intended late-game gate; not affected by `basic-mining` |
| `recipe-prod-research_character_walking_speed-1` | Character running speed | Military and Utility science unlocks | Intended late-game gate; not affected by `basic-mining` |
| `recipe-prod-research_character_reach-1` | Character reach/build/resource/drop distance | Military and Utility science unlocks | Intended late-game gate; not affected by `basic-mining` |

The affected six-of-eleven split explains why the UI looked approximately half
available and half unavailable. The six affected streams used Automation
science through their configured or default pack set; the five character and
inventory streams did not.

## Base Continuation Audit

MIR also extends finite vanilla chains. These are separate from the dedicated
direct-effect streams.

| Continuation | Default | Availability rule |
| --- | --- | --- |
| Braking force | On | Requires the highest finite vanilla Braking force level |
| Research speed | On | Requires the highest finite vanilla Research speed level |
| Worker robot storage | On | Requires the highest finite vanilla storage level |
| Weapon shooting speed | On | Requires the highest finite vanilla weapon-speed level |
| Laser shooting speed | On | Requires the highest finite vanilla laser-speed level |
| Inserter capacity bonus | Off | Intentionally opt-in because larger hand sizes can alter circuit-controlled inserter behavior |

The general Weapon shooting speed continuation and dedicated rocket/cannon
streams can otherwise own the same infinite bonuses. The default
`only-when-dedicated-tech-enabled` policy removes rocket and cannon-shell
effects only from MIR's generated general continuation when the corresponding
dedicated MIR technologies were emitted. Finite vanilla technologies are not
changed. `off` remains the compatibility escape hatch; `always` is not a safe
default because it can remove effects without proving a replacement exists.

## Expected Red Technologies

A generated technology can still be red before normal progression is complete.
That is intended when one of its listed science, weapon, vehicle, or equipment
prerequisites is not researched. For example, Cannon shooting speed should not
be available before Tanks and Weapon shooting speed 5.

After this fix, a generated stream must not be red solely because of a disabled
tutorial or scenario technology. The binary fixture rejects that graph shape.

## Unlock-All Behavior

Factorio `0.17.79` documents
`LuaForce.research_all_technologies(include_disabled_prototypes)` with
`include_disabled_prototypes` defaulting to `false`. Therefore
`basic-mining` correctly remains disabled and unresearched after the common
unlock-all command.

Infinite technologies also continue to display an unresearched next level
after the command advances them. Seeing the next infinite level is expected;
seeing it red while every legitimate prerequisite is researched is not.

Manual verification command:

```text
/c game.player.force.research_all_technologies()
```

Expected result: all generated direct-effect technologies show their next
infinite level as available, and none lists `basic-mining` as a prerequisite.

The final RC probe created a Factorio `0.17.79` save from the exact dist
archive. It reported all eleven generated direct-effect technologies at level
`2`, with zero unmet prerequisites and zero disabled prerequisites.

## Engine-Alignment Assessment

MIR is not fighting the engine in this correction. It is removing an invalid
data-stage graph edge before Factorio creates force technology state. There is
no runtime polling, force mutation, automatic research, scripted bonus, or
replacement for the normal research system.

The dedicated direct effects are native `0.17` modifiers accepted by the target
binary. Features without a proven native surface, including recipe
productivity and Factorio `2.x` DLC effects, remain excluded from `1.7.0`.
