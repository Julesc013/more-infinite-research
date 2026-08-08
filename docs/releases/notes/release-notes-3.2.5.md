---
title: "MIR 3.2.5 Release Notes"
status: current
applies_to: "3.2.5"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: ["docs/releases/3.2.4-unified-research-cost-curves.md"]
superseded_by: []
---

# MIR 3.2.5

MIR 3.2.5 is the Factorio 2.1 unified research-cost and compatibility release after public MIR 3.2.3. It supports Factorio 2.1.8 and newer and was qualified against Factorio 2.1.13. It absorbs the unpublished 3.2.4 work, so players should upgrade directly from 3.2.3 and must not install a 3.2.4 development archive as an intermediate.

## Research costs

- Every MIR research stream and base continuation gains a per-level linear cost increment while retaining its existing base-cost and exponential-growth controls.
- Fixed, linear, exponential, and hybrid curves use one formula: `(base + increment * offset) * growth ^ offset`.
- Existing default settings retain the prior cost behavior because the new increment defaults to zero.
- Stable base-continuation base settings retain their level-one coefficient meaning and are projected to the first controlled level.
- Recognized native-owner formulas remain byte-for-byte unchanged when their controls remain at defaults.
- Explicit overrides of unknown or over-budget external formulas fail closed instead of guessing a conversion.

## Configuration changes and upgrades

- MIR now carries compact versioned old/new cost descriptors into runtime instead of reparsing research formulas there.
- Factorio already normalizes the active research fraction when a prototype cost changes. MIR retains that engine-normalized value and does not apply a second `old_cost / new_cost` conversion.
- The active technology, exact level, queue, completed levels, completed unit-equivalent work, and unrelated force state are preserved by MIR's configuration handler.
- Productivity-family adoption signature changes no longer call a force-wide technology-effect reset, so unrelated mod effects and force recipe state are not reapplied.
- A malformed, tampered, unknown, or over-budget descriptor is refused safely and produces a stable diagnostic; descriptor analysis never mutates live research progress.
- The supported public upgrade path is 3.2.3 to 3.2.5. Keep a normal save backup, then save and reload once more after the first successful upgrade to confirm stable state.

## Compatibility and support

- Existing technology, setting, locale, runtime-state, and profile identifiers remain stable.
- Old profiles remain readable and unknown future profile fields remain preserved.
- New cost controls use neutral defaults.
- Normal loads expose a bounded, privacy-safe research-cost support record linking the neutral-default proposition to the final compiler result and providing stable reason and remediation codes.
- Existing Base, Space Age, native-owner, automatic-family, upgrade, configuration-change, and governed ecosystem checks remain part of the release evidence. A successful load is still only a load claim; it is not a blanket semantic-support claim for every mod combination.
- When reporting a problem, include the exact MIR archive hash, Factorio version, enabled mod archive names and hashes, startup settings, source save, and relevant log rows. Remove usernames, absolute paths, tokens, and unrelated save data before sharing.

## Known limits

- Unknown external research-cost formulas are preserved at defaults. MIR refuses an explicit override when it cannot prove a safe conversion instead of guessing.
- Generalized all-stream explanations, a public proof/environment platform, universal support bundles, and broad automatic compatibility generation are outside this patch release.
- MIR 3.2.5 is for Factorio 2.1. Do not copy it into Factorio 2.0; MIR 2.5.5 is a separate target projection with its own package and qualification.

## Publication and next release

The exact C32 ZIP is published and its downloaded GitHub bytes were verified. Publication used the recorded release-specific time-boxed exception: product qualification, deterministic package identity, maintainer playtest, and the exact Factorio 2.1.13 environment passed, while fresh protected GitHub qualification and a protected seal remain post-publication obligations. The exception does not claim those gates passed and does not change generic release policy.

The package and tag are immutable. Every later MIR 3 correction, including a correction to packaged documentation, routes to `3.2.9`. There will be no `3.2.6`, `3.2.7`, or `3.2.8` release.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.5.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `publicly-verified` |
| Candidate | `C32` |
| Package source commit | `a3bfbc4524b52cede425900e775384eb9c1fc4b3` |
| Archive SHA-256 | `AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF` |
| Content SHA-256 | `1A2A37380FDE8EA0C260F90414ECB2BF70314341369D816FDD74D59B50535A7D` |
| Tag | `3.2.5` |
| Tag commit | `62fddd86b51db7c0238731815d15ca26a4b45857` |
| Assurance exceptions | `C32-TIMEBOXED-PUBLICATION-2026-08-08` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
