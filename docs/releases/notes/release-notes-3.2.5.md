---
title: "MIR 3.2.5 Release Notes"
status: current
applies_to: "3.2.5"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-05
supersedes: ["docs/releases/3.2.4-unified-research-cost-curves.md"]
superseded_by: []
---

# MIR 3.2.5

MIR 3.2.5 is the planned Factorio 2.1 convergence release after public MIR 3.2.3. It absorbs the unpublished 3.2.4 work; there is no public 3.2.4 upgrade step and no 3.2.4 release package should be installed as an intermediate.

The release is deliberately focused on unified research costs, exact 3.2.3 upgrade/default compatibility, current compatibility corrections, and the bounded research-cost compatibility proof/support record. Generalized all-stream explanations, public proof/environment products, universal support bundles, and broad Factorio 2.0 projection productization are deferred to a later release. Release-specific migration, privacy, localization, performance, manual, protected, seal, publication, and public-byte checks remain mandatory.

## Research costs

- Every MIR research stream and base continuation gains a per-level linear cost increment while retaining its existing base-cost and exponential-growth controls.
- Fixed, linear, exponential, and hybrid curves use one formula: `(base + increment * offset) * growth ^ offset`.
- Existing default settings retain the prior cost behavior because the new increment defaults to zero.
- Stable base-continuation base settings retain their level-one coefficient meaning and are projected to the first controlled level.
- Recognized native-owner formulas remain byte-for-byte unchanged when their controls remain at defaults.
- Explicit overrides of unknown or over-budget external formulas fail closed instead of guessing a conversion.

## Corrected configuration changes

- MIR now carries compact versioned old/new cost descriptors into runtime instead of reparsing research formulas there.
- Factorio already normalizes the active research fraction when a prototype cost changes. MIR retains that engine-normalized value and does not apply a second `old_cost / new_cost` conversion.
- The active technology, exact level, queue, completed levels, completed unit-equivalent work, and unrelated force state remain untouched by MIR's configuration handler.
- Productivity-family adoption signature changes no longer call a force-wide technology-effect reset, so unrelated mod effects and force recipe state are not reapplied.
- A malformed, tampered, unknown, or over-budget descriptor is refused safely and produces a stable diagnostic; descriptor analysis never mutates live research progress.

## Compatibility and stability

- Existing technology, setting, locale, runtime-state, and profile identifiers remain stable.
- Old profiles remain readable and unknown future profile fields remain preserved.
- New cost controls use neutral defaults.
- Normal loads expose a bounded research-cost support record that links the neutral-default proposition to the final compiler result, provides stable reason/remediation codes, and records the Factorio 2.0 validation-log adapter disposition without creating 2.5.5 authority.
- The public upgrade path is 3.2.3 to 3.2.5.
- MIR 2.5.5 is a later conditional Factorio 2.0 projection and is not produced by this release.

## Candidate status

The source remains under development. `C32` is a reserved candidate floor, not an assigned candidate identity. Development packages are for testing only until exact upgrade, reload-equivalence, ecosystem, performance, manual, protected, seal, publication, and public-byte gates are complete.

The hosted assurance control plane now isolates each worker's exact test/fingerprint subtree and requires a plan-bound worker receipt before deterministic aggregate import. Latest exact repair head `409884cba10d69ead7020df17c64899fa91f633e` passed both hosted aggregates and merged through PR 45; append-only incident `INC-2026-0056` closes `325-A1a`. This is release tooling, not candidate evidence, and it does not assign C32 or advance 3.2.5 beyond `planned`.

Fresh development-breadth execution later exposed `INC-2026-0058`: the release-targeted ecosystem profiles still referenced retired pre-migration scenario paths. The package-excluded repair binds the profiles to `validation/scenarios/local-2.1.json` or `local-2.0.json`, teaches the migration tool to recognize JSON-escaped paths, and rejects missing or noncanonical profile authorities during static admission. Focused admission also repaired `INC-2026-0059`, an output-root migration preview that incorrectly depended on an untracked legacy `.mir/tasks` directory.

The first exact ecosystem retry reached and passed all nine Factorio loads, then exposed `INC-2026-0060`: Base-only rows reached Ice productivity's deliberately unavailable cryogenic-science selector. Ice productivity now declares its Space Age dependency before science selection, while the Space Age lane retains cryogenic science and accepting-lab proof. This is a package-visible development correction; exact source-bound ecosystem and breadth closure remain required.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.5.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `manually-accepted` |
| Candidate | `C32` |
| Package source commit | `a3bfbc4524b52cede425900e775384eb9c1fc4b3` |
| Archive SHA-256 | `AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF` |
| Content SHA-256 | `1A2A37380FDE8EA0C260F90414ECB2BF70314341369D816FDD74D59B50535A7D` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
