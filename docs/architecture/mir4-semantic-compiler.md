---
title: "MIR 4 Semantic Compiler Shadow"
status: current
applies_to: "4.0.0 M4C02-09"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-compilation-run-v1
  - mir4-provider-micro-protocol-adapter
  - mir4-merge-law-catalogue
  - mir4-feature-setting-cutover
---
# MIR 4 Semantic Compiler Shadow

The package-excluded semantic compiler is now owned by visible canonical roots: `tools/mir/domain/safety/SafetyKernel.ps1`, `tools/mir/domain/policy/PolicyEngine.ps1`, `tools/mir/application/compiler/NormalizedCompiler.ps1`, and `tools/mir/application/compiler/CompilationRun.ps1`. Deterministic record export is owned by `tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1`. The former `tools/lib/mir4` and `tools/commands/mir4` paths are read-only compatibility forwarders and are not writers.

W03 completes a reference-based `CompilationRunV1` without creating a second player compiler. Each run binds the W02 target contract and provider, the platform input lock, module closure, terminal normalized snapshot, existing fact and graph adapters, policy and claim owners, lifecycle plans, operation executor, runtime inventory, proof obligations, and bounded public projection authority.

`FeatureManifestRefV1` and `SettingSpecRefV1` are aggregate indexes. They reference the terminal snapshot, target profile, settings manifest, and existing Lua owners; they do not copy facts, policies, plans, or runtime records. `CompilerContext` remains the outer lifecycle compatibility adapter, and all terminal Lua planning, mutation execution, journals, results, and public artifacts remain player-authoritative.

The provider micro-protocol matrix maps the existing data-only `CompilerProvider` contract to thirteen concern interfaces without rewriting built-ins. It can read declared provider fields and emit package-excluded shadow records. It cannot invoke callbacks, mutate prototypes or runtime state, execute migrations, or publish.

The merge-law catalogue executes adapters for hard safety, target support, feature disable, ownership, science packs, prerequisites, numeric values, presentation, diagnostics, and evidence. Subscription and migration laws remain explicitly deferred to W04; a deferred row is not reported as passed.

The seven named lifecycle plans are references to current owners. `PrototypeMutationPlan` keeps the existing executor, runtime registration and migration remain W04-owned, and publication remains blocked by W00 release governance. W03 authorizes no executor and changes no player-package file.

Rollback removes `CompilationRunV1` and the package-excluded projections. It does not touch `CompilerContext`, the terminal planner, any executor, runtime state, migrations, journals, results, or public mod-data.
