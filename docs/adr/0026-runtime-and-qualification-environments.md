---
title: "ADR 0026: Runtime And Qualification Environments"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0026: Runtime And Qualification Environments

## Decision

`RuntimeEnvironmentIdentity` schema 2 binds the Factorio target, exact loaded-mod closure, effective startup settings, imported profile, compatibility policy, and promotion authority that affect runtime behavior.

`QualificationEnvironmentIdentity` schema 1 separately binds candidate archive, Factorio binary, runner, verifier, required test set, plan material, and trust class. Prototype surfaces belong to `CompilationSnapshot`, not either environment record.
