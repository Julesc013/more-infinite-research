---
title: "MIR 4.1 F2D Runtime Replay"
status: current
applies_to: "M41-F2D"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-01
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-f2d-runtime-replay-operator-guidance
---

# MIR 4.1 F2D runtime replay

F2D proves the accepted 4.0 product as generated from `src/mod` and `targets`; it does not allocate MIR 4.1 or cut over package authority. Run one target and one Factorio process at a time through the existing public CLI:

```powershell
./tools/mir.ps1 mir4 package-source runtime-replay `
  --target f210 `
  --factorio $FactorioBin `
  --work-root $WorkRoot `
  --evidence-root $EvidenceRoot `
  --retention OnFailure
```

Both roots must be absolute, external to the repository, separate, and empty. F210 selects the latest installed official 2.1 experimental engine under the moving-channel policy. Other targets retain their exact historical-engine profiles. Every result binds the exact executable version and hash used by that target.

The coordinator composes `TargetMaterializer`, the `runtime.exact-zip` smoke matrix, and `Test-MIRUpgradeMatrix.ps1`. It does not implement a second materializer or runtime framework. Each upgrade row writes evidence and a containment-checked cleanup receipt before its expanded root is released. `OnFailure` retains failed work, `Always` retains all work, and `Never` removes work even after failure only when explicitly selected.

The evidence root contains the target proof, fresh-load result, upgrade matrix and named row evidence, redacted logs, resource receipt, pre-cleanup custody, independent verification, and final custody manifest. Absolute local paths are forbidden. The independent verifier runs in a fresh PowerShell process before successful cleanup. A passing target remains `NO-CUTOVER`; tagging, signing, sealing, version allocation, publication, writer retirement, and package cutover all remain false.
