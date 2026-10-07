---
title: "Science Integration Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-10-07
supersedes: []
superseded_by: []
---

# Science Integration Capability

Science integration decides when active science packs participate in generated research costs or science-pack productivity. A pack must have a physical item prototype and be listed as an input by an active lab; lab compatibility remains the hard gate. Its prototype kind is not an admission contract: target profiles describe engine shapes, while the active lab relationship proves research use.

The dynamic science-pack manufacturing stream binds its base and discovered lab inputs to productive item outputs and rejects explicit upstream productivity bans. A same-named fluid cannot receive the item's manufacturing bonus, and a fully productivity-excluded science item cannot qualify through an unrelated coproduct. Explicit caller output constraints retain their authority. A modded sample used by a lab belongs to this existing science stream when its final recipe passes admission; adding a separate sample owner would duplicate that coverage. This rule does not qualify garden, seed or tree production, upstream finalizers, native output or save upgrades.

The 3.1 implementation separates six authorities behind the stable `science_packs.lua` facade:

- `pack_registry.lua` admits physical lab inputs as research packs and owns official ordering;
- `lab_compatibility.lua` validates or deterministically reduces ingredient sets;
- `recipe_unlock_facts.lua` owns recipe output, initial-availability, and indexed unlock facts;
- `technology_researchability.lua` owns enabled, acyclic, lab-valid researchability and reason codes;
- `pack_production_reachability.lua` resolves initial, research-gated, non-recipe, and unreachable pack production;
- `science_selection_policy.lua` owns configured, official, Space Age, mod-progression, and extension selection.

The facade wires the two recursive authorities through explicit callbacks, avoiding module-load cycles while preserving the existing public functions and rejection strings. Each fact cache is private; consumers receive values or copies rather than mutable cache tables. A rejected recursive alternative is traversal-local and cannot poison a later root query; a recipe that produces its own research ingredient still requires an independently earlier acquisition witness. When one proved technology unlocks several early intermediates, its contextual witness may support each distinct recipe while their routes are being checked; only re-entering the same active recipe/technology pair is rejected as an unseeded loop. Recipe-output lookup preserves the normalized item/fluid identity, so a research-unlocked fluid intermediate cannot be mistaken for an item or silently omitted.

Science ingredients and progression prerequisites are separate decisions. A pack with an independent initial acquisition route needs no inferred research gate. An enabled outer recipe can still require a research-gated ingredient or machine; those selected unlocks remain in its frontier. Natural acquisition witnesses include surface-qualified minable resources and trees as well as offshore pumps; a tree is not silently treated as a resource prototype. When pack production requires a recipe unlock, candidates must:

- exist and remain enabled in the final prototype graph;
- actually unlock a recipe producing the selected pack;
- have enabled, existing, acyclic prerequisite ancestry;
- be selected deterministically by technology prototype name.

Hidden technologies are not rejected merely for being hidden. A hidden implementation technology can remain a valid gate when it is enabled, researchable, and recipe-proven. Disabled tutorial, campaign, scenario, debug, or deprecated technologies are not valid inferred freeplay gates.

Recipe acquisition and category matching consume the same normalized category facts as productivity-cap policy. An explicit plural list takes precedence over a leftover singular category; an empty or malformed list does not invent a crafting route. Modeled recipe variants inherit their parent's category when neither variant field is declared, and the candidate index contains only those resolved variant categories. Controlled source checks cover these rules and the resulting acquisition decisions; native machine availability and affected catalogue/save behavior still need their selected environment.

A matching crafting category also needs an independently obtainable machine placement item, a declared native capture route, or a matching character crafting category. The shared acquisition solver checks these inputs with the same active research and cycle guards; a machine requiring the lab or product under assessment cannot bootstrap that route. For native capture, a spawner must declare the exact resulting entity, compatible obtainable ammunition must create a positive-speed capture robot through the recognized direct projectile/instant trigger chain, and an obtainable launcher must accept that ammunition. Fixed-recipe machines must name the selected recipe, and machine and spawner surface conditions must have matching location witnesses. Normal queries reuse the existing item placement index; bounded diagnostics reserve their cold visits separately. Research-gated construction or capture remains a later route rather than initial availability. Controlled lab and researchability fixtures exercise these decisions; native placement/capture, power, throughput, other trigger chains, script-created machines, catalogue changes and saved-world behavior remain separate qualification requirements.

Character crafting cannot supply a recipe with any declared fluid ingredient or result, including a fluid coproduct. This follows the [engine's manual-crafting boundary](https://wiki.factorio.com/Crafting). Selection checks typed entries, so an item sharing a fluid's name remains eligible for ordinary hand crafting. An acquired machine or an independent item-only producer may still supply the route, and a fluid route keeps its machine's research gate. Controlled fixtures exercise the actual lab and science-frontier consumers; they do not establish native production or saved-world migration.

Machine category and acquisition are also insufficient when the machine lacks the recipe's declared fluid ports. The existing query-local machine index counts `input`, `output` and `input-output` boxes once per prototype. A fluid route requires enough slots for its distinct fluid identities in each direction. Duplicate product entries do not invent another fluid identity. An item-only alternative can still supply the same lab or pack. These are necessary port checks, not a simulation of exact slot assignment, `fluidbox_index`, fluid filters, temperature, volume, pipe connectivity or logistics. The existing declared-machine callback retains its explicit caller-owned witness boundary. Controlled lab/researchability and source-epoch checks grant no new permission, owner, native production or save acceptance.

Minable acquisition follows the [native drop declaration](https://lua-api.factorio.com/latest/types/MinableProperties.html#result): an explicit `results` list replaces the singular `result` and `count`, including an empty list. A retained shorthand cannot create a second drop, turn a fluid into a placement item, or hide a valid item in the list. The shared source reader applies this precedence to resource, tree, plant and asteroid-chunk inputs. Controlled lab and researchability checks cover the resulting acquisition decisions and prototype immutability; actual mining, final catalogue, progression and saved-world qualification remain separate obligations.

On Factorio 0.15 and later, a positive [mining fluid amount](https://lua-api.factorio.com/latest/types/MinableProperties.html#fluid_amount) requires an acquisition witness for the exact typed `required_fluid`. The solver rejects a missing fluid identity or an unseeded mining/production cycle. It preserves an independently acquired fluid, an alternative producer, and research gates needed by a selected lab or recipe route. Such a conditional source cannot seed the boiler catalogue or become a reusable initial answer through a researched-fluid witness. Unconditional source preflights remain free of recipe-index construction; fluid-dependent sources resolve their input through the existing solver on demand. The 0.13 and 0.14 adapters ignore these later native fields. These necessary input checks do not certify mining-drill acquisition, native mining permissions, fluid delivery, production or saved-world behavior.

If a recipe-produced science pack has no valid unlocker, MIR removes that pack before final lab compatibility selection. It does not invent a gate or emit an unreachable technology. Packs produced through launch products, scripts, or other non-recipe systems remain eligible from active-lab evidence and may use a reachable same-named technology as their progression gate.

The `generated-prerequisite-safety` fixture reproduces the Factorio 0.17 `basic-mining` failure shape on the current line, verifies deterministic choice between multiple valid unlockers, checks the emitted prerequisite graph, and runs normal `research_all_technologies()` behavior in an isolated save.
