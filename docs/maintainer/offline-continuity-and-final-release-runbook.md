---
title: "MIR 2.5.0 Offline Continuity And Final Release Runbook"
status: current
applies_to: "Control Plane v5, MIR 3.2.2 C24, and MIR 2.5.0 P9"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-30
supersedes: []
superseded_by: []
---

# MIR 2.5.0 Offline Continuity And Final Release Runbook

This runbook preserves the exact release path when network access is unreliable. It does not relax package identity, human review, protected-runner, seal, or promotion gates.

## Frozen identities

| Release | Candidate | Package source | Archive SHA-256 | Content SHA-256 | Bytes / entries |
| --- | --- | --- | --- | --- | --- |
| MIR 3.2.2 | C24 | `29f81addc0eec9b571afd6428c9e3529c4497a1b` | `8A08758EECEEE3A930DE58A36395DD011F9BC2FB69D214CCAFFC065276ECF8D8` | `25E05F748E5B33748F16F78C66DDE4FD11CB48DB5F499BBE232668746981C87F` | 1,030,817 / 291 |
| MIR 2.4.9 | final | `ecd875bceda8f373c3dd8a9b3393e9626b5dec4c` | `B5503F94D04624F65462CC275FB6AA71A8CE93075F732DF498F6D73AD255F978` | `23D992943090BFF487675E9DF8C5C12BFDB1F3018B0BF04C9928265E5DC95255` | 893,263 / 209 |
| MIR 2.5.0 | 2.5-P9 | `f446d89f94ce4b9dc26f04c31c92f9bcffbac70d` | `30D7205527F3643169799AD8AF87C313D35DB81B14A6BDD460D9ED4D1B819DE3` | `02442BE983D20FEB45D0657FA7DE0198C49332B747CE509673932270EED66BC2` | 1,029,914 / 290 |

P9 is anchored to tag `2.4.9`, tag `3.2.2`, and dual-parent integration commit `96a269872ddb19716f00c586bc9534beb7eadfc4`. Do not change C24 or P9 package identity without a demonstrated product defect and a new candidate.

## Branch authority

`main`, `dev`, and `legacy` are permanent. `tmp/2.0` is the active disposable target workspace. `legacy` advances only through governed promotion from `tmp/2.0`.

Before acting on any recorded head, fetch and compare it. A head printed in a handoff is a snapshot, not authority.

```powershell
$cp = 'C:\Projects\Factorio\more-infinite-research'

git -C $cp fetch --all --tags --prune
git -C $cp branch -a -vv
git -C $cp show-ref
```

## Offline preflight

The following inputs must be local before disconnection:

- exact Factorio 2.1.12 executable and official modules;
- exact Factorio 2.0.77 executable and official modules;
- `testmods_2.1` and `testmods_2.0` archive closures;
- exact MIR 3.2.1, 3.2.2, 2.4.9, and P9 ZIPs;
- exact C24 and P9 source checkouts;
- the v5 evidence store and every immutable verification context in use.

Do not substitute another Factorio patch version. On the 2026-07-30 local audit, Factorio 2.1.12 and both mod closures were present, but an exact real Factorio 2.0.77 executable was not found. P9 runtime qualification must stop at that boundary until it is captured.

## Capture committed history

Create the handoff outside the repository so it cannot affect plans or package construction.

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$handoff = "C:\Projects\Factorio\offline-handoff-$stamp"

New-Item -ItemType Directory -Force $handoff | Out-Null
git -C $cp show-ref | Set-Content "$handoff\show-ref.txt"
git -C $cp branch -a -vv | Set-Content "$handoff\branches.txt"
git -C $cp worktree list --porcelain | Set-Content "$handoff\worktrees.txt"
git -C $cp status --porcelain=v2 --branch | Set-Content "$handoff\primary-status.txt"
git -C $cp bundle create "$handoff\more-infinite-research-all.bundle" --all
git bundle verify "$handoff\more-infinite-research-all.bundle" | Set-Content "$handoff\bundle-verify.txt"
git -C $cp fsck --full | Set-Content "$handoff\git-fsck.txt"
```

A Git bundle does not include dirty working-tree bytes. The custody bundles at `C:\Projects\Factorio\recovery\legacy-dirty-2026-07-29` and `C:\Projects\Factorio\recovery\mir-250-prep-dirty-2026-07-29` preserve those separately. Do not reset, merge wholesale, or delete either original dirty worktree.

## C24 preflight

Use an exact checkout at C24 package source `29f81add...`, not the `dev` controller worktree, as `SourceRepoRoot`. The controller worktree itself must also be clean and committed when the immutable context is created.

```powershell
$source21 = 'C:\tmp\mir-c24-shadow-source-20260729'
$factorio21 = 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
$prior21 = "$cp\dist\more-infinite-research_3.2.1.zip"
$mods21 = 'C:\Projects\Factorio\testmods_2.1'
$contextRoot = 'C:\Projects\Factorio\v5-contexts'
$evidenceRoot = 'C:\Projects\Factorio\v5-evidence'

& "$cp\scripts\Invoke-MIRControlPlane.ps1" validate -AllLocks -RepoRoot $cp
& "$cp\scripts\Invoke-MIRControlPlane.ps1" views -Check -RepoRoot $cp
& "$cp\scripts\Invoke-MIRControlPlane.ps1" registry -Check -RepoRoot $cp
& "$cp\scripts\Invoke-MIRControlPlane.ps1" replay -Check -RepoRoot $cp
& "$cp\validation\tests\tooling\Test-MIRControlPlane.ps1" -RepoRoot $cp
& "$cp\validation\tests\tooling\Test-MIRControlPlaneShadow.ps1" -ContractOnly -RepoRoot $cp
& "$cp\validation\tests\tooling\Test-MIRControlPlaneExecutor.ps1" -RepoRoot $cp
& "$cp\validation\tests\tooling\Test-MIRControlPlaneRelease.ps1" -RepoRoot $cp
& "$cp\validation\tests\tooling\Test-MIRControlPlaneWorkflow.ps1" -RepoRoot $cp
```

The parameterless shadow command is not a preflight. Operational shadow evaluation requires one immutable context and exact source checkout; `-ContractOnly` is the correct pre-context check.

## Fresh C24 calibration

Never resume a context after changing the controller. Create a new context and new evidence root.

```powershell
$context = & "$cp\scripts\Invoke-MIRControlPlane.ps1" context `
  -Mode calibrate-fresh `
  -Target 2.1 `
  -Release 3.2.2 `
  -CandidatePath "$cp\dist\more-infinite-research_3.2.2.zip" `
  -SourceRepoRoot $source21 `
  -ContextOutputRoot $contextRoot `
  -RepoRoot $cp | ConvertFrom-Json

& "$cp\scripts\Invoke-MIRControlPlane.ps1" calibrate `
  -ContextPath $context.path `
  -FactorioBin $factorio21 `
  -PriorRelease $prior21 `
  -LocalModDir $mods21 `
  -LocalModZipDir $mods21 `
  -SourceRepoRoot $source21 `
  -EvidenceRoot $evidenceRoot `
  -TrustClass ci `
  -RepoRoot $cp

& "$cp\scripts\Invoke-MIRControlPlane.ps1" calibration-proof `
  -ContextPath $context.path `
  -EvidenceRoot $evidenceRoot `
  -Output 'validation/baselines/control/3.2.2-v5-fresh-calibration.json' `
  -RepoRoot $cp
```

`calibrate` is intentionally C24-only, and its admissible local calibration trust class is `ci`. Do not use the nonexistent `local-calibration` trust class. The calibration command itself resolves `qualification.full`; the protected `qualification` command is a separate release-stage operation and must not be applied to this verification-stage local context.

Acceptance requires all atomic tasks, all 113 process-required environment batches, upgrade, ecosystem, native approved delta, exact paired performance, the exact C24 historical manual proof, both aggregates, zero invalid reuse, and zero impact false negatives.

After the proof passes, close INC-2026-0036, INC-2026-0037, and INC-2026-0038 with exact object digests; regenerate shadow analysis and views; set v4/v5 equivalence to `accepted`; document v4 sunset; and create an annotated toolchain candidate tag. Do not create that tag earlier.

## P9 local work

P9 remains package-frozen while target-side qualification fixtures may advance. Use the accepted controller on `dev` with the exact `tmp/2.0` source checkout and P9 archive.

The C24 `calibrate` command cannot execute P9. Before local P9 qualification, the controller must expose and test a candidate-local execution facade that runs the release-stage plan without claiming protected trust. Until that facade exists, create and inspect the P9 plan and context but do not mislabel hand-run evidence as a completed candidate qualification.

```powershell
$source20 = 'C:\tmp\mir-p9-qualification-source-20260729'
$factorio20 = '<exact Factorio 2.0.77 executable>'
$prior20 = "$cp\dist\more-infinite-research_2.4.9.zip"
$mods20 = 'C:\Projects\Factorio\testmods_2.0'

& "$cp\scripts\Invoke-MIRControlPlane.ps1" plan `
  -Mode calibrate-fresh `
  -Stage release `
  -Target 2.0 `
  -Release 2.5.0 `
  -SourceRepoRoot $source20 `
  -Output 'out/control-plane-v5-p9-release-plan.json' `
  -RepoRoot $cp
```

The eventual local facade must run target static/package tasks, Base and official DLC loads, the complete 2.0 runtime catalog, exact Py closure, the 2.4.9 upgrade, 319-row approved delta, operation-set randomized-order invariance, paired performance on an idle host, manual acceptance admission, and the candidate aggregate. It must emit non-release-eligible local evidence. Protected qualification must rerun protected-fresh obligations and consume only protected evidence.

## P9 manual acceptance

The maintainer may review P9 offline. The attestation must bind archive `30D720...9DE3`, content `02442B...BC2`, package source `f446d89...`, exact Factorio 2.0.77 identity, and the reviewed artifacts. A P6 or emergency-build attestation is invalid.

Review the technology tree, icons, locale fit, settings UX, save UI, balance, configuration-change item safety, 2.4.9 upgrade, Py stale-unlock correction, and absence of unsupported 2.1-only effects.

## Internet-only boundary

The following operations require remote or protected authority:

1. push accepted v5 commits and the toolchain tag;
2. push accepted P9 qualification and manual-attestation commits;
3. dispatch protected Factorio 2.0 qualification;
4. download and independently verify its artifact and seal;
5. admit promotion;
6. fast-forward `legacy` from `tmp/2.0`;
7. push annotated tag `2.5.0`;
8. publish releases and verify public bytes.

Never replace these with local untrusted evidence.

## Final promotion checks

Before tagging, prove:

- promotion is a fast-forward;
- `2.4.9` and `3.2.2` are ancestors through the governed dual-parent lineage;
- P9 ZIP identity is unchanged;
- the protected seal and independent verification pass;
- promotion admission passes;
- tag `2.5.0` is absent locally and remotely.

Only then fast-forward `legacy` and create the annotated tag. Publication and public-byte verification remain separate later states.
