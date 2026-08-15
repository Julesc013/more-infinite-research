---
title: "ADR 0004: MIR 3 EOL and MIR 4 Entry Gate"
status: current
applies_to: "MIR4-R0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# ADR 0004: MIR 3 EOL and MIR 4 Entry Gate

## Context

The MIR 3 EOL policy ends its emergency-lane list with `publish-valid-4x-distribution`. The successor bootstrap policy simultaneously forbids a public version-4 package or tag before MIR 3 EOL. Reading both clauses as public publication creates a circular gate.

## Decision

The versioned `MIR3-to-MIR4-Governance-ReconciliationV1` record resolves the relationship without rewriting either historical policy.

Before EOL, MIR must import a terminal baseline, generate one local behavior-equivalent Factorio 2.1 distribution, prove clean install and direct 3.2.9 upgrade, prove reload/settings/profile/engine equivalence, seal it locally, generate a complete publication bundle, and prove the dry run is idempotent. That locally sealed distribution satisfies the old “valid 4.x distribution” gate.

MIR 3 public custody, final `.9` baselines, final index, museum/restore work, emergency-lane proof, and EOL record then complete. Only after the EOL seal may a later authority allocate and publish the first 4.x tag, release, or Mod Portal asset.

## Consequences

The dependency graph is acyclic and fails closed. R0 may implement package-excluded import and local proof machinery now. It may not create a public 4.x identity or change any terminal `.9` byte.
