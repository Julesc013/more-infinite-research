---
title: "ADR 0004: Policy Overlays, Not Behavior Scripts"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0004: Policy Overlays, Not Behavior Scripts

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Named compatibility files register declarative policy overlays. They do not construct technologies directly.

## Consequences

Compat files can provide selectors, exact IDs, denylists, claims, and fixture expectations while the compiler remains responsible for validation and emission.
