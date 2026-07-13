---
title: "Report Row Schema"
status: draft
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Report Row Schema

Report rows are parser-friendly diagnostics emitted through logs and consumed by compatibility audit tooling.

Common fields:

| Field | Meaning |
| --- | --- |
| `kind` | Row family such as stream, decision, lab-matrix, or loop-risk. |
| `key` | Stable row key. |
| `status` | Generated, skipped, diagnostic, rejected, or observed status. |
| `reason` | Machine-readable reason. |
| `evidence` | Compact evidence string. |
