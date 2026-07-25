---
title: "ADR 0027: Compiler Schema Compatibility"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# ADR 0027: Compiler Schema Compatibility

## Decision

`.mir/compiler-schema-authority.json` declares current, readable, writable, and compatibility-projection versions. Unknown schema versions fail closed. Downgrades exist only through named projection functions and never replace the authoritative fingerprint.

CompilerInput schema 2, CompilerResult schema 2, and RuntimeEnvironmentIdentity schema 2 expose schema-1 compatibility projections. New authoritative records are written only at their current schema. Unknown fields are ignored only while reading the declared authoritative version.
