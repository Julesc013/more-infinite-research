---
title: "Fixture Workflow"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Fixture Workflow

Use fixtures to turn compatibility claims, bug reports, and risk cases into
repeatable evidence.

1. Add or update a fixture mod under `fixtures/`.
2. Add a post-MIR assertion fixture when behavior must be proved after MIR runs.
3. Register the fixture in `.mir/fixtures.yml` when it backs a durable claim.
4. Update `.mir/compatibility.yml` or the canonical claim JSON if public wording
   changes.
5. Run static validation first, then runtime validation with a Factorio binary.

Keep fixture names aligned with the behavior they prove. In particular,
reduced-target setting visibility belongs to `reduced-settings-surface`; it
must not be folded into `settings-profile-roundtrip` when the codec is not
shipped on that target.

