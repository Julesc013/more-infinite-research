---
title: "Policy Overlay Schema"
status: draft
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Policy Overlay Schema

Policy overlays select behavior. They do not emit technologies directly.

Typical fields:

| Field | Meaning |
| --- | --- |
| `schema` | Overlay schema version. |
| `id` | Stable overlay ID. |
| `applies_when` | Mod, prototype, or scenario selectors. |
| `capabilities` | Capability modes and gates. |
| `claims` | Claim records supported by the overlay. |
| `deny_risk_flags` | Risk flags that prevent emission. |
