---
title: "Library personal-view input observer"
status: current
applies_to: "MIR 5 qualification"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-16
supersedes: []
superseded_by: []
source_of_truth_for: []
---

# Library personal-view input observer

This passive test-only observer is bound only to Base2.1.24 and MIR5.0.21016. A governed native actor must supply real desktop input in this exact order: a `mir-research-browser` shortcut, a real query-field click, text that settles to `gear`, an actual GUI close such as Esc, then a second shortcut. The fixture never calls the Library remote interface, advances a fixture state machine, raises GUI events, reads MIR private storage or changes the GUI, research, queue or bonuses.

Event callbacks record only event facts and schedule the owned GUI-tree read for the following tick, after MIR's same-event handler has run. Text events may legitimately arrive as `g`, `ge`, `gea`, then `gear`; only the settled public query is required to be `gear`. The close callback never dereferences its possibly retired event element. The deferred close read verifies that the owned root has actually gone, and the deferred reopen read proves the retained `gear` query and exact root geometry.

The read-only report contains one sorted complete `[MIR_ACTIVE_MODS]` identity, bounded event counts, public root/query/tab/geometry snapshots and a before/after comparison of current research, progress, queue and worker-storage bonus. It is an input-observer prerequisite only. It does not establish desktop input delivery, visual correctness, settings-menu input, export, reload, multiplayer, client or release acceptance; those require the separately governed native case and its raw event/output evidence.
