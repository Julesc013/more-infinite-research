---
title: "Generated ID Reference"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-07
supersedes: ["schemas/stream-manifest.md"]
superseded_by: []
source_of_truth_for:
  - generated-ids
---

# Generated ID Reference

MIR 4.2.1 development also predeclares early `-1` and continuation `-4` identities for `research_material_nitric_acid`, `research_material_hydrochloric_acid`, `research_material_hydrofluoric_acid` and `research_material_glycerol`. These four Angel fluid families select only the retained named producers with the requested productive fluid result. The existing process, permission, ownership and progression gates still decide emission. Current native route admission, earned production, catalogue and save qualification remain pending.

Py's retained acid-gas and glycerol subjects use `research_material_py_acid_gas` and `research_material_py_glycerol`, each with separate `recipe-prod-<stream-key>-1` and `-4` identities. They do not reuse Angel glycerol's identity or acquire any sample/tree request. Exact producer selection and shared final-world admission decide emission; predeclaring these IDs grants no native qualification or permission exception.

The nine retained Py Earth sample keys are `research_material_py_earth_generic_sample`, `research_material_py_earth_sunflower_sample`, `research_material_py_earth_flower_sample`, `research_material_py_earth_shroom_sample`, `research_material_py_earth_tropical_tree_sample`, `research_material_py_earth_potato_sample`, `research_material_py_earth_jute_sample`, `research_material_py_earth_venus_fly_sample` and `research_material_py_earth_palmtree_sample`. Each predeclares `recipe-prod-<stream-key>-1` and `-4`, preserving the separate early and useful continuation stages. Py AlienLife must supply its exact item; the palm sample additionally requires Py HighTech. These identities do not qualify Angel plant-life samples or Py tree/seed/bootstrap routes. Permission, productive output, complete process safety, ownership and reachable science/labs still govern emission; native admission, production and save acceptance remain pending.

## Predeclared Automatic Family IDs

MIR 3.1.0 predeclares `mir-auto-prod-manufacturing-assembling-machine-1` and `mir-auto-prod-manufacturing-lab-1`. These IDs derive from stable semantic family names, never from mod or recipe names. Both are experimental in 3.1.5: they remain absent in the default attachment-only policy and in reviewed-data creation mode. The explicit broad opt-in policy may emit them after whole-plan validation. Predeclaration stabilizes identity; it does not assert that balance, grouping, or progression is accepted.

Generated recipe-productivity technologies use stable names:

```text
recipe-prod-<stream-key>-1
```

Generated base-technology continuations use the vanilla technology chain name and next level:

```text
<vanilla-technology-name>-<next-level>
```

Released generated IDs are save-facing API. Renames, removals, or stream target changes require migration review and release notes.

MIR 4.2.1 development predeclares `recipe-prod-research_material_rare_metals-4`, `recipe-prod-research_material_silicon-4`, `recipe-prod-research_material_glass-4`, `recipe-prod-research_material_black_paving-4` and `recipe-prod-research_material_white_paving-4`. Their existing `-1` identities retain levels one through three. The shared planner can emit a later stage only after the early route is admitted and MIR-owned, reachable science is selected, and a qualified recipe has useful productivity headroom. Imersite retains its separate exact-profile guard. These identity declarations do not establish current-package K2, K2SO, historical or SE qualification.

The machine-readable generated stream record remains `prototypes/mir/streams/generated_stream_manifest.json`. Base-chain identities are governed separately by `prototypes/mir/streams/generated_continuation_manifest.json`; each stable row binds a chain key, released identity pattern, and migration policy. Both records are routed through `.mir/streams.yml`.

Every stream key in the current legacy stream tables must have a manifest row. Most rows use the emitted `recipe-prod-<stream-key>-1` technology name as the manifest key. Compatibility policy streams may use a clearer stable `mir-prod-*` manifest key, but they still record the emitted Factorio technology name in `generated_technology`.
