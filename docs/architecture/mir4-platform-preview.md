---
title: "MIR 4 Platform Preview Architecture"
status: current
applies_to: "4.0.0 candidate programme"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---
# MIR 4 Platform Preview Architecture

MIR 4.0 has one stable player plane and one package-excluded developer plane. The player plane continues to use the existing compiler and emission boundary. The developer plane projects that compiler's governed inputs and public artifacts into deterministic, read-only contracts.

## Maturity and authority

`Stable` components may affect admitted player distributions. `Shadow` components execute and compare but cannot affect output. `Preview` components are usable developer products whose compatibility may change before 1.0. `Experimental` components are disabled by default. `Omitted by target` requires a target-local reason and evidence reference.

Anything below Stable is forbidden from mutating prototypes, settings, persistent state, migrations, support claims, hard-safety decisions, or player-package membership. The platform conformance gate proves package-source identity is unchanged by generation.

## One compiler, two observations

`LegacyCompilerHostAdapterV1` reads the existing target snapshots, stream manifest, compatibility manifest, fixture manifest, module boundaries, and package surface. It emits an immutable `CompilationRunV0` shadow record. The normalized compiler is therefore a comparison model over the current compiler, not a second prototype emitter.

The preview is physically split under `tools/lib/mir4`: `NormalizedCompiler.ps1` owns target providers, FeatureManifest/SettingSpec adapters and compilation runs; `SafetyKernel.ps1` owns non-overridable rejection; `PolicyEngine.ps1` owns review dispositions but cannot authorize mutation or override safety; `RuntimeStateModel.ps1` owns runtime and state inventory; `ProcessIR.ps1` owns effect-channel and opportunity models; and `ReleaseDag.ps1` validates the acyclic release workflow. `PlatformPreview.ps1` is the composition and deterministic packaging facade.

`mir4 platform compile` supplies an executable extension-to-shadow loop. It validates MEP V0, binds a target provider, normalizes each fragment, evaluates the hard-safety kernel before policy, and serializes stable diagnostics and a digest without acquiring mutation authority.

`TargetProviderV0` supplies identity, engine, predecessor, capability, and omission facts. It has no callback or emission surface. Historical providers remain private and experimental until separately admitted.

## Developer surfaces

API/SDK V0 carries six read-only envelope types. MEP V0 adds eight bounded data fragments. The reference extension is a declarative consumer and the Inspector is a second independent consumer of Query API snapshots. Both are packaged separately from the Factorio mod.

ProcessIR V0 records effect channels, inputs, outputs, invariants, and loop diagnostics. Autonomous synthesis can only propose one of six dispositions: handle a certified subject, preserve opaque behavior, request an extension, request review, omit with evidence, or fail hard safety with a witness. It cannot emit new gameplay families in 4.0.

The opportunity catalogue scans every declared effect channel and emits evidence-linked `request-review` or `request-extension` candidates. This is immediately usable for compiler tuning, while the absence of mutation authority prevents a confidence score or heuristic from becoming gameplay.

The stable release-DAG contract orders authority, deterministic construction, static proof, runtime proof, performance, manual review, aggregate qualification, signing, sealing, dry runs, restore, exact-tree promotion, tags, publication and public readback. Its executable validator rejects cycles, missing dependencies and any sign, seal, promote, tag or publish node that lacks the separate production go/no-go boundary.

## Commands

```powershell
.\tools\mir.ps1 mir4 platform generate
.\tools\mir.ps1 mir4 platform check
.\tools\mir.ps1 mir4 platform conformance
.\tools\mir.ps1 mir4 platform package
.\tools\mir.ps1 mir4 platform compile --target f210 --extension sdk/preview/mir4/reference-extension/extension.json --output build/results/mir4-shadow/reference-f210.json
```

The first three commands are suitable for development and hosted CI. `package` creates deterministic preview archives under `build/mir4/platform-preview/`; those archives are GitHub developer assets, never Mod Portal payloads. `compile` is the bounded, read-only tuning loop for extension authors and compiler maintainers.
