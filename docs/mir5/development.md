---
title: "Development guide"
status: draft
applies_to: "MIR replacement development"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-24
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-development-guide
---

# Development guide

## Start with a bounded task

Read root agent instructions, the [specification index](../../spec/mir5/README.md), and the one or two relevant contracts. Inspect current `git status`, exact source and active jobs once. Preserve dirty/untracked work and unique receipts. Do not reset to a historical planning commit.

A useful task packet is short:

```text
Outcome:
Existing requirement/incident IDs:
Input source/package/engine refs:
Permitted files:
Independent expected behavior:
Simplest implementation and work bound:
Tests and actual existing commands:
Stop condition:
```

For the first port, recover actual identity/tuning/settings from the pinned baseline. Do not invent a cleaner-looking replacement ID. Host expected output must not be generated from the candidate and then declared independent.

## Community bugs and request continuity

Maintain the [existing community request ledger](../../spec/programmes/community-requests.json) through `CONT-15`; preserve original IDs, MIR 4 crash/failure evidence, unresolved bugs and technology-tuning requests. Carry them into affected MIR 5 work and regression selection rather than closing them because the architecture changes. `SCI-UNLOCK-01` records the recurring approved science binding startup failures, the reported unsuccessful mod-removal attempts and missing reproduction evidence. It remains open until exact affected-package qualification supports closure. This intake does not claim a fix.

## Work in small vertical slices

Make a native family work end to end, then exercise a different native effect, a staged/native-owner integration and stateful caps/runtime. Keep partial packages off production saves. A successful tiny package is not a full-product migration or performance claim.

Use one implementer, one independent review responsibility and one test worker within the existing three-slot capacity. Workers must have nonoverlapping edits. Reuse running native campaigns; at most one heavy scenario per admitted machine. Exact archive libraries/settings are preserved and restored by existing qualified tools.

## Before creating an abstraction

Show the real repeated code or concrete safety boundary, why native Factorio behavior is insufficient, what new state it retains, and which tests protect its removal/replacement. Do not create an adapter for an imagined future engine or an API function without a consumer.

Code should be concise enough to follow, not minified. Prefer ordinary arrays/maps and direct field changes. Do not hide complexity in generated data. Explain any shared Generator growth together with the total declarations/adapters/UI/tooling footprint.

## Test selection

Follow [verification](../../spec/mir5/verification.md). Run cheap affected checks first, native slices for changed gameplay, migrations/clients when state is affected, and the full relevant frozen-candidate campaign before release. A documentation typo is not a new native campaign. A new engine is not covered by an old native receipt.

A test correction needs independent evidence. A resource refusal is not a pass, fail or timing sample. A path-only rename still needs package member equality and final-layout smoke, because import and package mistakes are real defects.

## Contribution completion

Return exact changed files/responsibilities, real commands/results, active regressions covered, any measured seconds/uncertainty, unresolved gaps and next action. No generic 'all tests passed' when native tests were unavailable. Stop after the assigned batch; new work gets a new bounded assignment.

Release and branch/control permissions remain explicit. Documentation adoption is not permission to publish or change repository security controls.

## Offline player asset freeze

The [release adapter](../../tools/mir5/release.py) builds the nine editions from one committed player tree and its tracked edition record. Select a full commit and a new output directory outside the checkout:

```powershell
python tools/mir5/release.py --source source/mir5 --revision <full-commit> --output ../mir5-freeze/<new-directory>
python tools/mir5/release.py --source source/mir5 --output ../mir5-freeze/<new-directory> --verify
```

The output contains nine canonical player ZIPs, `SHA256SUMS.txt` and `MIR5ReleaseAssetInventoryV1.json`. The inventory binds the source commit/trees, edition blob, complete package members, archive bytes and separate local controller identity: both Python tools, Python/zlib versions and compression policy. Verification requires that same controller and rebuilds packages in temporary custody to compare exact bytes. It rejects existing freeze destinations and changed, absent, extra or misidentified assets. Preserve failed output for inspection.

This command performs no signing, tagging or publication and grants no native-test acceptance. The final release still needs every applicable verdict in [verification](../../spec/mir5/verification.md), administration and separate release-immutability checks, exact main/tag reconciliation and public download readback. The maintainer authorizes unsigned GitHub-only MIR5 publication when the enrolled signing key is unavailable; retain accurate checksums and do not describe them as signatures. Mod Portal publication is outside this goal. Accepted packages must also reach the primary checkout's `dist` with verified hashes. The inventory is developer custody; public assets remain individual player ZIPs and useful integrity files.

## Determinism and visual context

Read [the architecture explainer](architecture.md) once, then only the relevant spec/diagram. For ordering, runtime, migration or package work, include [determinism](../../spec/mir5/determinism.md) in the task packet. Do not supply all diagrams or old transcripts to every task.

Tests of this pack are tool/document tests. The product case catalogue stays `not_run` until actual implementation commands and native evidence exist. Do not modify its expected assertion to copy a candidate's unexpected output.
