---
title: "ADR 0012: Fixture And Report-Diff Strategy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0012: Fixture And Report-Diff Strategy

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Every emitted compatibility behavior needs positive and negative fixtures.
Planner report diffs are required for broad classifier or policy changes.

## Consequences

Large mod updates can be reviewed as evidence changes instead of vague
compatibility anecdotes.
