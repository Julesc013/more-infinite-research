---
title: "Testing And Fixture Strategy"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-07
supersedes: []
superseded_by: []
---
# Testing And Fixture Strategy

Updated: 2026-10-07

The 3.0 compatibility compiler needs tests for both positive emission and negative safety. The goal is not only "the mod loads." The goal is proving that MIR emits, skips, rejects, and reports exactly what the policy says.

Current verification selection uses the declared inputs in `validation/tests.yml`, the existing assurance classes and `.mir/test-impact.yml`. `Test-MIRResearchabilityPlanning.ps1` consumes both `researchability_planning.lua` and `lab_reachability.lua`; its registry input and receipt hashes must include both. `Test-MIRRecipeSourceEpoch.ps1` consumes `recipe_source_epoch.lua`. Both exact acquisition fixtures map to their existing consumers and affected science scenarios. The selector's own known static test has no additional native scenarios. Unowned fixtures and tooling scripts retain conservative coverage. These exact mappings retain the broader static harness policy and grant no native acceptance.

The selection contract itself can be checked without Factorio or dependency archives:

```powershell
.\tests\tooling\Test-MIRDevelopmentCISelection.ps1 -PureSelectionOnly
```

Native lab, emitted research, production, save, multiplayer and engine performance claims still need their selected current-package scenario. Prepare only those affected scenarios from manifests over the shared dependency library, using verified same-volume hard links and private writable settings and saves. Keep compact results and required reproducers after completion; do not retain copied modpacks or count linked ZIP lengths as reclaimed physical storage.

When the hosted `static.mir4-platform-preview` worker fails on a stale generated projection, the same worker can preserve a separate SDK generation repair artifact. It invokes the existing complete fixed-point writer from the exact clean checkout and exports only changed files returned by that writer, with paths, hashes, source commit/tree, player-source fingerprint and run identity. The output is limited to 16 MiB; no player package or dependency archive is constructed. The original test and verification gate remain failed. Before adopting these bytes locally, verify the producer and exact source, all file hashes and generated path scope; preserve any local changes. Commit the generated corrections and obtain fresh required checks before integration. This artifact provides generated source for repair; it grants no native, release or signing acceptance.

## Test Pyramid

### Static Tests

- schema validation;
- stable sort helpers;
- stable ID generation;
- architecture import-direction linting;
- policy linter;
- claim linter;
- manifest linter;
- `DecisionRecord` validator;
- `StreamSpec` validator;
- settings parser;
- package hygiene;
- no forbidden runtime tick handlers.

### Synthetic Runtime Fixtures

- base recipe productivity;
- self-loop recipe;
- barrel/container return loop;
- filter cleaning loop;
- catalyst return loop;
- voiding sink;
- recycling recipe;
- matter/transmutation loop;
- hidden valid-looking recipe;
- recipe with `maximum_productivity = 0`;
- external owner exact match;
- external owner value mismatch;
- lab with no compatible science packs;
- science dependency cycle;
- loader-like item that is not a loader;
- mining-drill-like item that is not a mining drill;
- machine with base productivity;
- beacon/recycler/module rule-surface observer.

### Real Mod Fixtures

- base;
- Space Age;
- Air Scrubbing;
- ATAN Ash;
- ATAN Nuclear Science;
- AAI Loaders;
- AAI Industry;
- Big Mining Drill;
- Fluid Must Flow;
- Robot Attrition;
- Jetpack;
- Equipment Gantry;
- Krastorio 2;
- Krastorio 2 Spaced Out;
- Bob's focused material subsets;
- Angel/Bob material signal fixture;
- Space Exploration lane;
- Py-style material-family smoke fixture.

## Golden Outputs

Each fixture should assert:

- facts exported;
- candidates discovered;
- classifications stable;
- decisions stable;
- generated streams match expected;
- rejected recipes match expected;
- unknown candidates bounded;
- science packs researchable;
- labs compatible;
- no duplicate owners;
- no unexpected prototype mutations;
- package hygiene preserved.

## Report Diffing

Use report diffing when a mod updates or a classifier changes:

```powershell
.\tools\commands\planner\Compare-MIRPlannerReports.ps1 `
  -Before build\previous\mir-planner `
  -After build\current\mir-planner
```

The diff should summarize:

- new generated streams;
- removed generated streams;
- target recipe changes;
- new unknown candidates;
- resolved unknown candidates;
- new loop risks;
- new owner conflicts;
- new lab/science incompatibilities;
- cap changes;
- claim-level changes;
- package content changes.

## Release Gate

For 3.0 release candidates, require:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin '<Factorio 2.1 binary>'
.\tools\mir.ps1 release gate --profile release-targeted-2.1 --no-git-pull
git diff --check
```

Any generated report changes must be explained by source changes or restored if they are only local run churn.
