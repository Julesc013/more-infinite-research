---
title: "MIR 4 Platform Preview Architecture"
status: current
applies_to: "4.0.0 candidate programme"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
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

The preview is physically split under `tools/lib/mir4`: `NormalizedCompiler.ps1` owns target providers, FeatureManifest/SettingSpec adapters and compilation runs; `SafetyKernel.ps1` owns non-overridable rejection; `PolicyEngine.ps1` owns review dispositions but cannot authorize mutation or override safety; `RuntimeStateModel.ps1` owns runtime and state inventory; `ProcessIR.ps1` owns package-excluded ProcessIR certificates, effect-channel owner references, and proposal classification; and `ReleaseDag.ps1` validates the acyclic release workflow. `PlatformPreview.ps1` is the composition and deterministic packaging facade.

`mir4 platform compile` supplies an executable extension-to-shadow loop. It validates MEP V0, binds a target provider, normalizes each fragment, evaluates the hard-safety kernel before policy, and serializes stable diagnostics and a digest without acquiring mutation authority.

`TargetProviderV0` supplies identity, engine, predecessor, capability, and omission facts. It has no callback or emission surface. Historical providers remain private and experimental until separately admitted.

## Developer surfaces

API/SDK V0 carries six read-only envelope types. MEP V0 adds eight bounded data fragments. The reference extension is a declarative consumer and the Inspector is a second independent consumer of Query API snapshots. Both are packaged separately from the Factorio mod.

ProcessIR V1 derives deterministic process identities, exact/bounded flows, catalysts, returned containers, recycling/recovery classifications, self-intersections, SCCs, and minimal witnesses from copied canonical fact transports. It preserves terminal risk fingerprints and treats incomplete evidence as `UNKNOWN`. The repository currently has only a synthetic fixture corpus, so exact-target parity is explicitly blocked.

Autonomous synthesis V1 exposes ten descriptive constructors across Diagnose, Conservative, and Experimental modes. Known unsafe candidates fail hard safety, known safe candidates remain preview-admissible or explicitly quarantined, and no candidate becomes a player operation. Effect channels retain their existing semantic owners; opaque channels remain opaque.

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
