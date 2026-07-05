# Factorio 1.1 RC Planning Report

Updated: 2026-07-06
Branch: `tmp/1.1`
Target Factorio line: `1.1.x`
Prototype snapshot reviewed: `wube/factorio-data` tag `1.1.110`
Planned MIR release slot(s): `1.8.8, 1.8.9`
Risk rating: High
Change type in this commit: documentation and planning only; no code behavior changes.

This is a tentative maintainer-authorized planning note for the temporary experimental branch. It does not make this branch a release candidate by itself. A stable RC for Factorio `1.1` still requires target-line code edits, metadata edits, package construction, and a load test against a matching Factorio binary. If those gates fail, the plan must change rather than shipping a misleading archive.

## Evidence Reviewed

- Official API version index: https://lua-api.factorio.com/
- Mod structure and single-major compatibility rule: https://lua-api.factorio.com/latest/auxiliary/mod-structure.html
- Storage/global runtime split: https://lua-api.factorio.com/latest/auxiliary/storage.html
- Wube factorio-data prototype snapshots and release tags: https://github.com/wube/factorio-data
- FFF #127 source-generated versioned Lua API docs: https://www.factorio.com/blog/post/fff-127
- FFF #141 Mod Portal/licensing/determinism context: https://www.factorio.com/blog/post/fff-141
- FFF #153 0.13 stable / 0.14 experimental modding context: https://www.factorio.com/blog/post/fff-153
- FFF #217 continuing Lua API additions in the 0.16 era: https://www.factorio.com/blog/post/fff-217
- FFF #348 1.0 GUI/style/icon mod-breaking context: https://www.factorio.com/blog/post/fff-348
- FFF #363 1.1 technology/effect icon and breaking-change context: https://www.factorio.com/blog/post/fff-363

## API And Prototype Findings

API status: Full official 1.1.110 prototype/runtime docs and JSON were available.

Science-pack surface observed for the target: modern 1.1 science pack names: automation, logistic, military, chemical, production, utility, space.

- 1.1.110 supports max_level/count_formula continuation fields.
- 1.1.110 has laboratory-productivity, mining-drill productivity, worker robot battery, stack inserter capacity, gun/ammo/turret/toolbelt, inventory and trash modifiers.
- 1.1.110 does not have change-recipe-productivity, bulk-inserter-capacity-bonus, cargo modifiers, tower events, or Space Age families.
- 1.1 runtime uses pre-2.0 global rather than storage.

## Current MIR Code Surfaces That Do Not Backport Cleanly

The current branch began as the Factorio `2.1` development snapshot. The following surfaces must be treated as blockers or explicit exclusions before any stable RC claim:

- Remove all recipe-productivity streams or replace with a separately proven 1.1 design.
- Remove Space Age, Quality, recycler, elevated-rails, spoilage, agriculture, cargo, tower event, and storage-only assumptions.
- Rename/guard bulk-inserter references back to stack-inserter.
- Keep only direct native modifiers and base-tech continuations proven in 1.1.110.
- Port control code to global or omit runtime scripted features for RC.

## Minimum RC Plan

- Use 1.1 as the first older-line proving branch because it still has modern science names and infinite fields.
- Ship a reduced feature set: base extensions plus safe native direct effects.
- State recipe productivity and Space Age exclusions in release notes.

## Stable RC Readiness

Status: not ready.

This branch is suitable as an experimental planning branch only. The present source tree should not be packaged as a Factorio `1.1` RC by changing metadata alone. The RC threshold is a target-specific compatibility patch with unsupported technology modifiers removed, target science packs resolved, locale/package structure verified, and the package loaded by a matching Factorio `1.1.x` executable.

## Implementation Non-Goals For The First RC

- Do not promise full feature parity with the current Factorio `2.1` line.
- Do not ship any technology effect whose exact modifier name is not proven for Factorio `1.1`.
- Do not keep Space Age, Quality, recycler, elevated-rails, cargo, spoilage, agriculture, or recipe-productivity behavior on older lines unless that exact line has proof.
- Do not add broad runtime scans or compatibility shims just to imitate missing native modifiers.
- Do not tag a release from this temporary branch until the docs, todo, changelog, package, and validation evidence all agree.

## RC Validation Gates

- [ ] Run git status and diff checks before implementation.
- [ ] Build a target-line package only after metadata, dependencies, locale, and prototype shape are patched.
- [ ] Load the package in a matching Factorio 1.1.x binary; if unavailable, release notes must say validation was not run.
- [ ] Record exact source snapshot, binary version, load result, and exclusions before tagging.
- [ ] Do not publish from this temporary branch until blockers are closed or publicly deferred.

## Branch TODO Extract

- [ ] Select the exact MIR 2.x.x source snapshot for planned releases 1.8.8, 1.8.9.
- [ ] Create a target-line API/effect whitelist from official docs where available and factorio-data 1.1.110.
- [ ] Patch info.json factorio_version, version, dependencies, and optional-mod ordering for Factorio 1.1.
- [ ] Prune unsupported current-line streams before package validation.
- [ ] Write release notes that state the supported subset and excluded current-line features.
- [ ] Run a matching Factorio 1.1.x binary load test before RC approval.
- [ ] Create a 1.1 effect whitelist from official JSON.
- [ ] Decide whether scripted runtime features are omitted or ported to global.