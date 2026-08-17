---
title: "MIR 4 Experimental API V0"
status: current
applies_to: "4.0 bootstrap tooling"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---
# MIR 4 Experimental API V0

Generated from `spec/api/mir4-v0/contracts.json`. This is package-excluded, read-only experimental tooling, not stable MEP 1.0 or a public support contract.

## Quickstart

- `.\tools\mir.ps1 mir4 sdk generate`
- `.\tools\mir.ps1 mir4 sdk check`
- `.\tools\mir.ps1 mir4 api check`
- `.\tools\mir.ps1 mir4 api conformance`

| Kind | Purpose |
| --- | --- |
| `MIR4HostManifestV0` | Host identity and advertised read-only capabilities. |
| `MIR4ExtensionEnvelopeV0` | Namespaced extension declaration transported to a host. |
| `MIR4QuerySnapshotV0` | Immutable projection of public compiler artifacts. |
| `MIR4ProfileV0` | Declarative consumer profile with no executor access. |
| `MIR4DiagnosticV0` | Stable diagnostic code, severity and bounded context. |
| `MIR4SupportSnapshotV0` | Target-specific support and transport disposition. |

Canonical JSON recursively sorts object keys, preserves array order, uses compact UTF-8, and hashes the record with `digest` omitted. Unknown top-level fields, invalid reverse-DNS namespaces, more than 128 capabilities, more than 32 extensions, and digest mismatch fail closed.

Target transports: f210 may use a proven read-only projection; f200 remains stage-local/package-excluded; f110 and f100 use build-time static manifests. Mutable compiler context, executors, and safety internals are never exposed.
