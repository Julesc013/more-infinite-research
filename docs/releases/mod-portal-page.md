---
title: "More Infinite Research Mod Portal Page"
status: current
applies_to: "all supported More Infinite Research editions"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: [docs/releases/archive/mod-portal-page-old.md]
superseded_by: []
source_of_truth_for:
  - mir-universal-mod-portal-copy
---

# More Infinite Research

Adds fully customizable repeatable late-game research for productivity, speed, logistics, combat, player bonuses, robots, spoilage, cargo logistics, and compatible modded production chains.

More Infinite Research is for players who want useful long-term scaling in megabases, long-running saves, Space Age factories, and modded playthroughs without turning the mod into a full content overhaul.

The Mod Portal automatically offers an archive compatible with your Factorio version. Modern editions provide the complete compatibility-compiler feature set; historical-engine editions intentionally provide smaller target-appropriate sets. Install the newest compatible download shown by Factorio rather than copying an archive between engine generations.

## At a glance

- Adds configurable productivity research for intermediates, infrastructure, science packs, combat supplies, and compatible modded recipes.
- Adds repeatable character, robot, weapon-speed, cargo-logistics, and selected vanilla technology bonuses where the engine supports them.
- Lets you enable, disable, cap, or rebalance generated research through startup settings.
- Can explicitly adjust selected engine limits for productivity, energy use, pollution, speed, quality, and recycling; default values leave engine behavior unchanged.
- Discovers active recipes, items, technologies, science packs, and labs, then skips research that would be unsafe or unusable.
- Respects safe vanilla or third-party infinite research owners instead of creating duplicate effects.
- Keeps Space Age and other official expansion content optional and checks for the prototypes it actually needs.

## Productivity research

Depending on the installed content and the selected MIR edition, productivity research can cover:

- plates, gears, sticks, copper cable, circuits, batteries, sulfur, explosives, engines, robot frames, plastic, low-density structures, and rocket fuel;
- belts, underground belts, splitters, inserters, rails, walls, gates, landfill, soil, concrete, furnaces, mining drills, solar panels, and accumulators;
- ammunition, rockets, shells, grenades, armor components, modules, and science packs;
- oil processing, oil cracking, lubricant, sulfuric acid, acid neutralization, and compatible fluid process families;
- Space Age materials and processes such as tungsten, lithium, carbon, carbon fiber, ice, holmium, supercapacitors, superconductors, quantum processors, bioflux, and cultivation recipes;
- structurally compatible recipes and science packs added by other mods.

Technologies appear only when their required recipes, products, unlocks, labs, science packs, and effect types exist. Older Factorio editions omit features their engines cannot represent.

## Other repeatable bonuses

Supported editions can also add or continue research for:

- character mining, crafting, walking, inventory, logistic-trash, reach, build, and item-drop bonuses;
- worker robot battery and storage;
- rocket, cannon, flamethrower, electric, Tesla, laser, and general weapon shooting speed;
- braking force, laboratory research speed, and inserter capacity;
- cargo unloading distance and cargo landing-pad count when the relevant Space Age systems exist;
- agricultural growth and optional spoilage preservation in editions that support the scripted Space Age features.

Every feature is gated by the active engine and prototype set. A setting may be visible only in editions that can implement it safely.

## Research costs and limits

Generated research uses configurable first-level cost, linear per-level growth, exponential growth, maximum level, and research time. This supports fixed, linear, exponential, and hybrid curves. A maximum level of `0` means infinite.

Most settings are startup settings, so Factorio must restart after changing them. Common controls include:

- enabling or disabling individual research families;
- choosing research cost, growth, duration, and level caps;
- selecting science-pack and lab-compatibility policies;
- preferring safe existing research owners or MIR-owned replacements in reviewed cases;
- adjusting supported productivity, efficiency, pollution, speed, quality, recycling, and prototype limits;
- enabling concise generation and recipe-match diagnostics.

Recipe-productivity research remains subject to Factorio's active productivity cap unless you explicitly change that cap in the Limits settings.

## Compatibility approach

MIR reads the active prototype set late in data loading. It validates ownership, recipes, outputs, unlocks, science packs, labs, caps, prerequisites, and graph safety before creating or extending research.

This lets the mod coexist with Base Factorio, optional official expansions, custom labs and science packs, many recipe and logistics mods, and large overhauls without declaring every mod as a required dependency. Safe mod-added recipes can be adopted into an existing productivity family; hidden, recycling, self-return, denied, or otherwise unsafe recipes are excluded.

Compatibility is evidence-bound, not a blanket promise. A successful startup proves that a named combination loads; it does not guarantee ideal balance or semantic support for every feature in every overhaul. Mods that create or mutate relevant prototypes after MIR has scanned may still need a specific load-order adapter.

## Updating an existing save

Make a normal save backup before updating. Use the newest MIR download compatible with the same Factorio generation, keep or export your startup settings, load and save once, then reload that new save to confirm stable state.

MIR preserves stable technology, setting, locale, profile, migration, and runtime-state identities wherever the target engine permits. When a release requires a specific migration path or has a known limitation, the download's changelog and release notes are authoritative.

Do not install an archive built for a different Factorio generation. Historical editions are real target-specific ports, not modern packages with only their version metadata changed.

## Troubleshooting

If a technology is missing:

- check that it is enabled in startup settings;
- check that the required content exists;
- check that at least one active lab accepts its science packs;
- check whether vanilla or another mod already owns the same infinite effect;
- enable generated/skipped-technology diagnostics and inspect `factorio-current.log`.

If a recipe did not receive productivity:

- it may be hidden, recycling, self-returning, outside the matched family, or already capped;
- another mod may own the effect or may have changed the recipe after MIR scanned;
- enable recipe-match diagnostics to see the accepted and rejected matches.

A useful issue report includes the Factorio and MIR versions, enabled mod names and versions, relevant startup settings, the smallest reproducing save or mod set, and the relevant MIR log rows. Remove usernames, absolute paths, credentials, and unrelated save data before sharing logs.

## Links

- [Source code and releases](https://github.com/Julesc013/more-infinite-research)
- [Issue tracker](https://github.com/Julesc013/more-infinite-research/issues)
- [Detailed changelog](https://github.com/Julesc013/more-infinite-research/blob/main/changelog.txt)
