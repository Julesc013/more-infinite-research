---
title: "Generated Reference Views"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-03
supersedes: []
superseded_by: []
---

# Generated Reference Views

Files in this directory are deterministic projections of machine-readable authorities. Run `./tools/commands/docs/Update-MIRGeneratedAuthorityDocs.ps1` after changing their sources; architecture validation runs the same command with `-Check` and rejects drift.

The source authority is named at the top of each generated document. Do not edit generated tables by hand.
