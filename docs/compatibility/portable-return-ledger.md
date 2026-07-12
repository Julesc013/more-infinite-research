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
| PL-003 | Four executed 2.0 scenarios were absent from the expected manifest | `portable-tooling` | Scenario declarations are target-explicit in released 3.1 | Register all declared 2.0 scenarios | Complete |
| PL-004 | Raw text hashes drift across CRLF and LF checkouts | `portable-tooling` | Keep normalized identities | Replay the final identity implementation | Complete |
| PL-005 | Content equality alone does not prove the exact frozen archive loads | `portable-tooling` | Released 3.1 requires exact-dist and upgrade proof | Preserve base, Space Age, and upgrade logs | Complete |
| PL-006 | Factorio 2.1 cargo and dependency surfaces are invalid 2.0 defaults | `target-local-feature-cut` | Reject from `dev` | Keep target-owned exclusions | Complete |
| PL-007 | Runtime validation used a Factorio 2.1 line test instead of positive target capabilities | `portable-tooling` | Queue capability-driven dispatch for the next development release | Execute all positively declared 2.0 gates | Accepted for next `dev` |
| PL-008 | Shared fixtures assumed 2.1 science, recycler, and settings shapes | `portable-fixture` | Queue target-derived fixture shapes for the next development release | Use the positive 2.0 profile now | Accepted for next `dev` |
| PL-009 | Upgrade automation encoded one release pair | `portable-tooling` | Queue the parameterized harness for the next development release | Prove exact 2.3.5 to 2.4.0 retention | Accepted for next `dev` |

## Fixed-Point Rule

The convergence loop is not complete until one full old-target sweep produces zero new portable compiler fixes, reusable validation fixes, higher-target profile corrections, and package-governance fixes. Target-local schema, asset, and feature cuts do not restart unrelated targets.

The current fixed point is open. MIR 2.3.5 lessons are incorporated in released 3.1.0, while MIR 2.4.0 produced three reusable validation and fixture lessons queued for the next development release. The 1.1 through 0.6 refresh remains independently pending.

## Release Boundaries

- Released 3.0.5 bytes are immutable.
- New discoveries after publication go to the next modern and target-line development releases, not to immutable 3.1.0, 2.4.0, 3.0.5, or 2.3.5 bytes.
- A hotfix patch is reserved for load failure, save corruption, generated-ID defects, fatal prototype errors, severe package defects, serious setting regressions, or a concrete ownership/safety failure.
- Factorio 2.0 metadata, lower dependency floors, cargo cuts, and target wording never merge upward.
