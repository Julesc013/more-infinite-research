---
title: "Migrating MEP V0 to V1"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-mep-v0-to-v1-developer-migration
---

# Migrating MEP V0 to V1

Run the bundled `migrate` command with a V0 envelope and a new output directory. The converter creates V1 data but does not overwrite the input:

```powershell
& tools/mir/cli/Invoke-MIR4Extension.ps1 -Command migrate -RepoRoot . -ExtensionPath old/extension.json -OutputRoot migrated
& tools/mir/cli/Invoke-MIR4Extension.ps1 -Command validate -RepoRoot . -ExtensionPath migrated/extension-v1.json
```

Review target constraints, unavailable values, dependency order, diagnostics, and the new digest. Migration grants no player authority; repeat lock, explain, test, and package.
