---
title: "Factorio 2.0 RC Planning Report"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# Factorio 2.0 RC Planning Report

Updated: 2026-07-06 Branch: `tmp/2.0` Target Factorio line: `2.0.x` Prototype snapshot reviewed: `wube/factorio-data` tag `2.0.77` Planned MIR release slot(s): `1.9.7, 1.9.8, 1.9.9` Risk rating: Moderate Change type in this commit: documentation and planning only; no code behavior changes.

This is a tentative maintainer-authorized planning note for the temporary experimental branch. It does not make this branch a release candidate by itself. A stable RC for Factorio `2.0` still requires target-line code edits, metadata edits, package construction, and a load test against a matching Factorio binary. If those gates fail, the plan must change rather than shipping a misleading archive.

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

API status: Full official 2.0.77 prototype/runtime docs and JSON were available.

Science-pack surface observed for the target: automation/logistic/military/chemical/production/utility/space science, plus Space Age packs requiring exact 2.0.77 add-on proof.

- 2.0.77 has max_level/count_formula and the modern prototype stage.
- 2.0.77 has change-recipe-productivity, laboratory-productivity, cargo-landing-pad-count, bulk-inserter-capacity-bonus, character inventory/trash modifiers, and on_tower_planted_seed.
- 2.0.77 JSON did not contain max-cargo-bay-unloading-distance, so that stream must be removed or guarded unless later proof exists.
- RecipePrototype exposes additional_categories and category; current helper checks categories/category and needs recheck.

## Current MIR Code Surfaces That Do Not Backport Cleanly

The current branch began as the Factorio `2.1` development snapshot. The following surfaces must be treated as blockers or explicit exclusions before any stable RC claim:

- Downgrade info.json from 2.1 to 2.0 and remove 2.1.8 dependency floors.
- Audit Space Age, Quality, recycler, and elevated-rails IDs against factorio-data 2.0.77.
- Remove or guard research_cargo_bay_unloading_distance.
- Keep change-recipe-productivity only after a full 2.0.77 load and recipe-category audit.
- Run the legacy 2.0 validation profile against a real 2.0.x binary.

## Minimum RC Plan

- Create a narrow compatibility patch from the selected MIR 2.x.x snapshot.
- Apply metadata/dependency downgrade first, then remove proven 2.1-only surfaces.
- Use official 2.0.77 JSON and factorio-data 2.0.77 as the contract.
- Treat this as the future stable legacy development branch after the temporary campaign.

## Stable RC Readiness

Status: not ready.

This branch is suitable as an experimental planning branch only. The present source tree should not be packaged as a Factorio `2.0` RC by changing metadata alone. The RC threshold is a target-specific compatibility patch with unsupported technology modifiers removed, target science packs resolved, locale/package structure verified, and the package loaded by a matching Factorio `2.0.x` executable.

## Implementation Non-Goals For The First RC

- Do not promise full feature parity with the current Factorio `2.1` line.
- Do not ship any technology effect whose exact modifier name is not proven for Factorio `2.0`.
- Do not keep Space Age, Quality, recycler, elevated-rails, cargo, spoilage, agriculture, or recipe-productivity behavior on older lines unless that exact line has proof.
- Do not add broad runtime scans or compatibility shims just to imitate missing native modifiers.
- Do not tag a release from this temporary branch until the docs, todo, changelog, package, and validation evidence all agree.

## RC Validation Gates

- [ ] Run git status and diff checks before implementation.
- [ ] Build a target-line package only after metadata, dependencies, locale, and prototype shape are patched.
- [ ] Load the package in a matching Factorio 2.0.x binary; if unavailable, release notes must say validation was not run.
- [ ] Record exact source snapshot, binary version, load result, and exclusions before tagging.
- [ ] Do not publish from this temporary branch until blockers are closed or publicly deferred.

## Branch TODO Extract

- [ ] Select the exact MIR 2.x.x source snapshot for planned releases 1.9.7, 1.9.8, 1.9.9.
- [ ] Create a target-line API/effect whitelist from official docs where available and factorio-data 2.0.77.
- [ ] Patch info.json factorio_version, version, dependencies, and optional-mod ordering for Factorio 2.0.
- [ ] Prune unsupported current-line streams before package validation.
- [ ] Write release notes that state the supported subset and excluded current-line features.
- [ ] Run a matching Factorio 2.0.x binary load test before RC approval.
- [ ] Prove or remove every Space Age cargo modifier before RC.
- [ ] Patch recipe category discovery for additional_categories if validation shows it matters.
