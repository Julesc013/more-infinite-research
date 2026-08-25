---
title: "MIR 4 API and SDK V1 Preview"
status: current
applies_to: "4.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
---
# MIR 4 API and SDK V1 Preview

Generated from `spec/api/mir4-v1/contracts.json` and the W05 module-ecosystem authority. The nine APIs return copied, bounded, paginated, capability-labelled data. Unavailability is an explicit status with a reason and evidence; it is never reported as a numeric zero.

V1 records use the permanent `https://julesc013.github.io/more-infinite-research/schemas/mir4/v1/` namespace and `mir-canonical-json/1`: NFC UTF-8 without a BOM, ordinal object keys, preserved generic array order, signed safe integers only, canonical target and timestamp forms, and domain-separated SHA-256 digests. V0 is accepted only by explicit migration readers and is never emitted as V1.

Bindings are provided for JSON Schema, Lua with LuaLS annotations, TypeScript/Node, Python, and PowerShell. Every language binding exposes parse, validate, canonicalize, digest, capability negotiation, availability decoding, bounded pagination, snapshot comparison, diagnostic rendering, extension validation, and manifest/archive verification. Lua uses explicit host ports for canonical JSON, SHA-256, and archive entry I/O because the Factorio sandbox has no general filesystem or ZIP authority.

The generated conformance corpus contains 12 positive and 18 negative cases. PowerShell, Python, and Node must produce identical canonical bytes, digests, and accept/reject sets. The same conformance runner operates from a clean extracted archive. The reference extension and fixtures exercise all 12 fragment kinds. Use `tools/mir.ps1 mir4 extension` for init, validate, explain, test, package, and migrate commands.

This is package-excluded developer-preview tooling. `BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER` remains open because no governed exact IR4 consumer closure is local.