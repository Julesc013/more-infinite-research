---
title: "MIR 4 SDK V1 Developer Preview Quickstart"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes:
  - docs/reference/mir4-sdk-v0-quickstart.md
superseded_by: []
---

# MIR 4 SDK V1 developer preview quickstart

Generate and validate the current package-excluded developer preview:

```powershell
.\tools\mir.ps1 mir4 platform generate
.\tools\mir.ps1 mir4 platform conformance
.\tools\mir.ps1 mir4 platform package
```

The package command emits only V1-named release-facing assets under `build/mir4/platform-preview`. Run `conformance-v1/Invoke-MIR4SdkV1Conformance.ps1` from the extracted SDK archive to validate portability.

```powershell
.\conformance-v1\Invoke-MIR4SdkV1Conformance.ps1
# CI and machines with Node:
.\conformance-v1\Invoke-MIR4SdkV1Conformance.ps1 -RequireNode
```

The corpus has 12 positive and 18 negative records. PowerShell, Python, and Node are required to agree on accepted and rejected case IDs, canonical bytes, and domain-separated digests. The Lua binding implements the same data operations and accepts explicit host ports for canonical JSON, SHA-256, and archive entries; this keeps it usable inside Factorio without inventing filesystem authority.

Each supported binding exposes parse, validate, canonicalize, digest, capability negotiation, availability decoding, bounded pagination, snapshot comparison, diagnostic rendering, extension validation, and manifest/archive verification. Small PowerShell and Python examples are bundled under `api-v1/examples`, and `api-v1/package-metadata.json` is the machine-readable operation inventory.

API V1 contains nine copied, bounded, capability-labelled surfaces. MEP V1 contains 12 data-only fragment kinds and the V0-to-V1 migration helpers. Neither surface can mutate prototypes, settings, migrations, runtime state, player packages, or public compatibility claims. Pin the archive and embedded manifest digests; compatibility may still change before 1.0.
