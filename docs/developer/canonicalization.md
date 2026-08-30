---
title: "MIR Canonical JSON V1"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-canonical-json-v1-developer-guide
---

# MIR Canonical JSON V1

`mir-canonical-json/1` defines UTF-8 encoding, Unicode normalization, property ordering, schema-owned array ordering, number grammar, unavailable values, timestamps, target IDs, extension ordering, and domain-separated SHA-256 digests.

Never hash pretty-printed JSON, host-language object iteration, locale-formatted numbers, or normalized data from a different contract. Parse, validate, canonicalize, then digest.

PowerShell, Python, TypeScript/Node, and Lua bindings share the same positive and negative corpus. Run `sdk/preview/mir4/conformance-v1/Invoke-MIR4SdkV1Conformance.ps1` from the extracted API preview.
