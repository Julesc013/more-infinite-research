---
title: "MIR 4 API/SDK V0 Preview"
status: deprecated
applies_to: "4.0 developer preview migration input"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-24
supersedes: []
superseded_by:
  - docs/reference/generated/mir4-api-sdk-v1.md
source_of_truth_for:
  - generated-api-v0-migration-reference
---
# MIR 4 API/SDK V0 Preview

> Deprecated compatibility input. Use API/SDK V1 for new consumers; retain V0 only for deterministic V0-to-V1 migration.

Generated from `spec/api/mir4-v0/contracts.json`. This package-excluded, read-only tooling does not establish a player support claim.

## Migration checks

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

Target transports are read-only. Mutable compiler context, executors, SafetyKernel internals, and prototype emission are never exposed. V0 source artifacts remain package-excluded migration inputs and are not emitted as release-facing preview archives.
