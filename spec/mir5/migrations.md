---
title: "Save continuity and migration"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-migrations-specification
---

# Save continuity and migration

`MIG-01` — Preserve historical prototype/setting IDs, level boundaries, effective native effects, hidden carriers and relevant persistent state before attempting runtime recovery. Same ID alone is insufficient if effect values, targets or starting levels change.

A data-stage generator cannot inspect the player's save. Runtime code cannot reliably reconstruct state already discarded by engine loading. Missing a required historical technology must not be treated like an absent optional new addition. [Lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html)

## Baseline and upgrade paths

The principal predecessor is the exact published 4.7 package for the same engine family. Preserve prior release variants by their hashes where relevant; version text alone does not identify previously reissued bytes. Distinct older upgrade boundaries retain their previously promised scope or receive an explicit documented bridge decision. Never recommend downgrade as the automatic inverse of upgrade.

Private incomplete slices use disposable worlds only. Do not load and resave a real full MIR factory with a one-technology replacement package. Full-save migration qualification starts only after all relevant definitions and runtime bridges exist.

## Migrations themselves

`MIG-02` — Inventory existing JSON/Lua migrations by filename, purpose, required predecessor and imports. Factorio remembers applied names and runs JSON before Lua migrations. Do not rename filenames mechanically during repository cleanup. Decouple required historical logic from retired imports without retaining a whole old subsystem. [Migrations](https://lua-api.factorio.com/latest/auxiliary/migrations.html)

Small state transformations are idempotent. Keep the existing storage/global namespace and contribution baselines where necessary. Do not reset every force/technology, clear `mir` storage or grant invented levels to repair an unexplained failure. Writing native `level`/`researched` can itself change benefits/enablement; test effective state. [LuaTechnology](https://lua-api.factorio.com/latest/classes/LuaTechnology.html)

## Independent observation

Capture the earliest accessible loaded state before MIR compensation, then after migration and ordinary lifecycle handling. Compare completed/next levels; science/cost/effect semantics; native owner contributions; hidden carriers; queue/current research; saved progress; configured caps; disablement ownership; runtime multipliers; settings and unrelated force data.

`MIG-03` — Acceptance is original immutable save → candidate upgrade → saved candidate → independent cold reload → second cold reload, plus actual multiplayer lifecycle where affected. Same binary and upstream closures must be retained or any deliberately changed boundary isolated. State disappearance before callbacks is a failure to diagnose, not a fixture value to overwrite.

Required opponents include levels 0/2/3/7 around staged continuations; finite-at-cap and earned-above-cap; 42% partial investment where existing fixtures use it; native powder/crystal separation; unrelated scripted offset sentinels; mod removal/readdition; optional feature disable cleanup; force merges/resets; library state reconstruction.

## Cleanup is not history erasure

Delete retired implementation after obligations are recovered and replacement acceptance exists. Keep small active regression fixtures and source/hash pointers that still test current continuity. Old release branches/tags hold old design documents. Old migration filenames, real compatibility aliases, copyright and changelog entries are **live obligations**, not confusing architecture remnants to be renamed blindly.

## Determinism does not replace migration qualification

`MIG-04` — The migration input includes the save's applied migration-name history, not just its research levels. Equal complete input must yield equal output. An exactly-once engine migration and an idempotent reconciliation function have different tests. Never reset migration history as a shortcut.

Do not open and save a real full-catalogue world with a one-family experimental package. Early slices use disposable fixtures. A preserved prototype ID with changed effect recipes, initial level or per-level scalar may still lose meaning; compare the earned native/physical outcome, not only names. See [determinism](determinism.md).
