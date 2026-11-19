---
title: "K2SO material continuation fixture"
status: prepared
audience: developer
doc_type: reference
---

# K2SO material continuation

This disposable four-stage fixture checks published 5.0.21017 finite material research upgrading to the corrected 5.0.21018 continuations, then a finite cap and relaxation. It is not a player recovery command. The old `materials` fixture and its accelerated historical save remain unchanged and are not an ordinary-cost predecessor for this sequence.

All stages use the exact declared Factorio 2.1.24 / K2SO selection. The three ordinary material costs, research times, rewards and production recipes are never changed. The actor grants only its named native prerequisites as setup; those script completions are recorded separately and cannot count as laboratory research. It never assigns selected material levels, research progress, native bonuses or MIR storage, and never calls a MIR handler.

The final K2SO science policy removes early science when space science is present. Consequently, the candidate continuations consume white science alone. The fixture checks the final technology rows and the existence of an accepting original lab before creating its own accelerated electric lab in `data-final-fixes.lua`. Its private widened lab inputs cannot affect MIR's earlier science reduction. Only the private lab speed is accelerated; its actual electrical buffer is filled while working. This establishes paid science and effects, not ordinary elapsed time or production of science packs.

| Stage | Required observation |
| --- | --- |
| `source`, actor 0.1.0, published 5.0.21017, maximum 0 | All three level-four identities are absent. Real labs earn nine finite levels at unchanged counts 200/400/800 and time 30, consuming 4200 automation, 4200 logistic and 2800 chemical packs. The four recipe bonuses reach 6%. A separate force retains unearned disabled material research. |
| `upgrade`, actor 0.2.0, corrected 5.0.21018, maximum 0 | Configuration entry preserves the finite paid state before fixture setup. All three new level-four continuations complete ordinarily at 1600 white packs each, reaching 8% and next level 5. Another 360 white packs produce genuine 20% work on silicon level 5, with two silicon queue entries followed by the fixture probe. New foreign continuation identities are deliberately disabled before the cap transition. |
| `finite`, actor 0.3.0, same candidate, maximum 3 | MIR's configuration callback cancels only the two forbidden silicon queue entries, retaining 20% on silicon's native saved progress and the eligible probe's own progress and order. All earned levels and 8% bonuses survive above cap. The foreign unearned level-four continuations remain disabled and cannot acquire an enablement restoration right. |
| `relaxed`, actor 0.4.0, same candidate, maximum 0 | Only the player's MIR-owned disablements restore. The eligible probe is retained; cancelled intentions are not automatically re-enqueued. Explicit ordinary queue additions resume silicon level 5 for the remaining 1440 white packs, then complete level 6 for 2000 more. The probe costs 20 automation packs. Silicon reaches 12%, the other recipes remain at 8%, and foreign state matches the original uncapped frame. |

Every endpoint requires at least two elapsed ticks after its final observation, a closed `mir5-native-complete` server save, and the standard runner's two independent one-update cold reloads. Cold checks compare complete tracked technology levels, researched/enabled/visible flags, native saved work, recipe bonuses, queue/current progress, science budgets and stopped lab. `on_load` only changes local observation flags.

Source preparation uses the explicit native prerequisites `automation-science-pack`, `logistic-science-pack`, `chemical-science-pack`, `kr-rare-metal-processing`, `kr-enriched-ores`, `kr-silicon-processing`, `kr-stone-processing` and `space-science-pack`. The unrelated fixture probe is a new effect-free technology costing 20 automation packs at time 30. Foreign disablements are deliberate opposing setup, never described as paid history. All selected paid levels and unfinished material work are earned in real labs.

Materialize each stage's five wrappers together with the two shared Lua files as one seven-member archive. The four profiles select source/upgrade/finite/relaxed actor versions. Pass each protected predecessor through the existing `InputSavePath` / `ExpectedInputSaveSha256` protocol; do not reuse a mutable working save as custody. The existing runner supplies four processes for the fresh source and three for each successor, thirteen serial processes total. Root freezes actual engine, archive, observer, source and save hashes in the prepared command record before dispatch; this source contains no invented artifact hashes.

Host controls may exercise the actor with explicit supplied native frames and ordinary-completion callbacks. They are fixture controls, not a simulated Factorio acceptance result. An old-package absent-tail witness, fresh corrected progression, paid upgrade, cap cancellation, save persistence and reporter reproduction retain separate verdicts. This sequence does not qualify physical manufacturing output, arbitrary K2/SE profiles, multiplayer, mining, worker-history reports or whole-product release readiness.
