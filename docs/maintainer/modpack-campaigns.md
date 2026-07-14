---
title: "Modpack Campaigns"
status: current
applies_to: "3.2.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Modpack Campaigns

Run ecosystems independently before any combined stress scenario. A mega-smash can expose coexistence failures, but it cannot qualify AAI, BZ, Bob, Angel, Krastorio, Space Exploration, Pyanodon, or a planet cluster.

Use an exact MIR candidate archive and bind it to the source commit that produced it:

```powershell
.\scripts\Invoke-MIRCompatAudit.ps1 `
  -RunManualScenarios `
  -ManualScenariosPath .\fixtures\compat-matrix\local-library-scenarios.json `
  -ScenarioNames local-2-1-bz-suite-space-age `
  -LocalModLibraryDirs C:\Projects\Factorio\testmods_2.1 `
  -Offline `
  -IncludeRecommendedDependencies `
  -FactorioLine 2.1 `
  -FactorioVersions 2.1 `
  -FactorioBin $env:FACTORIO_BIN `
  -ModUnderTestZip .\build\validation-dist\more-infinite-research_3.2.0.zip `
  -ModUnderTestSourceCommit <full-commit> `
  -RunLoadTests `
  -OutputDir .\artifacts\campaigns\bz
```

The runner writes `campaign-evidence.json`. Every executed scenario records the MIR archive SHA-256 and source commit, dependency-lock fingerprint, requested and actual roots, exact root and dependency versions with archive SHA-256, result, timeout state, and claim level. Missing archive SHA-256 blocks evidence creation.

`loads` is the default claim level. A passing load proves only that the exact closure reached save creation. It does not prove automatic coverage, progression, balance, migration, or full-pack support. Raise a claim only after its fixture, coverage, upgrade, and interactive gates exist.

Campaign acceptance requires zero dependency failures, an exact candidate binding, no timeouts, and an explicit result for every requested scenario. Coverage acceptance is separate: every recipe must have one stable accounting category, and all dangling effects, unintended duplicate owners, graph cycles, invalid effect types, missing prerequisites, and unreachable generated technologies must be zero.

Do not commit third-party archives. Commit the compact evidence record or lock fingerprint and retain the generated lock under the controlled artifact store.
