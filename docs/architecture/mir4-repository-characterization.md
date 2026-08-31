---
title: "MIR 4 repository characterization"
status: current
applies_to: "MIR 4.x"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-31
supersedes: []
superseded_by: []
generated_from:
  - governance/repository/migrations/repository-characterization-v1.json
---

# MIR 4 repository characterization

M41-05A and M42-00A close the observation gap before any package-source move. They do not move Lua, change package membership, retire a compatibility reader, rewrite the package-visible root README, allocate a version, or publish anything.

The existing migration authorities under `governance/repository/migrations/` remain the declared history. The characterization writer ingests them in the exact order recorded by `.mir/control/repository-fixed-point.json` and emits deterministic reports under ignored `build/reports/repository-characterization/`:

- the complete authority-fact ledger and its last-declared current binding per physical path;
- declared writer and compatibility-reader records;
- a declared reader/writer graph without source-code inference;
- bridge-expiry status that retains every bridge until its own gates are proven;
- the tracked and non-ignored physical-file inventory;
- exact player-package membership and package-source fingerprint;
- documentation routing and front-matter status counts.

Run the supported command surface:

```powershell
.\tools\mir.ps1 mir4 repository characterize
.\tools\mir.ps1 mir4 repository characterization-check
```

The root `README.md` is explicitly recorded as a package-visible bridge with frozen bytes. M41-05B may separate repository and package documentation only after M42-00 establishes the independent target materializer and proves package parity, target-local deltas, rollback, and the new package documentation authority.

Generated reports grant no deletion authority. The reader records are declarations imported from accepted migrations; they do not pretend to be a whole-program static analysis. Any later inferred reader must be added through a separately versioned scanner contract and reconciled with these declared facts.
