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

## Research costs

- Every MIR research stream and base continuation gains a per-level linear cost increment while retaining its existing base-cost and exponential-growth controls.
- Fixed, linear, exponential, and hybrid curves use one formula: `(base + increment * offset) * growth ^ offset`.
- Existing default settings retain the prior cost behavior because the new increment defaults to zero.
- Recognized native-owner formulas remain byte-for-byte unchanged when their controls remain at defaults.
- Explicit overrides of unknown or over-budget external formulas fail closed instead of guessing a conversion.

## Corrected configuration changes

- MIR now carries compact versioned old/new cost descriptors into runtime instead of reparsing research formulas there.
- When a recognized adopted native owner changes cost, MIR preserves completed unit-equivalent work by converting the old fractional progress with `old_cost / new_cost`.
- The active technology, exact level, queue, completed levels, and unrelated force state remain untouched by the conversion.
- Productivity-family adoption signature changes no longer call a force-wide technology-effect reset, so unrelated mod effects and force recipe state are not reapplied.
- A malformed, tampered, unknown, or over-budget descriptor is refused safely and produces a stable diagnostic.

## Compatibility and stability

- Existing technology, setting, locale, runtime-state, and profile identifiers remain stable.
- Old profiles remain readable and unknown future profile fields remain preserved.
- New cost controls use neutral defaults.
- The public upgrade path is 3.2.3 to 3.2.5.
- MIR 2.5.5 is a later conditional Factorio 2.0 projection and is not produced by this release.

## Candidate status

The source remains under development. `C32` is a reserved candidate floor, not an assigned candidate identity. Development packages are for testing only until exact upgrade, reload-equivalence, ecosystem, performance, manual, protected, seal, publication, and public-byte gates are complete.

The hosted assurance control plane now isolates each worker's exact test/fingerprint subtree and requires a plan-bound worker receipt before deterministic aggregate import. Latest exact repair head `409884cba10d69ead7020df17c64899fa91f633e` passed both hosted aggregates and merged through PR 45; append-only incident `INC-2026-0056` closes `325-A1a`. This is release tooling, not candidate evidence, and it does not assign C32 or advance 3.2.5 beyond `planned`.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.5.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `planned` |
| Candidate | `not-assigned` |
| Package source commit | `pending` |
| Archive SHA-256 | `pending` |
| Content SHA-256 | `pending` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
