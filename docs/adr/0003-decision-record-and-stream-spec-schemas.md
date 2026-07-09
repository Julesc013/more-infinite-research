---
title: "ADR 0003: DecisionRecord And StreamSpec Schemas"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0003: DecisionRecord And StreamSpec Schemas

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Every compiler decision is serialized as a schema-versioned `DecisionRecord`.
Every emitted prototype change originates from a schema-versioned `StreamSpec`.

## Consequences

Diagnostics, fixtures, report diffs, and migration review share the same
intermediate representation.
