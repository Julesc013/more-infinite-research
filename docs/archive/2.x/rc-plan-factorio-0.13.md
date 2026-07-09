---
title: "Factorio 0.13 RC Planning Report"
status: archived
applies_to: "0.13"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-06
supersedes: []
superseded_by: ["../../maintainer/backporting.md"]
---
# Factorio 0.13 RC Planning Report

Updated: 2026-07-06
Branch: `tmp/0.13`
Target Factorio line: `0.13.x`
Prototype snapshot reviewed: `wube/factorio-data` tag `0.13.20`
Planned MIR release slot(s): `1.7.7`
Risk rating: Severe
Change type in this commit: documentation and planning only; no code behavior changes.

This is a tentative maintainer-authorized planning note for the temporary experimental branch. It does not make this branch a release candidate by itself. A stable RC for Factorio `0.13` still requires target-line code edits, metadata edits, package construction, and a load test against a matching Factorio binary. If those gates fail, the plan must change rather than shipping a misleading archive.

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

API status: Official 0.13 docs are listed; FFF #141 and #153 provide Mod Portal/licensing and 0.13 stabilization/modding context.

Science-pack surface observed for the target: science-pack-1, science-pack-2, science-pack-3, alien-science-pack.

- factorio-data 0.13.20 did not show max_level/count_formula.
- Observed effects include logistics trash, stack inserter capacity, inserter stack size, turret attack, gun speed, ammo damage, and toolbelt.
- 0.13 is the Mod Portal launch era; licensing and metadata acceptability must be verified.
- No recipe productivity, mining drill productivity, Space Age, or modern science names were observed.

## Current MIR Code Surfaces That Do Not Backport Cleanly

The current branch began as the Factorio `2.1` development snapshot. The following surfaces must be treated as blockers or explicit exclusions before any stable RC claim:

- Use finite-chain design unless binary proof says infinite fields are accepted.
- Replace science/prerequisite discovery with alien-science-era data.
- Remove every current 2.x recipe-productivity and Space Age stream.
- Audit locale and metadata against 0.13 Mod Portal expectations.

## Minimum RC Plan

- Create a minimal stable RC for selected native effects only.
- Do not promise full MIR parity; this is a historical celebration target.
- Validate package installation, metadata, and load in 0.13.20.

## Stable RC Readiness

Status: not ready.

This branch is suitable as an experimental planning branch only. The present source tree should not be packaged as a Factorio `0.13` RC by changing metadata alone. The RC threshold is a target-specific compatibility patch with unsupported technology modifiers removed, target science packs resolved, locale/package structure verified, and the package loaded by a matching Factorio `0.13.x` executable.

## Implementation Non-Goals For The First RC

- Do not promise full feature parity with the current Factorio `2.1` line.
- Do not ship any technology effect whose exact modifier name is not proven for Factorio `0.13`.
- Do not keep Space Age, Quality, recycler, elevated-rails, cargo, spoilage, agriculture, or recipe-productivity behavior on older lines unless that exact line has proof.
- Do not add broad runtime scans or compatibility shims just to imitate missing native modifiers.
- Do not tag a release from this temporary branch until the docs, todo, changelog, package, and validation evidence all agree.

## RC Validation Gates

- [ ] Run git status and diff checks before implementation.
- [ ] Build a target-line package only after metadata, dependencies, locale, and prototype shape are patched.
- [ ] Load the package in a matching Factorio 0.13.x binary; if unavailable, release notes must say validation was not run.
- [ ] Record exact source snapshot, binary version, load result, and exclusions before tagging.
- [ ] Do not publish from this temporary branch until blockers are closed or publicly deferred.

## Branch TODO Extract

- [ ] Select the exact MIR 2.x.x source snapshot for planned releases 1.7.7.
- [ ] Create a target-line API/effect whitelist from official docs where available and factorio-data 0.13.20.
- [ ] Patch info.json factorio_version, version, dependencies, and optional-mod ordering for Factorio 0.13.
- [ ] Prune unsupported current-line streams before package validation.
- [ ] Write release notes that state the supported subset and excluded current-line features.
- [ ] Run a matching Factorio 0.13.x binary load test before RC approval.
- [ ] Check old Mod Portal factorio_version acceptance for 0.13.
- [ ] Prototype one finite continuation technology before broad generation.