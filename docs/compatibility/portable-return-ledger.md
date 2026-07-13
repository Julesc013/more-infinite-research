---
title: "Portable Return Ledger"
status: current
applies_to: "3.0.5+"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
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
| PL-003 | Four executed 2.0 scenarios were absent from the expected manifest | `portable-tooling` | Make scenario declarations target-explicit in 3.1 | Register all 71 2.0 scenarios now | Complete |
| PL-004 | Raw text hashes drift across CRLF and LF checkouts | `portable-tooling` | Keep normalized identities | Replay the final identity implementation | Complete |
| PL-005 | Content equality alone does not prove the exact frozen archive loads | `portable-tooling` | Require exact-dist and upgrade proof in the wave contract | Preserve base, Space Age, and upgrade logs | Complete |
| PL-006 | Factorio 2.1 cargo and dependency surfaces are invalid 2.0 defaults | `target-local-feature-cut` | Reject from `dev` | Keep target-owned exclusions | Complete |
| PL-007 | Runtime validation used a Factorio-line test instead of positive capabilities | `portable-tooling` | Use capability-driven dispatch | Execute all positively declared 2.0 gates | Complete |
| PL-008 | Shared fixtures assumed 2.1 science, recycler, and setting shapes | `portable-fixture` | Derive assertions from target capabilities | Use the positive 2.0 profile | Complete |
| PL-009 | Upgrade automation encoded one release pair | `portable-tooling` | Parameterize prior/current/fixture identities | Prove exact 2.3.5 to 2.4.0 retention | Complete |
| PL-010 | Historical parsers rejected spaced count formulas | `portable-shared-fix` | Emit one compact formula shape | Replay on every old target | Complete |
| PL-011 | Weapon prerequisite anchors differ by target | `portable-target-profile` | Resolve target-declared candidates | Keep target-era candidates local | Complete |
| PL-012 | Recursive graph traversal overflows on deep mod graphs | `portable-shared-fix` | Retain iterative deterministic safety | Replay without modern assumptions | Complete |
| PL-013 | A plan could be published before authoritative acceptance | `portable-shared-fix` | Publish only validated accepted plans | Match the same boundary on 2.0 | Complete |
| PL-014 | Selected configuration changes did not guarantee a load | `portable-tooling` | Execute both phases | Preserve exact phase evidence | Complete |
| PL-015 | Override fixtures assumed the current Factorio line | `portable-tooling` | Derive target metadata | Emit a target-valid helper mod | Complete |
| PL-016 | 0.14 rejects modern CLI/settings scenarios | `portable-tooling` | Keep dispatch capability-driven | Omit unsupported flags and gates | Complete |

## Fixed-Point Rule

The convergence loop is not complete until one full old-target sweep produces zero new portable compiler fixes, reusable validation fixes, higher-target profile corrections, and package-governance fixes. Target-local schema, asset, and feature cuts do not restart unrelated targets.

The 2026-07-13 sweep reached the fixed point after auditing every qualified `tmp/2.0`, `tmp/1.1`, `tmp/1.0`, `tmp/0.17`, `tmp/0.16`, `tmp/0.15`, `tmp/0.14`, and `tmp/0.13` head. Compiler, graph, formula, prerequisite, plan-publication, configuration-change, settings-override, fixture-shaping, and runner lessons are returned. The target archives remain referenced by `.mir/branches.yml`; copying them into the 3.1.5 mod or release ZIP would violate package and target-ownership boundaries.

## Release Boundaries

- Released 3.0.5 bytes are immutable.
- Ordinary discoveries go to 3.1.0 and 2.4.0, not to 3.0.6 or 2.3.6.
- A hotfix patch is reserved for load failure, save corruption, generated-ID defects, fatal prototype errors, severe package defects, serious setting regressions, or a concrete ownership/safety failure.
- Factorio 2.0 metadata, lower dependency floors, cargo cuts, and target wording never merge upward.
