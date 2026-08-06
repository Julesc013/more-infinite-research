---
title: "MIR 4 Offline Release Authority"
status: future
applies_to: "4.0.0+"
audience: maintainer
doc_type: requirement
owner: mir-maintainers
last_reviewed: 2026-08-07
supersedes: []
superseded_by: []
---
# MIR 4 Offline Release Authority

`MIR4-Offline-Release-Authority` requires MIR 4 release engineering to operate locally from archived inputs without GitHub or another live cloud service. GitHub is a later publication mirror, not the only release authority.

The eventual design must provide local workflow-DAG execution, a protected-equivalent local trust policy, signed immutable evidence, candidate sealing, annotated release tags, complete release bundles, evidence-store restore, branch-loss reconstruction, repository-bundle recovery, and idempotent later replication to GitHub.

This is a package-excluded future requirement. It does not admit MIR 4 implementation, expand the MIR 3 `.5` wave, or authorize the terminal MIR 3 `.9` wave.
