---
title: "Library render-only capture fixture"
status: current
applies_to: "MIR 5 qualification"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-10
supersedes: []
superseded_by: []
source_of_truth_for: []
---

# Library render-only capture fixture

This test-only observer uses the shipped public `more-infinite-research-browser.open` interface and Factorio's renderer to capture all four tabs, both Settings scopes, Availability and a filtered Research list on exact2.1.23/MIR5.0.21012. Run English and German serially through the existing governed single-client owner with protected source copies, exact archive hashes, defaults and full restoration; no player source change is required. This fixture must never enter a player ZIP.

Each page settles for180 ticks, then `game.take_screenshot` requests the real GUI with `show_gui=true`, `force_render=true` and no resolution override or downsampling. The page stays in place for60 further ticks; the final flush waits for screenshot writes. Per-page JSON records the actual numeric display scale, resolution, root location and style bounds. `complete.json` records requests, not visual acceptance: independently validate and inspect all seven real PNGs and bind their hashes to the exact package, engine, locale, seed and controller. Headless execution cannot produce this evidence. Keep the same scale and geometry throughout each session.

The observer compares the complete named native technology level/researched/enabled rows, recipe enabled rows, research queue/current/progress and robot-storage bonus before and after every page. It never synthesizes GUI events, imports MIR code, changes MIR storage/styles, starts research or writes a save. Only test-observer storage and normal public personal-view state are changed.

This is additional render-only evidence. It does not establish real mouse/keyboard, resize, drag, close, native Startup settings-menu, export/file, disconnect/rejoin, protected save/reload, simultaneous-client or performance acceptance. The public interface cannot drive those controls. Preserve prior failed desktop captures and keep the separate acceptance cases open.
