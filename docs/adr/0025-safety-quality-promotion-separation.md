---
title: "ADR 0025: Safety, Quality, And Promotion Separation"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0025: Safety, Quality, And Promotion Separation

## Decision

Structural safety, measured design quality, human review, promotion, execution, and release eligibility are independent decisions. `CompilerResult` schema 2 records execution, safety, review, promotion, and release dimensions plus complete disposition classes, counts, and fingerprints.

An incomplete quality assessment cannot pass. A safety pass does not imply review or promotion. A promotion record must bind the exact design, qualification, quality evidence, applicability envelope, and migration authority.
