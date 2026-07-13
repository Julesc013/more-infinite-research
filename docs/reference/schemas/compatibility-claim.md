---
title: "Compatibility Claim Schema"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Compatibility Claim Schema

The canonical machine record is `fixtures/compat-matrix/claims.json`, routed by `.mir/compatibility.yml`.

Required fields:

| Field | Meaning |
| --- | --- |
| `mod` | External mod or load-profile identifier. |
| `claim_level` | Narrow evidence-bound claim level. |
| `capabilities` | Capability behavior map. |
| `tested_factorio` | Factorio version used for the evidence. |
| `generated_streams` | Manifest stream IDs used by the claim. |
| `fixtures` | Fixture or named load-check evidence. |
| `public_text` | Allowed public wording. |

