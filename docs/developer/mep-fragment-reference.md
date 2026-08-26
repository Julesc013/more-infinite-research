---
title: "MEP V1 Fragment Reference"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-mep-v1-fragment-reference
---

# MEP V1 fragment reference

The exact twelve fragment kinds and field constraints are defined by `spec/schemas/preview/mir4-mep-v1.schema.json`. Treat that schema, not examples, as validation authority.

Every envelope carries protocol version, extension identity and version, target constraints, fragments, dependencies, conflicts, diagnostics, and a domain-separated digest. Fragment order is canonicalized; semantic dependency order is resolved separately.

Forbidden content includes callbacks, executable Lua, compiler context, raw prototypes, mutation plans, runtime state, migration executors, SafetyKernel overrides, release credentials, and support declarations. Unknown fields fail validation. Archives with unsafe paths fail packaging verification.

Use the `minimal`, `all-fragments`, and `unavailable` templates bundled under `sdk/preview/mir4/mep-v1/templates/`.
