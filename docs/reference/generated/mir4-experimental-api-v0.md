---
title: "MIR 4 API/SDK V0 Preview"
status: current
applies_to: "4.0 developer preview"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---
# MIR 4 API/SDK V0 Preview

Generated from `spec/api/mir4-v0/contracts.json`. This is real, package-excluded, read-only developer-preview tooling. Compatibility may change before 1.0 and it does not establish a player support claim.

## Quickstart

- `.\tools\mir.ps1 mir4 sdk generate`
- `.\tools\mir.ps1 mir4 sdk check`
- `.\tools\mir.ps1 mir4 api check`
- `.\tools\mir.ps1 mir4 api conformance`
- `.\tools\mir.ps1 mir4 platform conformance`
- `.\tools\mir.ps1 mir4 platform package`

| Kind | Purpose |
| --- | --- |
| `MIR4HostManifestV0` | Host identity and advertised read-only capabilities. |
| `MIR4ExtensionEnvelopeV0` | Namespaced extension declaration transported to a host. |
| `MIR4QuerySnapshotV0` | Immutable projection of public compiler artifacts. |
| `MIR4ProfileV0` | Declarative consumer profile with no executor access. |
| `MIR4DiagnosticV0` | Stable diagnostic code, severity and bounded context. |
| `MIR4SupportSnapshotV0` | Target-specific support and transport disposition. |

Canonical JSON recursively sorts object keys, preserves array order, uses compact UTF-8, and hashes the record with `digest` omitted. Unknown top-level fields, invalid reverse-DNS namespaces, more than 128 capabilities, more than 32 extensions, and digest mismatch fail closed.

Target transports are read-only. Mutable compiler context, executors, SafetyKernel internals, and prototype emission are never exposed. MEP V0, the reference extension, Inspector, target-provider projections, shadow compilation runs, Runtime/State inventory, and ProcessIR reports are distributed as separate preview assets.
