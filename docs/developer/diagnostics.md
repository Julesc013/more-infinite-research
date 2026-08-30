---
title: "MIR 4 Diagnostic Registry"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-diagnostic-registry-developer-guide
---

# MIR 4 diagnostic registry

Diagnostics are typed records with stable codes, severity, subject, target, message parameters, and deterministic ordering. Rendered prose is a projection; code and structured fields are the contract.

Extensions may emit only registered extension diagnostics. Unknown codes, nondeterministic order, oversized payloads, or values outside the schema fail conformance. Never use a warning to bypass a hard-safety rejection.

The current registry is bundled as `sdk/preview/mir4/api-v1/diagnostics.json`.
