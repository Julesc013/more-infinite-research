---
title: "MIR 4 maintainer authority map"
status: current
applies_to: "MIR 4.x"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-09-05
supersedes: []
superseded_by: []
generated_from:
  - governance/repository/migrations/repository-characterization-v1.json
  - governance/repository/migrations/current-product-bridge-retirement-v1.json
source_of_truth_for:
  - mir4-maintainer-authority-map
---

# MIR 4 maintainer authority map

This page routes maintainers to authorities; it is not a second hand-maintained path ledger. Generate the exact current ledger with:

```powershell
.\tools\mir.ps1 mir4 repository characterize
```

The resulting `build/reports/repository-characterization/authority-ledger.json` contains every declared migration fact and the last accepted binding per final path. Its companion writer, reader, graph, bridge-expiry, physical-file, package-membership, and documentation-routing reports share the same immutable input set.

| Concern | Editable authority | Projection or evidence |
| --- | --- | --- |
| repository migration history | `governance/repository/migrations/*.json` ordered by `.mir/control/repository-fixed-point.json` | characterization bundle |
| accepted release changes | `changes/unreleased/*.json` and released history | generated changelogs and release narratives |
| player package membership | `src/mod/package-source.json`, `targets/package-authority.json`, and target overlays | package-membership report and generated target packages |
| current development execution | `spec/execution/mir4-4.1-development-context-v1.json` | exact engine and candidate evidence |
| historical compatibility bridges | `governance/repository/migrations/current-product-bridge-retirement-v1.json` | bridge-expiry report and succession receipt |
| documentation metadata | Markdown front matter | `.mir/docs.yml` and documentation indexes |
| verification selection | `.mir/assurance.json` and `validation/tests.yml` | materialized verification plan and aggregate gate |
| branch roles | `spec/branches/mir4-branch-operating-model-v1.json` | ruleset receipts and branch readback |
| immutable release preservation | release records and external archive custody | manifests, seals, signatures, restore receipts |

Generated projections are checked fixed points, never competing editable authorities. Historical release records stay immutable. The current bridge authority records zero current-product authority bridges; retained compatibility paths are read-only, package-excluded, unused by current semantics, owned, tested, and expiry-bounded. No report independently authorizes deletion, package movement, signing, tagging, or publication.
