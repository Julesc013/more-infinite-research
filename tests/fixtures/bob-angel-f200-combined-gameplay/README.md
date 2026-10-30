---
title: "F200 combined steel gameplay fixture"
status: prepared
applies_to: "MIR 5 F200 combined Space Age/BobTech/Angel Defaults selection"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-31
supersedes: []
superseded_by: []
source_of_truth_for:
  - f200-combined-steel-gameplay-fixture
---

# F200 combined steel gameplay fixture

- Scope: one disposable F200 2.0.77 Defaults-mode gameplay witness for the recognised Space Age plus BobTech Bob/Angel closure. It is narrower than the exact 69-row/28-private-carrier/875-setting F200 data admission and establishes no catalogue, migration, multiplayer, ordinary-cost, menu-performance, or release result.

- Independent inputs: the complete published `recipe-prod-research_steel-1` row is `tests/fixtures/bob-angel-f200-combined-published-473-expectations.json.gz` (`B80EDB79ABE75F3A19A3D7BD2B9CAB43343807D405C9E474E93219D542EDE633`): level one, two automation/logistic prerequisites, `8000*2^(L-1)` at 60 seconds, and two `0.10` effects on `angels-plate-steel` and `angels-plate-steel-2`. Factorio exposes that authored 60-second unit as runtime `research_unit_energy = 3600` ticks. The NoMIR upstream context is `tests/fixtures/bob-angel-f200-combined-upstream-context.json.gz` (`C5B76C07B66A305099412E2BDBD63855234692C9D5DFF32B3351D0A100A75C7D`), derived from EAD7 `control-without-mir` raw data (`AD702CC98FA30A672C8A358305D0F562A5965E51F28CED8D0EFC8ABD26F5F487`), including the `angels-steel-smelting-2` owner, its roll/plate unlocks, and the unchanged one-roll-to-four-plate advanced-crafting route.

- Research: only `automation-science-pack`, `logistic-science-pack`, and `angels-steel-smelting-2` are seeded as named upstream prerequisites. The fixture normally queues the MIR technology with `force.add_research`; it never directly sets its researched, level, progress, or enabled state, and never assigns `recipe.enabled`. A real 100-Biolab farm requires the native 50% drain, four module slots, quality-module support, normal entity quality, pressure-1000 surface condition, and both accepted science packs; native completion of that queue consumes 4,000 automation and 4,000 logistic packs. `game.speed = 16` only bounds this disposable test world; the native count and time remain the published values.

- Physical/save witness: after the real `on_research_finished` event advances the infinite row from level one to two, an unchanged module-free `assembling-machine-1` runs exactly 100 `angels-roll-steel` through the real route. The fixture drains output and requires exactly 440 `steel-plate` and native route bonus `0.10`; the separate entity modifier remains zero. Remaining productivity credit must equal `100 * native_recipe_bonus - (440 / 4 - 100)` within the existing comparator, preserving the recipe getter's float precision rather than assuming an exact decimal. Initial and reload markers retain raw recipe/entity/progress values and the derived credit. It saves `mir5-native-complete` once; each later cold process reads the completed storage witness on load, then on its first tick independently compares native research/science/machine/physical-output state before writing only a reload marker. Labs are frozen only during the initial transition; cold checks make no lab-energy assignments.

- Deferred Library scope: the read-only `mir5-bob-angel-f200-combined-gameplay/report` interface leaves a later EN/DE Library stage pending. That stage must use the existing public owned-Library method on this saved closure, retain fresh client screenshots/query/role/native-state observations, and perform no fixture-simulated input. This fixture makes no Base or Space Age Library result claim.
