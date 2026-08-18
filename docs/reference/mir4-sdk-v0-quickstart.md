---
title: "MIR 4 SDK V0 Preview Quickstart"
status: current
applies_to: "MIR 4 API/SDK V0 preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---

# MIR 4 SDK V0 Preview Quickstart

SDK V0 is a real, distributable developer preview. Its schemas and diagnostics are deterministic, but compatibility may change before API/SDK 1.0. It cannot mutate Factorio prototypes, settings, migrations or persistent authoritative state.

## Generate and verify

```powershell
.\tools\mir.ps1 mir4 sdk generate
.\tools\mir.ps1 mir4 sdk check
.\tools\mir.ps1 mir4 api check
.\tools\mir.ps1 mir4 api conformance
.\tools\mir.ps1 mir4 platform generate
.\tools\mir.ps1 mir4 platform conformance
.\tools\mir.ps1 mir4 platform package
.\tools\mir.ps1 mir4 platform compile --target f210 --extension sdk/preview/mir4/reference-extension/extension.json --output build/results/mir4-shadow/reference-f210.json
```

The generated preview archives are written beneath `build/mir4/platform-preview`. They are GitHub developer assets, never player ZIP or Mod Portal content.

The SDK archive is self-contained. After extraction, run its conformance entrypoint from any directory; it does not require a repository checkout:

```powershell
.\mir4-sdk-v0-preview\sdk\preview\mir4\conformance\Invoke-MIR4SdkConformance.ps1
```

The PowerShell runner requires PowerShell 7 with `Test-Json`. The Lua modules are data-only validators and do not require Factorio globals.

The archive manifest binds every file by SHA-256. Pin both the outer archive checksum and its embedded manifest digest when adopting a preview build.

The portable bindings live under `sdk/preview/mir4/api-v0` and `sdk/preview/mir4/powershell`. The older repository path under `sdk/experimental/mir4` remains a generated compatibility alias during V0.

## Extension workflow

1. Start from `sdk/preview/mir4/reference-extension/extension.json`.
2. Declare only data fragments supported by MEP V0.
3. Validate against `sdk/preview/mir4/schema/mir4-mep-v0.schema.json`.
4. Run conformance, including negative fixtures.
5. Consume Query or Support projections rather than compiler internals.
6. Treat every diagnostic candidate as review-required unless a stable policy explicitly admits it.

The `platform compile` command is the tuning loop: it validates a MEP envelope, normalizes its fragments against a governed target provider, runs the physical SafetyKernel and PolicyEngine boundary, and writes a deterministic shadow result. The result can diagnose, preserve, or request review or extension, but it cannot mutate player behavior.

MEP V0 accepts Compatibility, Profile, Proof, Presentation, CapabilityRequirement, ExtensionDependency, ExtensionConflict and FinalizationRequirement fragments. It rejects callbacks, prototype writes, raw compiler contexts and hard-safety access.

## Inspector

Open `sdk/preview/mir4/inspector/index.html` with the generated Query snapshot to inspect capabilities, streams, diagnostics and profile information. Use `Export-MIR4SupportSnapshot.ps1` for a portable read-only support record. Inspector is an API consumer and has no private compiler-state dependency.

## Stability rule

V0 changes require regenerated schemas, bindings, reference outputs, fixtures, conformance and migration notes in the same pull request. A V0 consumer must pin the preview manifest and checksum rather than assuming forward compatibility.
