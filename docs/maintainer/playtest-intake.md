---
title: "Playtest Intake"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-21
supersedes: []
superseded_by: []
---
# Playtest Intake

Playtest observations are useful only when they are bound to the exact candidate, Factorio installation, mod closure, settings, and save that produced them. Create a bundle with `scripts/New-MIRPlaytestBundle.ps1`; its `report.json` conforms to `verification/schema/playtest-report.schema.json`.

The bundle records the candidate archive/content/source identities, Factorio binary identity, installed official-mod content fingerprints, `mod-list.json`, third-party archive hashes, optional startup-settings and save hashes, the observation, compact compiler fingerprints, and portable attachment hashes. Logs and text artifacts are redacted before copying. Saves are copied only when `-IncludeSave` is explicitly supplied.

Use one of the governed observation categories:

- `startup-failure`, `missing-technology`, `unexpected-technology`, `wrong-recipe-membership`, or `duplicate-owner`;
- `wrong-prerequisite`, `wrong-science`, `unreachable-technology`, `technology-too-early`, or `technology-too-late`;
- `effect-too-large`, `effect-too-small`, `cost-too-large`, or `cost-too-small`;
- `icon-or-locale`, `settings-ux`, `save-or-upgrade`, `performance`, or `sanitation-review-required`.

Before triage, reproduce the observation with the candidate hash in the report. A 3.2 release blocker may reopen the candidate; balance preferences, provider refinements, and proposed technologies go to the post-3.2 tuning workspace. Any package-visible fix invalidates candidate-bound evidence and requires a new archive identity.

Do not publish bundles without inspecting their attachments. The capture script removes known repository/user paths and retains selected MIR/error/warning log lines, but it cannot prove that arbitrary mod output contains no private data.
