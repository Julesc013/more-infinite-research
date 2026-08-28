---
title: "MIR 4 Platform Preview Architecture"
status: current
applies_to: "4.0.0 candidate programme"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-hybrid-platform-boundary
  - shadow-non-interference
---
# MIR 4 Platform Preview Architecture

MIR 4.0 has one stable player plane and one package-excluded developer plane. The player plane continues to use the existing compiler and emission boundary. The developer plane projects that compiler's governed inputs and public artifacts into deterministic, read-only contracts.

## Maturity and authority

`Stable` components may affect admitted player distributions. `Shadow` components execute and compare but cannot affect output. `Preview` components are usable developer products whose compatibility may change before 1.0. `Experimental` components are disabled by default. `Omitted by target` requires a target-local reason and evidence reference.

Anything below Stable is forbidden from mutating prototypes, settings, persistent state, migrations, support claims, hard-safety decisions, or player-package membership. The platform conformance gate proves package-source identity is unchanged by generation.

## One compiler, two observations

`LegacyCompilerHostAdapterV1` reads the existing target snapshots, stream manifest, compatibility manifest, fixture manifest, module boundaries, and package surface. It emits an immutable `CompilationRunV0` shadow record. The normalized compiler is therefore a comparison model over the current compiler, not a second prototype emitter.

The preview is physically split across visible roots. `tools/mir/application/compiler/NormalizedCompiler.ps1` owns target providers and FeatureManifest/SettingSpec adapters, `tools/mir/application/compiler/CompilationRun.ps1` owns semantic reference runs, `tools/mir/domain/safety/SafetyKernel.ps1` owns non-overridable rejection, `tools/mir/domain/policy/PolicyEngine.ps1` owns review dispositions but cannot authorize mutation or override safety, and `tools/mir/application/runtime/RuntimeStateModel.ps1` owns runtime/state inventory and migration-law projections. `tools/mir/application/processir/ProcessIR.ps1` owns package-excluded ProcessIR certificates, effect-channel owner references, and proposal classification. `tools/mir/application/release/ReleaseDag.ps1` validates the acyclic release workflow; its former `tools/lib/mir4` path is a read-only compatibility forwarder. `PlatformPreview.ps1` is the composition and deterministic packaging facade.

`mir4 platform compile` supplies an executable extension-to-shadow loop. The V1 developer surface validates typed MEP V1 data; the original V0 loop remains a migration-compatibility input. Both bind a target provider, normalize each fragment, evaluate the hard-safety kernel before policy, and serialize stable diagnostics and a digest without acquiring mutation authority.

`TargetProviderV0` supplies identity, engine, predecessor, capability, and omission facts. It has no callback or emission surface. Historical providers remain private and experimental until separately admitted.

## Developer surfaces

API/SDK V1 carries nine copied, bounded, capability-labelled surfaces. MEP V1 adds 12 typed data fragments. The reference extension and Inspector are synthetic first-party conformance consumers, packaged separately from the Factorio mod. Independent production-consumer acceptance remains open for component graduation. V0 is retained only for V0-to-V1 migration testing.

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
