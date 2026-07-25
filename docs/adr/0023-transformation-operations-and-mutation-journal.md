---
title: "ADR 0023: Transformation Operations And Mutation Journal"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0023: Transformation Operations And Mutation Journal

## Decision

Every technology create or patch is a schema-1 `TransformationOperation` in a fingerprinted `TransformationPlan`. The envelope binds phase, action, subject, precondition, policy authority, payload, expected output, and evidence.

`emit/technology_operation_executor.lua` is the shared technology create/patch mutation authority. Stream and base executors retain only their specialized diagnostics and routing. Every applied operation can produce exactly one `MutationJournal` entry binding before, after, operation, status, and plan fingerprints.
