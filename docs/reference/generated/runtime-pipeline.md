---
title: "Generated Runtime Pipeline"
status: current
applies_to: "4.0.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-02
supersedes: []
superseded_by: []
---

# Generated Runtime Pipeline

<!-- BEGIN GENERATED MIR PIPELINE -->
This package-excluded reference is generated from `src/mod/families/modern/prototypes/mir/pipeline/commands.lua`; run `./scripts/Update-MIRPipelineDocumentation.ps1` after changing the command DAG.

| Phase | Command | Kind | Implementation | Depends on |
| ---: | --- | --- | --- | --- |
| 10 | `compatibility-repairs` | mutation | `prototypes/mir/compatibility/repairs/registry.lua` | none |
| 12 | `recipe-productivity-permissions` | mutation | `prototypes/mir/pipeline/recipe_productivity_permissions.lua` | `compatibility-repairs` |
| 15 | `sanitize-input-technology-effects` | sanitation | `prototypes/mir/emit/effect_safety.lua` | `recipe-productivity-permissions` |
| 20 | `module-permissions` | mutation | `prototypes/mir/pipeline/module_permissions.lua` | `sanitize-input-technology-effects` |
| 20 | `prototype-limits` | mutation | `prototypes/mir/pipeline/prototype_limits.lua` | `compatibility-repairs`, `module-permissions` |
| 20 | `pipeline-extent` | mutation | `prototypes/mir/pipeline/extent.lua` | `compatibility-repairs`, `prototype-limits` |
| 30 | `prepare-competing-productivity` | plan | `prototypes/mir/policy/competing_productivity.lua` | `pipeline-extent` |
| 30 | `prepare-competing-base-extensions` | plan | `prototypes/mir/policy/competing_base_extensions.lua` | `prepare-competing-productivity` |
| 35 | `compile-generation-plan` | plan | `prototypes/mir/pipeline/compiler_orchestrator.lua` | `prepare-competing-base-extensions` |
| 40 | `emit-streams` | emission | `prototypes/mir/emit/stream_executor.lua` | `compile-generation-plan` |
| 50 | `apply-competing-productivity` | mutation | `prototypes/mir/pipeline/mutations/competing_productivity.lua` | `emit-streams` |
| 50 | `emit-base-extensions` | emission | `prototypes/mir/planner/base_continuations.lua + prototypes/mir/emit/base_continuation_executor.lua` | `apply-competing-productivity` |
| 60 | `apply-competing-base-extensions` | mutation | `prototypes/mir/pipeline/mutations/competing_base_extensions.lua` | `emit-base-extensions` |
| 70 | `weapon-speed-adjustments` | mutation | `prototypes/mir/pipeline/mutations/weapon_speed.lua` | `apply-competing-base-extensions` |
| 70 | `max-level-control` | mutation | `prototypes/mir/pipeline/mutations/max_level.lua` | `weapon-speed-adjustments` |
| 75 | `assert-technology-safety` | assertion | `prototypes/mir/emit/effect_safety.lua` | `max-level-control` |
| 80 | `emit-compatibility-diagnostics` | report | `prototypes/mir/compatibility/diagnostics/registry.lua` | `assert-technology-safety` |
| 80 | `emit-compiler-reports` | report | `prototypes/mir/planner/compiler.lua` | `emit-compatibility-diagnostics` |
| 80 | `emit-compatibility-planner` | report | `prototypes/mir/compatibility/planner.lua` | `emit-compiler-reports` |
| 90 | `assert-plan-output` | assertion | `prototypes/mir/planner/output_validator.lua` | `emit-compatibility-planner` |
| 92 | `apply-maximum-level-presentation` | emission | `prototypes/mir/pipeline/mutations/maximum_level_presentation.lua` | `assert-plan-output` |
| 95 | `publish-compiler-artifacts` | publication | `prototypes/mir/pipeline/compiler_orchestrator.lua` | `apply-maximum-level-presentation` |
| 100 | `flush-diagnostics` | report | `prototypes/mir/report/diagnostics_sink.lua` | `publish-compiler-artifacts` |
<!-- END GENERATED MIR PIPELINE -->
