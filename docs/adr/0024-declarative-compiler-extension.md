---
title: "ADR 0024: Declarative Compiler Extension"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0024: Declarative Compiler Extension

## Decision

New families, streams, effect targets, gates, quality profiles, and promotion permissions enter through governed data authorities and generated projections. They do not add prototype mutation branches to compatibility policy.

Provider claims bind exact semantic fingerprints. Claims for one recipe and stream collapse only when their subject, partition, effect, policy, review evidence, and risk material are identical. Disagreement is `REVIEW_REQUIRED`; provider ordering is never a semantic tie-breaker.
