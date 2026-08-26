---
title: "Environment Locks, Diffs, and Support Bundles"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-environment-evidence-developer-guide
---

# Environment locks, diffs, and support bundles

EnvironmentLockV1 binds the Factorio target, engine, MIR identity, ordered mods, configuration, and evidence inputs. EnvironmentDiffV1 reports structured changes between two valid locks. SupportBundleV1 binds a failure proposition to its lock, observations, diagnostics, and custody.

Use `tools/commands/mir4/Invoke-MIR4EnvironmentEvidence.ps1` in the repository, or the matching bundled interface, to create and validate records. Generate a minimized bundle only after reproducing the same proposition; minimization cannot broaden the claim.

Commit reusable synthetic locks and fixtures. Keep personal paths, credentials, saves, proprietary mods, and machine secrets out of support bundles.
