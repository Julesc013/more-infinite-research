---
title: "MIR 4 Target Compiler"
status: current
applies_to: "4.0.0 M4C02-09"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 Target Compiler

W02 makes target variation an explicit compiler boundary without creating a second gameplay authority. Target Registry V6 has two keyed tables: immutable distribution identities and support policy. Each row joins by `fNNN`, while `.mir/targets.json` remains the granular engine-capability authority and is bound by SHA-256.

`MIR4TargetProviderSpecV1` may project only distribution version, Factorio version, package root, and explicit capability omissions. The target compiler enforces determinism, supported-subset round trip, unowned-field preservation, idempotence, locality, explicit loss, absence of hidden product policy, provenance completeness, and resource budgets. Recipe, technology, stream, setting-default, and compatibility-claim policy belongs to later semantic layers.

The generalized product command delegates bytes to the existing bootstrap and historical materializers. It then copies their deterministic private packages into `build/mir4/m4c02-target-products` and records exact hashes. It does not sign, seal, publish, or mutate package sources.

Targets F210 and F200 have stable private-candidate mechanisms; F110 and F100 are preview conditional mechanisms; F018-F013 are experimental historical mechanisms. Targets F012-F006 are omitted-by-target and remain `BLOCKED_WITH_EVIDENCE` until governed predecessor packages and snapshots, exact engine locks, and rights-custody records exist.

Rollback restores Target Registry V5 as the current platform reader, deletes only generated V6 projections and private W02 output, and leaves every legacy materializer and player-package source unchanged.
