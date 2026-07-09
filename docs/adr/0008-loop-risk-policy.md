---
title: "ADR 0008: Loop-Risk Policy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0008: Loop-Risk Policy

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Loop-risk candidates are diagnostic-only by default. This includes recovery,
cleaning, self-return, barrel/container return, catalyst, recycling, voiding,
matter/transmutation, and similar loops.

## Consequences

False positives are acceptable until policy is refined. False negatives are
dangerous and require negative fixtures.
