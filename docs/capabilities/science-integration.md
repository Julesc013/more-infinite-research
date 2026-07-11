---
title: "Science Integration Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: []
---

# Science Integration Capability

Science integration decides when active science packs participate in generated research costs or science-pack productivity. Lab compatibility remains the hard gate.

Science ingredients and progression prerequisites are separate decisions. MIR adds no prerequisite when any visible recipe producing the pack is already enabled in every declared recipe difficulty. When pack production requires a recipe unlock, candidates must:

- exist and remain enabled in the final prototype graph;
- actually unlock a recipe producing the selected pack;
- have enabled, existing, acyclic prerequisite ancestry;
- be selected deterministically by technology prototype name.

Hidden technologies are not rejected merely for being hidden. A hidden implementation technology can remain a valid gate when it is enabled, researchable, and recipe-proven. Disabled tutorial, campaign, scenario, debug, or deprecated technologies are not valid inferred freeplay gates.

If a recipe-produced science pack has no valid unlocker, MIR removes that pack before final lab compatibility selection. It does not invent a gate or emit an unreachable technology. Packs produced through launch products, scripts, or other non-recipe systems remain eligible from active-lab evidence and may use a reachable same-named technology as their progression gate.

The `generated-prerequisite-safety` fixture reproduces the Factorio 0.17 `basic-mining` failure shape on the current line, verifies deterministic choice between multiple valid unlockers, checks the emitted prerequisite graph, and runs normal `research_all_technologies()` behavior in an isolated save.
