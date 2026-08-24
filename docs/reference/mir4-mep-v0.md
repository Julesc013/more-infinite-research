---
title: "MIR Extension Protocol V0 Preview"
status: deprecated
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by:
  - docs/architecture/mir4-module-ecosystem.md
---
# MIR Extension Protocol V0 Preview

> Deprecated compatibility input. New extensions use MEP V1; V0 remains only for deterministic migration testing.

MEP V0 is a package-excluded, data-only declaration format. It lets a mod describe compatibility, profiles, proof references, presentation, capabilities, dependencies, conflicts, and finalization requirements without receiving compiler internals or write access.

Every envelope has a reverse-DNS extension ID, target selector, declared fragment list, canonicalization identifier, and SHA-256 digest. Unknown fragment kinds, duplicate fragment IDs, forbidden executable fields, invalid namespaces, stale digests, and undeclared dependencies fail closed with stable diagnostics.

MEP V0 is a preview contract. Modders can use it immediately and pin schema `0`; breaking improvements remain possible before API/MEP 1.0. A V0-to-V1 migration tool and compatibility window are required before 1.0 graduation.

See `sdk/preview/mir4/reference-extension/extension.json` for the executable conformance example.
