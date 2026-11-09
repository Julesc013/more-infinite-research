---
title: "Ferrum worker storage native functional observer"
status: prepared
applies_to: "Exact full-Ferrum Factorio2.1.23/F21012, narrow2.0.77/F20012 counterpart"
audience: developer
doc_type: test-fixture
owner: mir-maintainers
last_reviewed: 2026-11-10
supersedes: []
superseded_by: []
---

# Ferrum worker storage native functional observer

This is a scenario-level observer for a future governed native assignment. Host controls prove its acceptance/refusal behavior, not genuine research, consumption, save continuity or gameplay. It imports no MIR code or private runtime storage. Physical robot inventory/cargo/delivery is explicitly unperformed; a force carrying-capacity scalar is not that witness.

Install `control.lua` only as the scenario `__level__` actor, using the same embedded actor bytes across source, destination and cold reloads. Do not put it in a mod `control.lua`: its `on_configuration_changed` entry observation must run before MIR's configuration callback. It records `level-pre-MIR-configuration` before comparing protected source frames, then separately records/checks `post-MIR-configuration` on the first tick after all configuration callbacks. An engine entry difference remains visible and refuses; the observer does not silently reinterpret it as a MIR change.

The separate tiny data-only lab mod contains `lab-source/data.lua` and the selected metadata as `info.json`. F210 uses `lab-source/info.json`; F200 uses `lab-source/info-f200.json`. It defines a void-energy laboratory at speed1001, two effect-free unrelated-work sentinels, and one hidden/disabled/effect-free calibration technology. It never changes an existing technology, setting, cost, time, effect, science pack or laboratory prototype. The custom lab initially accepts space science but omits robotics science: actual Ferrum must append robotics once through its own final lab patch. Runtime checks require actual acceptance of all seven expected worker packs.

## Exact selected inputs

| Role | Factorio | Ferrum | PlanetsLib | Spider launcher | MIR |
|---|---|---|---|---|---|
| F210 source / destination | 2.1.23 | 0.1.5 | 2.4.0 | 2.9.87 | absent / 5.0.21012 |
| F200 source / destination | 2.0.77 | 0.0.5 | 1.18.0 | 2.9.86 | absent / 5.0.20012 |

Both roles include the exact matching Base, Space Age, Quality and Elevated Rails versions, the lab mod0.1.0, and ActiveMods observer0.1.0. F210 also includes Recycler2.1.23. All other active mods refuse. Keep the same lab/observer/provider bytes and versions across each source/destination pair. Root owns exact archive/engine hashes, direct-library leases, real composition, resource admission, actor packaging and execution. No archive is built by the host controls.

## Independent native obligations

Source administrative setup recursively researches only the finite4 prerequisite roots and the electromagnetic-science prerequisite. It labels every resulting scripted event separately and rejects any scripted4/5/6 grant. Native1–3 must supply the initial capacity3. Ferrum4 and5 must then each complete once through the actual laboratory with `by_script=false`, observed intermediate progress and exact supplied-item depletion. Their independent contracts are675/1012 units,60seconds, storage effect1, and the five native packs plus Ferrum robotics. No level setter is used to obtain these completions.

After those earnings, the source preserves native capacity5 and scripted continuity sentinels: player current/ordered unrelated work at.375 with detached.27; a separate uninvested foreign force retains its disabled finite4 flag, current.42 and detached.27. These partials are explicitly scripted continuity witnesses, not lab-earned work. Source native rows, effects, creators, evaluated counts, full science vectors, prerequisites, flags and queue/progress are snapshotted before saving.

The first MIR addition must preserve that source frame and introduce only the admitted empty native rows. Public6 must retain `1518.75*1.5^(L-6)`,60seconds, effect1, all seven packs including robotics/electromagnetic, and the exact declared prerequisite set. Private4 must retain the full authored default contract `675*1.5^(L-4)`, six default packs and no investment; a dummy holder or public7 overlap refuses. F200's absent modifier `hidden` member remains absent in observations; F210 requires its documented Boolean representation.

The fractional count is not rounded in fixture Lua. The never-researched calibration row has literal constant `count_formula="1518.75"`, matching the independently specified formula value at level6. At map multiplier1, public6's native `research_unit_count` must equal the independent engine calibration integer. Both raw values are recorded. This qualifies only that level/multiplier comparison, not all cost levels or alternate settings.

The destination temporarily researches only public6 in the player force, requires one ordinary completion and exact item consumption, then restores the source's unrelated ordered queue/current/detached work after the final queue assignment. Capacity must increase from5 to6. All finite source rows, foreign frames, private investment/flags and unrelated work remain exact. Every completion stops the lab; subsequent queue work waits until a later tick. Both native infinite representations (completed6 or advanced7) identify the same single earned level without a setter.

## Four-process dispatch contract per family

1. Source server: `--start-server-load-scenario <owned-scenario>` under the exact provider-only selection. Require ordinary4/5 markers, `source-saved`, and the closed `mir-ferrum-worker-source.zip`.
2. Destination server: load a distinct copy of that protected source with only exact MIR12 added. Require both configuration observations, one ordinary6 completion, restored native frames, `destination-saved`, and closed `mir-ferrum-worker-destination.zip`.
3. First cold: use a distinct read-only one-update engine load of the exact protected destination, require one `cold` marker and natural success, and verify the ZIP remains byte-identical.
4. Second cold: a separate process repeats the same immutable one-update check. The actor has no persisted cold counter and must not save or mutate state on either cold.

Use the retained post-transition caller/kernel pattern:4096MiB,180seconds per process,64MiB per stage; direct-library selection/owned-archive custody and shared live-log reader; named completion marker plus save-log/closed-ZIP predicate; exact saved actor CRC/hash; save/input hashes before/after each load; native-fatal/output checks; restoration of every original control/archive and Factorio-zero receipt. Exit0 or benchmark expiry alone is insufficient. These are future controller obligations, not commands dispatched by this fixture unit.

The private read-only interface `mir-ferrum-worker-storage-native.report` exposes bounded phase/frames/counts. It never starts research or repairs state. Source, entry, after-MIR and cold markers use `[MIR_FERRUM_WORKER_NATIVE]`. Unknown phase/version/science/count/provenance/state refuses; preserve adverse bodies and diagnose before any new actor version or retry. Full Ferrum gameplay/save/cold and physical delivery remain pending actual execution and independent review.
