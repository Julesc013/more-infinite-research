---
title: "Compiler Schema Registry"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Compiler Schema Registry

> Generated from `.mir/compiler-schema-authority.json`. The machine registry is authoritative.

| Record | Current | Readable | Writable | Compatibility projection |
| --- | ---: | --- | --- | ---: |
| `CompilationSnapshot` | 2 | 2 | 2 | none |
| `CompilerInput` | 2 | 2 | 2 | 1 |
| `CompilerResult` | 3 | 3 | 3 | 2 |
| `MutationJournal` | 2 | 2 | 2 | none |
| `PolicySnapshot` | 1 | 1 | 1 | none |
| `QualificationEnvironmentIdentity` | 1 | 1 | 1 | none |
| `RuntimeEnvironmentIdentity` | 2 | 2 | 2 | 1 |
| `TransformationOperation` | 2 | 2 | 2 | none |
| `TransformationPlan` | 2 | 2 | 2 | none |

Unknown schema versions fail closed. Downgrades exist only through explicit compatibility projections.
