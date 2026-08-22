---
title: "MIR 4 API and SDK V1 Preview"
status: current
applies_to: "4.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---
# MIR 4 API and SDK V1 Preview

Generated from `spec/api/mir4-v1/contracts.json` and the W05 module-ecosystem authority. The nine APIs return copied, bounded, paginated, capability-labelled data. Unavailability is an explicit status with a reason and evidence; it is never reported as a numeric zero.

Bindings are provided for JSON Schema, Lua with LuaLS annotations, TypeScript, Python, and PowerShell. The reference extension and fixtures exercise all 12 fragment kinds. Use `tools/mir.ps1 mir4 extension` for init, validate, explain, test, package, and migrate commands.

This is package-excluded developer-preview tooling. `BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER` remains open because no governed exact IR4 consumer closure is local.