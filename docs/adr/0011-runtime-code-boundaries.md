---
title: "ADR 0011: Runtime Code Boundaries"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0011: Runtime Code Boundaries

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Static productivity streams should not require runtime code. Runtime behavior
must be event-driven, bounded, documented, and validated. Broad `on_tick`
scanning remains forbidden without a future explicit exception.

## Consequences

MIR uses native technology modifiers and prototype-stage behavior first.
Runtime systems remain narrow and conservative.
