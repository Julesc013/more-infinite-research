---
title: Localized Library search native observer
---

This passive Linux-only observer records the real German localized-search sequence from the accepted fresh R09 save. It is a candidate input observer, not native acceptance evidence.

The actor must first observe the retained open Library window and mining-drill query, then supply only real desktop input: Escape, shortcut, Help click, Research click, query click, Ctrl+A, Backspace, the ASCII text `Eisenzahnrad`, Escape and shortcut. The observer records delivered event facts immediately and takes each owned GUI/native snapshot on the next tick.

Closing requires the owned root to be retired, `player.opened` to be empty, a live connected character controller, and the unchanged native research frame. The bounded tick observer can detect that public state while awaiting either of the two closes, even when this fixture receives no close callback. It records `close_observation.event_received=false` and leaves the actual close-event counter/log unchanged; it never manufactures an event. A delivered callback still cannot substitute for the required retired state. The caller retains the real input and before/after captures separately.

This distinction follows the retained actual localized-search R03 diagnostic: one Escape request visibly retired the Library, while the passive fixture produced no close phase. The exact reason this observer missed a callback remains unverified. Factorio's [event contract](https://lua-api.factorio.com/latest/events.html#on_gui_closed) and [staff clarification](https://forums.factorio.com/viewtopic.php?t=115401) also identify cases where close events are unavailable; querying public open state is distinct from assuming every disappearance delivers an event. This is a fixture correction, not a player focus change or a native acceptance result.

Each Help or Research transition requires exactly one owned tab-selection fact and one owned tab-click fact before its snapshot; their callback order is intentionally not treated as a product contract. Retained Factorio 2.1.24 R03 evidence happened to record selection then click on the same tick, while the host control also covers the other ordering as an immaterial event delivery variation.

It writes ten bounded JSON phase files beneath `script-output/mir-library-localized-search-native/`: `00-initial`, `01-setup-closed`, `02-open`, `03-help-tab`, `04-research-tab`, `05-query-click`, `06-cleared`, `07-localized-query`, `08-closed` and `09-reopen`. The localized-query and reopen phases both require the one public result item `[img=technology/recipe-prod-research_gears-1] Eisenzahnrad-Produktivität`.

The exact active selection is Base 2.1.24, MIR 5.0.21017, this observer 0.1.1, API Alpha 0.1.0, API Beta 0.1.0 and the active-mods observer 0.1.0. The only connected client observed by this fixture is `MIR5Deutsch` after its locale is `de`.

No remote action, GUI setter, synthetic event, private MIR state access, research mutation or save operation is permitted. Existing historical and personal-view observer fixtures remain separate inputs.
