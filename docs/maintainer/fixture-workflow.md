---
title: "Fixture Workflow"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-10
supersedes: []
superseded_by: []
---

# Fixture Workflow

Use fixtures to turn compatibility claims, bug reports, and risk cases into repeatable evidence.

1. Add or update a fixture mod under `fixtures/`.
2. Add a post-MIR assertion fixture when behavior must be proved after MIR runs.
3. Register the fixture in `.mir/fixtures.yml` when it backs a durable claim.
4. Update `.mir/compatibility.yml` or the canonical claim JSON if public wording changes.
5. Run static validation first, then runtime validation with a Factorio binary.

Keep fixture names aligned with the behavior they prove. In particular, reduced-target setting visibility belongs to `reduced-settings-surface`; it must not be folded into `settings-profile-roundtrip` when the codec is not shipped on that target.

Compatibility campaign scenarios use schema 2 records in `validation/scenarios/manual.json`, `local-library-scenarios.json`, and `local-library-scenarios-2.0.json`. Do not pass setup policy only through PowerShell. The record must declare targets, kind, group, setup, roots, settings, expected plan boundary, timeout, claim level, and notes. Static validation runs `tests/compatibility/Test-MIRScenarioManifests.ps1`; campaign evidence retains those execution properties next to the exact archive, source commit, dependency lock, actual roots, and result.

A reload-bearing manual scenario additionally declares `runtime_fixtures`, `required_reload_count`, `max_reload_duration_seconds`, and any `required_reload_log_fragments` in the manifest. Reloads are explicit per-scenario opt-ins, limited to two, and preserve distinct stdout, stderr, Factorio-log, duration, and save-hash evidence; scenarios without those fields retain the zero-reload behavior.

The existing [Bob Tin continuation runner](../../tests/runtime/Test-MIRF210CurrentBobTinLevel4Continuation.ps1) and [K2 Imersite continuation runner](../../tests/runtime/Test-MIRK2213ImersiteContinuation.ps1) accept `-SourceVersion 4.2.2` with a supplied current `4.2.21002` package and its canonical materialization receipt. Omitting the option retains the `4.2.1` default and rejects a `4.2.21002` package. K2 also requires the matching [4.2.2 input profile](../../fixtures/run-profiles/k2-213-imersite-f210-422.json); the [4.2.1 profile](../../fixtures/run-profiles/k2-213-imersite-f210.json) remains available. Both profiles use assertion fixture `0.1.4`, which preserves the powder/crystal ownership, output and saved-progress assertions while accepting those two explicit MIR versions. The runner verifies the selected version, archive bytes and loaded mod selection. Older fixture archives and native receipts remain historical inputs under their original identities; these caller changes establish no fresh gameplay result. The separate [Lua version controls](../../tests/runtime/k2_imersite_version_controls.lua) execute the actual data and runtime fixture guards with supplied source strings and controlled tables; they do not simulate production or save serialization.

The [Research Library graphical runner](../../tests/runtime/Test-MIRResearchBrowser.ps1) and [personal-state lifecycle runner](../../tests/runtime/Test-MIRBrowserPersonalStateContinuity.ps1) also accept explicit `-SourceVersion 4.2.2` for `4.2.21002` or `4.2.20002` candidates. Their default remains `4.2.1`; selecting one source version does not admit a package from the other. Supply the engine and flat library explicitly, with the selected candidate and exact prepared assertion fixtures already present. The graphical runner's target values are `2.1`/`2.0`; the lifecycle runner uses `F210`/`F200`. Lifecycle `ScriptedFixture` remains F200-only and does not establish physical mouse or keyboard interaction. Host controls exercise argument binding, actual archive readers, library selection and the owned-worker protocol; graphical startup, two-client lifecycle and save acceptance still require their selected native runs.

The A04 [modern launch-return scenario](../../fixtures/assert-modern-launch-return/scenario.json) selects exact F200/F210 engines and a supplied source-4.2.2 candidate. Run [Test-MIRModernLaunchReturn.ps1](../../tests/runtime/Test-MIRModernLaunchReturn.ps1) with `-Target`, `-FactorioExe`, `-LibraryDirectory`, `-CandidateZip` and `-SourceMaterializationPath`. The candidate must already exist once in the selected library with matching bytes. Use `-PrepareInputs` once to install the small assertion fixture under the existing library lock; its only generated variation is exact target metadata. Preparation refuses different bytes already occupying the same fixture identity. It restores the previous control files and starts no engine. Normal execution reads archives directly, activates default settings and disables unselected mods through the existing library adapter. All run output stays under the checkout.

The fixture grants prerequisites, places a silo, landing pad and lab, supplies non-space inputs and power, and accelerates ticks. It changes no recipes, rocket-part counts or research-progress values. The engine must consume the construction inputs, launch a satellite, deliver 1000 space science and consume a transferred portion in the lab. A saved completed result is then independently reloaded. This is a prepared focused acceptance test; until executed, it establishes no native, graphical, upgrade or full-playthrough acceptance. [Observation-reader controls](../../tests/runtime/Test-MIRModernLaunchReturnStatic.ps1) run without Factorio. The separate [Lua controls](../../tests/runtime/modern_launch_return_controls.lua) execute the fixture callbacks with simulated engine objects when supplied its exact `control.lua` bytes; they do not simulate or qualify Factorio's production or save serialization.

