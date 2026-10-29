---
title: Large-factory diagnostic activity observer
status: current
applies_to: Pinned F200 and F210 diagnostic inputs
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-30
supersedes: []
superseded_by: []
source_of_truth_for:
  - large-factory-activity-fixture
---

# Large-factory diagnostic activity observer

This test-only observer measures actual production and sampled crafting completions on an existing disposable world over exactly 600 ticks per initialization/configuration/load activation. Each activation clears local observations and arms one new window; after completion it remains inactive until another activation. It is not limited to one window over the fixture's entire save lifetime. Compose `control.lua` and the selected `info-f200.json` or `info-f210.json` renamed to `info.json`; no data/settings stages, player source, research, entity, inventory or settings writes are included. The pinned engines are 2.0.77 and 2.1.23. The existing native runner owns archives, copied input saves, process admission, logs and restoration.

The first update after initialization/configuration/load captures player-force counts for nine native entity types, cumulative production for fifteen named normal-quality items, and `products_finished` for up to 256 assembling machines/furnaces per initial surface. It observes at most 32 surfaces and 128 active mods, with a 64 KiB final report bound. Exactly600 ticks later it reports native counter deltas, productive/invalidated sampled machines, counter decreases and surface count changes, then unregisters its update callback and releases all local object references. It never writes persistent storage or saves a world. Load/configuration callbacks only reconnect local registration; actual observations wait for an update where game access is legal.

The native engine log contains one `[MIR5_LARGE_FACTORY_ACTIVITY] START` and one `COMPLETE` JSON row per completed window. Retain the exact log, selection, source save, fixture payload/container and actual settings with the existing launcher. An incomplete window supplies no completion. Counter decreases and invalidated objects remain visible; `is_crafting` alone is deliberately unused because a started craft need not make progress. Production deltas cover normal quality only; the bounded machine sample can witness other qualities but is neither random nor a whole-factory estimate. A zero observation does not prove universal inactivity.

`activity_observed` states whether at least one sampled completion or positive selected production delta occurred. `large_factory_qualified`, performance and release verdicts remain false: independent review must assess the actual scale/useful work and input applicability. A large idle map must not gain an active-factory claim from entity count or completed benchmark ticks alone. Keep this diagnostic observer out of ordinary acceptance timing, and do not subtract its overhead from a scored result. The original sanitized aggregate admission remains unchanged; this fixture does not add percentiles, stall attribution, a whole-modpack settings backup or native-state preservation proof.

Adding this observer to the existing governed diagnostic path needs a separately frozen exact selection and verified own archive/source members. Do not insert it into an active timing block or relabel a profile containing the data-stage active-mod observer as this runtime observer. Source settings and any removed/updated upstream mods retain their actual declared limits; this fixture grants no configuration or save support authority.
