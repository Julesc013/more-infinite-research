---
title: "Library render-only capture fixture"
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

# Library render-only capture fixture

This test-only observer uses the shipped public `more-infinite-research-browser.open` interface and Factorio's renderer to capture all four tabs, both Settings scopes, Availability and a filtered Research list on exact2.1.24/MIR5.0.21016. Run English and German serially through the existing governed single-client owner with protected source copies, exact archive hashes, defaults and full restoration; no player source change is required. This fixture must never enter a player ZIP.

The same actor also admits exact2.0.77/MIR5.0.20016 using the distinct0.1.5 metadata in `info-f200.json`. Cross-edition, prior and other package tuples, including2.1.23 and all15 tuples, are refused. Both metadata files identify fixture0.1.5; governed staging must still bind the exact selected archive hash and distinguish the selected current archive from any same-version private build. The immutable0.1.4 actor remains at Git commit `2fd5d0fcfd1e4173284bbae8d61a8293d439977c`; host controls execute that retained actor to prove that it refuses both current16 tuples before it can open a page or request a screenshot. Both engines provide the consumed render APIs and Base public intro hooks; F200 native rendering remains a separate qualification obligation. The actor does not read or normalize technology-effect `hidden` fields.

Each page settles for180 ticks, then `game.take_screenshot` requests the real GUI with `show_gui=true`, `force_render=true` and no resolution override or downsampling. The page stays in place for60 further ticks; the final flush waits for screenshot writes. Per-page JSON records the actual numeric display scale, resolution, root location and style bounds. `complete.json` records requests, not visual acceptance: independently validate and inspect all seven real PNGs and bind their hashes to the exact package, engine, locale, seed and controller. Headless execution cannot produce this evidence. Keep the same scale and geometry throughout each session.

The observer compares the complete named native technology level/researched/enabled rows, recipe enabled rows, research queue/current/progress and robot-storage bonus before and after every page. It never synthesizes GUI events, imports MIR code, changes MIR storage/styles, starts research or writes a save. In the protected freeplay copy, it records the original intro flag and calls the installed Base scenario's public `freeplay.set_skip_intro(true)` hook before player creation; the normal cutscene then ends without opening the modal welcome dialog that would pause the tick-driven capture sequence. The original save is never written. Other changes are limited to test-observer storage and normal public personal-view state.

Capture begins after the initial cutscene controller ends naturally, so that its camera transition and normal GUI cleanup cannot interrupt an open Library page. This is additional render-only evidence. It does not establish real mouse/keyboard, resize, drag, close, native Startup settings-menu, export/file, disconnect/rejoin, protected save/reload, simultaneous-client or performance acceptance. The public interface cannot drive those controls. Preserve prior failed desktop captures and keep the separate acceptance cases open.
