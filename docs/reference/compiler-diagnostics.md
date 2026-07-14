---
title: "Compiler Diagnostic Codes"
status: current
applies_to: "3.1.5+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# Compiler Diagnostic Codes

Automatic compiler decisions keep their durable machine-facing reason keys and also expose stable codes from `prototypes/mir/domain/diagnostics/codes.lua`.

| Namespace | Meaning |
| --- | --- |
| `MIR-AUTO-001` through `MIR-AUTO-007` | Disabled, preview, creation, reviewed-data, creation-maturity, and provider-authorization policy outcomes. |
| `MIR-PROVIDER-001` through `MIR-PROVIDER-004` | Provider discovery, rejection, attachment, and planned-generation lifecycle outcomes. |

Codes are append-only identifiers. Wording may improve without changing automation. Provider records name every code they can emit, and the registry rejects duplicate code values. Reports should include the code, reason key, provider ID, source prototype identity, final state, and evidence where those fields apply.
