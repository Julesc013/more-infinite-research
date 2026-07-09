---
title: "Factorio 0.14 RC Planning Report"
status: archived
applies_to: "0.14"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-06
supersedes: []
superseded_by: ["../../maintainer/backporting.md"]
---
# Factorio 0.14 RC Planning Report

Updated: 2026-07-06
Branch: `tmp/0.14`
Target Factorio line: `0.14.x`
Prototype snapshot reviewed: `wube/factorio-data` tag `0.14.23`
Planned MIR release slot(s): `1.7.8`
Risk rating: Severe
Change type in this commit: documentation and planning only; no code behavior changes.

This is a tentative maintainer-authorized planning note for the temporary experimental branch. It does not make this branch a release candidate by itself. A stable RC for Factorio `0.14` still requires target-line code edits, metadata edits, package construction, and a load test against a matching Factorio binary. If those gates fail, the plan must change rather than shipping a misleading archive.

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

API status: Official 0.14 docs are listed, and FFF #153 confirms 0.14 experimental followed 0.13 stable with scripting/modding work during stabilization.

Science-pack surface observed for the target: science-pack-1, science-pack-2, science-pack-3, alien-science-pack.

- factorio-data 0.14.23 did not show max_level/count_formula in the base scan.
- Observed effects include logistic trash, stack inserter capacity, inserter stack size, turret attack, gun speed, ammo damage, and toolbelt.
- No mining drill productivity, recipe productivity, Space Age, or modern science packs were observed.
- 0.14 is likely a finite-numbered-continuation target unless infinite technology support is proven.

## Current MIR Code Surfaces That Do Not Backport Cleanly

The current branch began as the Factorio `2.1` development snapshot. The following surfaces must be treated as blockers or explicit exclusions before any stable RC claim:

- Do not use current max_level/count_formula generation until 0.14 proof exists.
- Replace modern science with alien-era packs.
- Remove recipe productivity, mining-drill productivity, Space Age, cargo, Quality, pipeline, spoilage, agriculture, and storage-only runtime code.
- Design finite continuations or prove an accepted infinite equivalent.

## Minimum RC Plan

- Treat this as the first legacy reconstruction branch rather than a normal backport.
- Build a minimal finite RC focused on combat, inserter capacity, toolbelt, and logistics trash if supported.
- Use 0.14.23 factorio-data plus binary load as authority.

## Stable RC Readiness

Status: not ready.

This branch is suitable as an experimental planning branch only. The present source tree should not be packaged as a Factorio `0.14` RC by changing metadata alone. The RC threshold is a target-specific compatibility patch with unsupported technology modifiers removed, target science packs resolved, locale/package structure verified, and the package loaded by a matching Factorio `0.14.x` executable.

## Implementation Non-Goals For The First RC

- Do not promise full feature parity with the current Factorio `2.1` line.
- Do not ship any technology effect whose exact modifier name is not proven for Factorio `0.14`.
- Do not keep Space Age, Quality, recycler, elevated-rails, cargo, spoilage, agriculture, or recipe-productivity behavior on older lines unless that exact line has proof.
- Do not add broad runtime scans or compatibility shims just to imitate missing native modifiers.
- Do not tag a release from this temporary branch until the docs, todo, changelog, package, and validation evidence all agree.

## RC Validation Gates

- [ ] Run git status and diff checks before implementation.
- [ ] Build a target-line package only after metadata, dependencies, locale, and prototype shape are patched.
- [ ] Load the package in a matching Factorio 0.14.x binary; if unavailable, release notes must say validation was not run.
- [ ] Record exact source snapshot, binary version, load result, and exclusions before tagging.
- [ ] Do not publish from this temporary branch until blockers are closed or publicly deferred.

## Branch TODO Extract

- [ ] Select the exact MIR 2.x.x source snapshot for planned releases 1.7.8.
- [ ] Create a target-line API/effect whitelist from official docs where available and factorio-data 0.14.23.
- [ ] Patch info.json factorio_version, version, dependencies, and optional-mod ordering for Factorio 0.14.
- [ ] Prune unsupported current-line streams before package validation.
- [ ] Write release notes that state the supported subset and excluded current-line features.
- [ ] Run a matching Factorio 0.14.x binary load test before RC approval.
- [ ] Decide finite-chain naming and migration policy for pre-max_level branches.
- [ ] Verify whether 0.14 accepts infinite fields despite absence from base data.