---
title: "Fixture Workflow"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-11
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

Compatibility campaign scenarios use schema 2 records in `validation/scenarios/manual.json`, `local-library-scenarios.json`, and `local-library-scenarios-2.0.json`. Do not pass setup policy only through PowerShell. The record must declare targets, kind, group, setup, roots, settings, expected plan boundary, timeout, claim level, and notes. Static validation runs `validation/tests/compatibility/Test-MIRScenarioManifests.ps1`; campaign evidence retains those execution properties next to the exact archive, source commit, dependency lock, actual roots, and result.

A reload-bearing manual scenario additionally declares `runtime_fixtures`, `required_reload_count`, `max_reload_duration_seconds`, and any `required_reload_log_fragments` in the manifest. Reloads are explicit per-scenario opt-ins, limited to two, and preserve distinct stdout, stderr, Factorio-log, duration, and save-hash evidence; scenarios without those fields retain the zero-reload behavior.

