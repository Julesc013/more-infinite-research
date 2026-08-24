---
title: "MIR 4 SDK V1 Developer Preview Quickstart"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-24
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

API V1 contains nine copied, bounded, capability-labelled surfaces. MEP V1 contains 12 data-only fragment kinds and the V0-to-V1 migration helpers. Neither surface can mutate prototypes, settings, migrations, runtime state, player packages, or public compatibility claims. Pin the archive and embedded manifest digests; compatibility may still change before 1.0.
