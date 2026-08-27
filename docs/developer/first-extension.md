---
title: "Your First MIR 4 Extension from a Preview Archive"
status: current
applies_to: "MIR 4.0.0 developer preview"
audience: developer
doc_type: tutorial
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-clean-archive-first-extension
---

# Your first MIR 4 extension from a preview archive

Extract `mir4-mep-v1-preview.zip` into an empty directory, enter its `mir4-mep-v1-preview` root, and run PowerShell 7:

```powershell
$root = (Get-Location).Path
$command = Join-Path $root 'tools/mir/cli/Invoke-MIR4Extension.ps1'
& $command -Command doctor -RepoRoot $root
& $command -Command init -RepoRoot $root -ExtensionId org.example.first -Template minimal -OutputRoot work/first
& $command -Command validate -RepoRoot $root -ExtensionPath work/first/extension.json
& $command -Command lock -RepoRoot $root -ExtensionPath work/first/extension.json -Target f210 -OutputRoot work/first
& $command -Command explain -RepoRoot $root -ExtensionPath work/first/extension.json -Target f210
& $command -Command test -RepoRoot $root -ExtensionPath work/first/extension.json -Target f210
& $command -Command package -RepoRoot $root -ExtensionPath work/first/extension.json -OutputRoot work/package
```

Expected results are `passed`, `initialized`, `valid`, a target lock, a read-only shadow explanation, a passing shadow test, and a deterministic developer ZIP. F210 currently reports `review-required` for transport because player emission remains blocked behind the terminal emitter.

Edit only `work/first/extension.json`. Replace placeholder subject references with stable identifiers, then repeat validate, lock, explain, and test. The archive requires no repository checkout or network access.
