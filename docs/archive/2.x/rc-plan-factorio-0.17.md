---
title: "Factorio 0.17 RC Planning Report"
status: archived
applies_to: "0.17"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-06
supersedes: []
superseded_by: ["../../maintainer/backporting.md"]
---
# Factorio 0.17 RC Planning Report

Updated: 2026-07-06
Branch: `tmp/0.17`
Target Factorio line: `0.17.x`
Prototype snapshot reviewed: `wube/factorio-data` tag `0.17.79`
Planned MIR release slot(s): `1.8.4, 1.8.5`
Risk rating: High
Change type in this commit: documentation and planning only; no code behavior changes.

This is a tentative maintainer-authorized planning note for the temporary experimental branch. It does not make this branch a release candidate by itself. A stable RC for Factorio `0.17` still requires target-line code edits, metadata edits, package construction, and a load test against a matching Factorio binary. If those gates fail, the plan must change rather than shipping a misleading archive.

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

API status: Official 0.17.79 docs are listed; current JSON endpoints were unavailable, so factorio-data 0.17.79 supplies prototype proof.

Science-pack surface observed for the target: modern 0.17 science names are present, plus a generic science-pack artifact to validate.

- factorio-data 0.17.79 shows max_level/count_formula, mining-drill productivity, inventory/trash slots, stack inserter capacity, gun/ammo/turret/toolbelt, and character mining speed.
- 0.17 predates change-recipe-productivity and Space Age concepts.
- 0.17 still has normal/expensive recipe forms, so scanners must preserve that shape if used.
- Runtime storage must use global if control code remains.

## Current MIR Code Surfaces That Do Not Backport Cleanly

The current branch began as the Factorio `2.1` development snapshot. The following surfaces must be treated as blockers or explicit exclusions before any stable RC claim:

- Remove recipe productivity, Space Age, cargo, Quality, recycler, elevated-rails, pipeline extent, spoilage, agriculture, and storage-only runtime surfaces.
- Keep a whitelist for direct effects from factorio-data 0.17.79.
- Map icons and prerequisites to base 0.17 techs/items.
- Validate with a 0.17.79 executable.

## Minimum RC Plan

- Make this a reduced native-effect and base-extension port, not full current-line backport.
- Preserve recipe-matching compatibility only where still used for diagnostics or future proofing.
- Document excluded 2.x streams in release notes.

## Stable RC Readiness

Status: not ready.

This branch is suitable as an experimental planning branch only. The present source tree should not be packaged as a Factorio `0.17` RC by changing metadata alone. The RC threshold is a target-specific compatibility patch with unsupported technology modifiers removed, target science packs resolved, locale/package structure verified, and the package loaded by a matching Factorio `0.17.x` executable.

## Implementation Non-Goals For The First RC

- Do not promise full feature parity with the current Factorio `2.1` line.
- Do not ship any technology effect whose exact modifier name is not proven for Factorio `0.17`.
- Do not keep Space Age, Quality, recycler, elevated-rails, cargo, spoilage, agriculture, or recipe-productivity behavior on older lines unless that exact line has proof.
- Do not add broad runtime scans or compatibility shims just to imitate missing native modifiers.
- Do not tag a release from this temporary branch until the docs, todo, changelog, package, and validation evidence all agree.

## RC Validation Gates

- [ ] Run git status and diff checks before implementation.
- [ ] Build a target-line package only after metadata, dependencies, locale, and prototype shape are patched.
- [ ] Load the package in a matching Factorio 0.17.x binary; if unavailable, release notes must say validation was not run.
- [ ] Record exact source snapshot, binary version, load result, and exclusions before tagging.
- [ ] Do not publish from this temporary branch until blockers are closed or publicly deferred.

## Branch TODO Extract

- [ ] Select the exact MIR 2.x.x source snapshot for planned releases 1.8.4, 1.8.5.
- [ ] Create a target-line API/effect whitelist from official docs where available and factorio-data 0.17.79.
- [ ] Patch info.json factorio_version, version, dependencies, and optional-mod ordering for Factorio 0.17.
- [ ] Prune unsupported current-line streams before package validation.
- [ ] Write release notes that state the supported subset and excluded current-line features.
- [ ] Run a matching Factorio 0.17.x binary load test before RC approval.
- [ ] Create a 0.17 science/prerequisite map.
- [ ] Add a 0.17 load-only validation profile before implementation.