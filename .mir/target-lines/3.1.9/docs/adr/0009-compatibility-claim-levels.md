---
title: "ADR 0009: Compatibility Claim Levels"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0009: Compatibility Claim Levels

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Compatibility claims use explicit levels: unknown, load-only, observed, coexists, diagnostic-only, partial support, full family support, and full pack support.

## Consequences

Docs must claim the proven behavior, not the mod name. "Full support" is rare and requires fixture-backed pack-level evidence.
