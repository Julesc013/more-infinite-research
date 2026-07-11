---
title: "Portable Return Ledger"
status: current
applies_to: "3.0.5+"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Portable Return Ledger

`.mir/portable-return.yml` is the machine-readable authority. This page explains the decisions that keep old targets useful without allowing their metadata, engine limits, or feature cuts to become modern defaults.

## Current Return Set

| ID | Discovery | Classification | Modern decision | Target decision | Status |
| --- | --- | --- | --- | --- | --- |
| PL-001 | Stale 2.3.5 RC4 predated the final 3.0.5 settings and recycler contract | `portable-target-profile` | Keep released 3.0.5 authoritative | Replay through the 2.0 profile and requalify | Complete |
| PL-002 | 2.0 cap pass called the final builder API while the branch retained the older classifier API | `portable-shared-fix` | Retain the build-once immutable index | Port the same fact/policy boundary | Complete |
| PL-003 | Four executed 2.0 scenarios were absent from the expected manifest | `portable-tooling` | Make scenario declarations target-explicit in 3.1 | Register all 71 2.0 scenarios now | Accepted for 3.1 |
| PL-004 | Raw text hashes drift across CRLF and LF checkouts | `portable-tooling` | Keep normalized identities | Replay the final identity implementation | Complete |
| PL-005 | Content equality alone does not prove the exact frozen archive loads | `portable-tooling` | Require exact-dist and upgrade proof in the wave contract | Preserve base, Space Age, and upgrade logs | Accepted for 3.1 |
| PL-006 | Factorio 2.1 cargo and dependency surfaces are invalid 2.0 defaults | `target-local-feature-cut` | Reject from `dev` | Keep target-owned exclusions | Complete |

## Fixed-Point Rule

The convergence loop is not complete until one full old-target sweep produces zero new portable compiler fixes, reusable validation fixes, higher-target profile corrections, and package-governance fixes. Target-local schema, asset, and feature cuts do not restart unrelated targets.

The current fixed point is open. MIR 2.3.5 produced accepted 3.1 tooling work, and the 1.1 through 0.6 refresh remains pending.

## Release Boundaries

- Released 3.0.5 bytes are immutable.
- Ordinary discoveries go to 3.1.0 and 2.4.0, not to 3.0.6 or 2.3.6.
- A hotfix patch is reserved for load failure, save corruption, generated-ID defects, fatal prototype errors, severe package defects, serious setting regressions, or a concrete ownership/safety failure.
- Factorio 2.0 metadata, lower dependency floors, cargo cuts, and target wording never merge upward.
