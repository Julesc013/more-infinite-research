---
title: "Factorio 1.0 RC Planning Report"
status: archived
applies_to: "1.0"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../maintainer/backporting.md"]
---
# Factorio 1.0 RC Planning Report

Updated: 2026-07-10 Branch: `tmp/1.0` Target Factorio line: `1.0.x` Prototype snapshot reviewed: `wube/factorio-data` tag `1.0.0` Planned MIR release slot(s): `1.8.1+` Risk rating: High Change type in this commit: documentation and planning only; no code behavior changes.

This is a tentative maintainer-authorized planning note for the temporary experimental branch. It does not make this branch a release candidate by itself. A stable RC for Factorio `1.0` still requires target-line code edits, metadata edits, package construction, and a load test against a matching Factorio binary. If those gates fail, the plan must change rather than shipping a misleading archive.

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

API status: Official 1.0.0 HTML docs are listed; JSON endpoints used in this audit were unavailable, so factorio-data 1.0.0 is the prototype contract until a better export is found.

Science-pack surface observed for the target: modern science names are present, with a generic science-pack artifact that must be ignored or explained by fixture proof.

- factorio-data 1.0.0 shows max_level/count_formula, mining-drill productivity, inventory/trash slots, stack inserter capacity, gun/ammo/turret/toolbelt, and character mining speed.
- No change-recipe-productivity proof was found.
- 1.0 is before storage rename, so runtime state must use global.
- Latest mod-structure docs note a `0.18`-to-`1.0` exception. MIR uses that only for the frozen `1.8.0` bridge package; `1.8.1+` is the maintained direct Factorio `1.0` line.

## Current MIR Code Surfaces That Do Not Backport Cleanly

The current branch began as the Factorio `2.1` development snapshot. The following surfaces must be treated as blockers or explicit exclusions before any stable RC claim:

- Strip Space Age, recipe productivity, cargo, Quality, recycler, elevated rails, and storage-specific runtime code.
- Use stack-inserter terminology instead of bulk-inserter.
- Keep only max_level/count_formula native effects and chain extensions after validation.
- Rebuild science-pack selection from target data.

## Minimum RC Plan

- Treat `1.0` as a `1.1`-style reduced feature port with extra API-export caution, seeded from the validated `1.9.3` source point plus lessons from the `1.8.0` bridge proof.
- Use factorio-data 1.0.0 and a real 1.0 binary load as mandatory proof.
- Do not claim recipe productivity unless a target binary accepts it in a fixture.
- Do not add new features in `1.8.1`; the release establishes the maintained `1.0` line after the bridge proof.

## Stable RC Readiness

Status: not ready.

This branch is suitable as an experimental planning branch only. The present source tree should not be packaged as a Factorio `1.0` RC by changing metadata alone. The RC threshold is a target-specific compatibility patch with unsupported technology modifiers removed, target science packs resolved, locale/package structure verified, and the package loaded by a matching Factorio `1.0.x` executable.

## Implementation Non-Goals For The First RC

- Do not promise full feature parity with the current Factorio `2.1` line.
- Do not ship any technology effect whose exact modifier name is not proven for Factorio `1.0`.
- Do not keep Space Age, Quality, recycler, elevated-rails, cargo, spoilage, agriculture, or recipe-productivity behavior on older lines unless that exact line has proof.
- Do not add broad runtime scans or compatibility shims just to imitate missing native modifiers.
- Do not tag a release from this temporary branch until the docs, todo, changelog, package, and validation evidence all agree.

## RC Validation Gates

- [ ] Run git status and diff checks before implementation.
- [ ] Build a target-line package only after metadata, dependencies, locale, and prototype shape are patched.
- [ ] Load the package in a matching Factorio 1.0.x binary; if unavailable, release notes must say validation was not run.
- [ ] Record exact source snapshot, binary version, load result, and exclusions before tagging.
- [ ] Do not publish from this temporary branch until blockers are closed or publicly deferred.

## Branch TODO Extract

- [ ] Start from the validated `1.8.0` bridge commit or from `1.9.3` plus bridge lessons, choosing the cleaner diff.
- [ ] Create a target-line API/effect whitelist from official docs where available and factorio-data 1.0.0.
- [ ] Patch info.json to `version = "1.8.1"`, `factorio_version = "1.0"`, and `base >= 1.0`.
- [ ] Prune unsupported current-line streams before package validation.
- [ ] Write release notes that state the supported subset and excluded current-line features.
- [ ] Run a matching Factorio 1.0.x binary load test before RC approval.
- [ ] Find or generate a machine-readable 1.0 API surface if possible.
- [ ] Build a 1.0 binary smoke fixture for generated max_level technologies.
