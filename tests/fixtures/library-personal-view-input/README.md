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

This passive test-only observer0.1.5 is bound only to Base2.1.24 and MIR5.0.21016. A governed native actor must supply real desktop input in this exact order: a `mir-research-browser` shortcut, a real Help-tab selection, a real Research-tab selection, a real query-field click, text that settles to `gear`, an actual GUI close such as Esc, then a second shortcut. The fixture never calls the Library remote interface, advances a fixture state machine, raises GUI events, reads MIR private storage or changes the GUI, research, queue or bonuses.

Event callbacks record only event facts and schedule the owned GUI-tree read for the following tick, after MIR's same-event handler has run. Text events may legitimately arrive as `g`, `ge`, `gea`, then `gear`; only the settled public query is required to be `gear`. The close callback never dereferences its possibly retired event element. The deferred Help and Research reads require actual selected indexes4 then1 and retain the public tabbed-pane name, type, available readable minimum/maximum style fields and root geometry. The initial Open, Help, Research and query reads require the same live tabbed-pane index; the close/reopen read records a new valid index and compares only geometry and structural style because the closed GUI is legitimately reconstructed. Individual tab-child pixels are not a Factorio GUI API witness, so the fixture records no invented child bounds. It never reads LuaStyle `width` or `height`, which are write-only in Factorio2.1.24; absent or automatic readable style fields remain recorded as `nil` or zero.

After every deferred snapshot, the observer writes one immutable numbered JSON phase receipt below `script-output/mir-library-personal-view-input/`. The receipt binds the complete active-mod table, phase, bounded actual event log, that snapshot and all prior snapshots. The final `08-reopen.json` marks the sequence complete. This is the governed Linux actor's polling surface; it must not synthesize a fixture remote call.

The external actor waits for `01-initial.json` before sending the MIR shortcut. A load may reach the observer without a usable join callback, so while it is still awaiting an entry event the observer begins only when exactly one valid connected player is present on a tick; it records that factual origin as `singleplayer-load`. Zero or multiple players do nothing. A real join keeps its separate `joined` origin and phase guard; the retained configuration-change load recorded that actual callback before the fallback ran. Readers must accept either sole first origin without inventing or rewriting an event. The observer withholds the receipt while the player is in the normal Base cutscene or any GUI remains opened, up to1800 ticks, and records the usable non-cutscene controller identity in it. If the normal Base welcome requires real dismissal, the actor may send only the matching ordinary desktop input, including Tab when the displayed prompt asks for it. The actor records setup input separately; any bounded pre-shortcut unrelated GUI click, tab, text and close facts are recorded as `setup-*` and never count as MIR input. Once the first MIR shortcut is observed, all subsequent MIR event ordering is strict. The fixture does not call Base `freeplay.set_skip_intro`, change a save or otherwise suppress setup UI.

An observed GUI event and its deferred public-state snapshot do not prove that an external device capture has repainted. The [retained personal-input adverses](../../../spec/evidence/library516-linux-personal-input-adverses-r01.json) include valid event/state observations whose Help/Research PNGs show the preceding view. Keep that failed pipeline and visual association failure distinct from the separately reviewed state reader; require an independent phase-to-visible-state comparison after any capture-timing correction.

The read-only report contains one sorted complete `[MIR_ACTIVE_MODS]` identity, bounded event counts, public root/query/tab/geometry snapshots and a before/after comparison of current research, progress, queue and worker-storage bonus. It is an input-observer prerequisite only. It does not establish desktop input delivery, visual correctness, settings-menu input, export, reload, multiplayer, client or release acceptance; those require the separately governed native case and its raw event/output evidence.
