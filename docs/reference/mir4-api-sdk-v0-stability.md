---
title: "MIR 4 API and SDK V0 Stability Policy"
status: deprecated
applies_to: "MIR 4 API/SDK V0 preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by:
  - docs/reference/generated/mir4-api-sdk-v1.md
---

# MIR 4 API and SDK V0 Stability Policy

> Deprecated compatibility policy. V1 is the current release-facing developer preview.

V0 is a supported developer preview, not a frozen 1.0 compatibility contract. Every preview archive is immutable once attached to a release, but a later V0 build may change a schema, field, diagnostic or binding when the change is documented and conformance remains deterministic.

Consumers must pin the asset manifest digest and validate every input. Unknown kinds, schema versions, target codes and forbidden MEP fields fail closed. Diagnostics are stable within one pinned preview asset and may only be renamed with an explicit migration entry.

A V0 change requires updated source contracts, JSON Schemas, generated references, both bindings, canonicalization vectors, positive and negative fixtures, examples, conformance tests and this policy or a linked migration note. Breaking changes must state the old and new field or diagnostic, the mechanical migration and the first asset digest carrying the change.

Graduation to 1.0 requires named adopters, compatibility tests across supported targets, a deprecation window, semantic versioning rules and a maintainer-approved stability authority. No V0 declaration grants prototype mutation, hard-safety access or authoritative compiler output.
