---
title: "MIR 4 Spark To Sol Handoff And Completion Plan"
status: current
applies_to: "MIR 4.0 M4C01"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-20
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-spark-sol-handoff
  - mir4-m4c01-next-work-plan
---

# MIR 4 Spark To Sol Handoff And Completion Plan

This page is the planning handoff from the completed Spark work to the next Sol planning and Codex execution cycle. It is an operational handoff, not a release seal. The accepted evidence is named explicitly; observations, scratch output, and incomplete audits are not promoted to proof.

## Executive status

Spark 5.3 work is complete for this cycle. The M4C01 work was advanced to a stable, identity-bound audit state, but M4C01 is not closed.

The accepted campaign state is:

| Task | Attempt | Result | Meaning |
| --- | --- | --- | --- |
| V00 | V00-A03 | PASS_WITH_OMISSIONS | Baseline and custody inventory completed; configured engine authorities were not found and the output root was a temporary path. |
| V01B | V01B-A01 | PASS_REUSED | The f210 retained performance result passed the pure independent verifier. |
| V02 | V02-A01 | PASS_REUSED | The f200 retained performance result passed the pure independent verifier. |
| V03 | V03-A01 | PASS_FRESH | Static-only validation exited 0 with 61 checks, 60 passed, 0 failed, and 1 expected runtime skip. |
| V04 | V04-A01 | INCOMPLETE | Package, target-disposition, maturity-firewall, and non-interference preparation exists, but the required V04 JSON packet and completion receipt do not. |

The next authoritative action is to reconcile the V03 audit packet and complete V04 in a new non-overwriting attempt. Do not rerun V03, f210 performance, or f200 performance unless an invalidating identity, source, generated-file, schema, validator, authority, or package-surface change occurs.

## Fixed M4C01 identity

The retained M4C01 checkout is:

```text
path:   C:\Projects\Factorio\more-infinite-research\tmp\mir4-full-platform-m4c01
branch: agent/mir4-full-platform-m4c01
HEAD:   e190836c8b8f781c4e41dafc08df367ca986b33a
tree:   49c08c58cd919c682db561dea2be528896a15eca
```

The package-source commit recorded by the f210 and f200 verifier receipts is `b460edd330dc19524bad97a2374c4c40c3b2ef36`. Preserve both identities. The checkout identity proves the audited source state; the package-source commit is part of the retained performance evidence binding.

The root checkout `info.json` remains the terminal package authority at version `3.2.11` for Factorio `2.1`. It is not the MIR 4 player-distribution metadata. MIR 4 distribution metadata lives inside the generated candidate ZIPs and uses versions such as `4.0.21000` and `4.0.20000`.

## What Spark accomplished

### Authority and boundary work

The M4C01 source authorities and canonical tests were located and bound to the fixed checkout. The relevant authority families include the target registry, package-presentation overlay, maturity and publication contract, bootstrap candidate plan, historical private-candidate authorization, target profiles, platform preview contract, package-surface locks, and release validation commands.

The resulting boundary is explicit:

| Surface | Current disposition |
| --- | --- |
| f210 and f200 | Candidate-mandatory stable player targets. |
| f110 and f100 | Candidate-conditional reduced targets. |
| f018 through f013 | Private experimental historical candidates. |
| f012 through f006 | Deferred museum targets, not part of the M4C01 player candidate set. |
| SDK, MEP/API, reference extension, query profile, target provider, and Inspector preview surfaces | Preview, Shadow, or Experimental and non-authoritative as declared. |
| Public Mod Portal publication | Not authorized by the M4C01 authorities. |

The stable package boundary forbids development material, raw authority/evidence trees, SDK and developer packages, validation and test harnesses, build and audit roots, machine-specific paths, credentials, private URLs, debug material outside the package contract, nested unrelated ZIPs, and superseded candidates.

### Candidate distributions

Ten M4C01 player-candidate ZIPs exist in the retained checkout. Their inventory record calls them `built-unqualified-m4c01-candidate`; this is a build state, not a release qualification claim.

| Target | Factorio line | Role | Distribution version | Archive SHA-256 | Bytes | Entries |
| --- | --- | --- | --- | --- | ---: | ---: |
| f210 | 2.1 | mandatory | 4.0.21000 | FA32F0C9A3FF7CBF9D95AA45F6164CF893C0CBBB4BFFE7AEED9FAC524B5C0117 | 1048215 | 305 |
| f200 | 2.0 | mandatory | 4.0.20000 | 886E92D34D04A3D9FBC3193B35658E4C0A2DB2F0582F531AAFA5AF53CBE30B3E | 1045468 | 303 |
| f110 | 1.1 | conditional | 4.0.11000 | DC6B8C9ED3E96DBE2C4EE7D472CBA21B9B3F68839ADA983513F6712A1099EE36 | 398294 | 174 |
| f100 | 1.0 | conditional | 4.0.10000 | 0ED165168251D919919E8872CE38374F68CB51BAB31027E2B9F0269400D745EC | 398297 | 174 |
| f018 | 0.18 | private-experimental | 4.0.01800 | 300E4D0A5FD46F5AADEB7D338225674B41B0548FAEE9E05C31617759AA16D7A5 | 366413 | 177 |
| f017 | 0.17 | private-experimental | 4.0.01700 | 12EEC0FEE2133CDD08FA1BEDB62FBFCCB70DCA8D6288B96653F37573FB848C78 | 366367 | 177 |
| f016 | 0.16 | private-experimental | 4.0.01600 | 72551DE9879F22EC085D9B5509CBE0CDEBABF3C33FA2A50355C6CEFE982A2BC3 | 366366 | 177 |
| f015 | 0.15 | private-experimental | 4.0.01500 | 4C058908AEF6B2AC555D3D377F32C99C0C5ABFFC801E941E95399F5F61011AA8 | 366682 | 177 |
| f014 | 0.14 | private-experimental | 4.0.01400 | D840549340820F07841E420D5952601E707D81D51A52ED1BF0E00FD9692B5A0B | 367120 | 177 |
| f013 | 0.13 | private-experimental | 4.0.01300 | CDDED672AB0E1CC8EAF91585D149F5372D093A94FC3CC9A5B9348DAF3FDFAD0C | 367210 | 177 |

The ZIP paths are under `build\mir4\m4c01-player-candidates\distributions\more-infinite-research_<version>.zip`. The candidate-set record has `public_output_authorized: false`.

### Accepted performance evidence

V01B bound f210 to Steam Factorio `2.1.14` and V02 bound f200 to `2.0.77`. Both retained results returned `passed` from `Test-MIRRuntimePerformanceEvidence`. Both receipts record zero Factorio processes started and zero repository files modified. Both explicitly defer complete release-level revocation and protected release qualification to later negative-assurance and release gates.

The accepted retained-result hashes are:

| Target | Retained result | SHA-256 |
| --- | --- | --- |
| f210 | `build\results\mir4-m4c01\runtime\f210\performance-regression.json` | 2BEE85B206623AB5A1203C1C8EA862A3E121EF2BFEE9859CFF5AAB968D8365BB |
| f200 | `build\results\mir4-m4c01\runtime\f200\performance-regression.json` | 6F8EBE1C17A4F78FFB0B8A93C1CD4C6AB93CB5942217320A14610ED357F7A8F5 |

The old f210 and f200 evidence digests are recorded as superseded and must not be promoted. Do not spend another performance campaign on these targets unless the invalidation conditions change.

### Fresh static evidence

V03 ran:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

The exit code was 0. The receipt reports 61 total checks, 60 passed, 0 failed, 1 expected runtime skip, and no B0/B1/B2/B3/I/N findings. Factorio was not launched. The static result explicitly does not establish runtime or historical-engine qualification.

The V03 preflight exists and binds the exact branch, HEAD, tree, zero tracked diff, zero staged diff, and zero untracked files. The V03 completion artifact list omitted that preflight even though it exists. This is an audit-packet packaging discrepancy, not a reason to rerun the 61 checks. The V03 coverage record also reports `checks_skipped: 2` while the results record reports one skipped check and one runtime skip; reconcile this count in the closeout packet instead of silently changing either historical artifact.

## V04 preparation that is not yet completion

The existing `V04-A01` directory contains seven command logs and one preview-package descriptor. The following canonical commands completed with exit code 0 during preparation:

```powershell
.\validation\tests\release\Test-MIR4BootstrapMaterialization.ps1
.\validation\tests\release\Test-MIR4LocalPlaytestShadow.ps1
.\validation\tests\release\Test-MIR4OfflineCandidateCustody.ps1
.\validation\tests\release\Test-MIR4HybridPlatformAuthority.ps1
.\validation\tests\package\Test-MIRPackageIdentity.ps1
.\validation\tests\package\Test-MIRDeterministicPackage.ps1
.\validation\tests\mir4\Test-MIR4PlatformPreview.ps1
.\validation\tests\mir4\Test-MIR4ExperimentalApiSdk.ps1
```

The logs show bootstrap materialization, local-playtest shadow, offline custody, hybrid authority, package identity, deterministic packaging, platform preview, and experimental API/SDK checks passing. These are useful V04 inputs and command receipts, but they are not a substitute for the required V04 package inventory, surface, target disposition, maturity firewall, non-interference, findings, coverage, completion, and SHA256 manifest outputs.

The preview descriptor records four preview-only ZIPs: the SDK, platform preview, reference extension, and Inspector preview. It records publication as preview-only and not Mod Portal. These preview ZIPs are not player-package contents.

Manual ZIP inspection also observed one root, `info.json`, locale, migrations, changelog, assets, and target-specific runtime/settings counts in every available candidate. It did not find the broad forbidden path classes checked manually. Treat those observations as provisional until V04 emits canonical JSON evidence.

## Evidence locations and retention rules

Keep the following material. Do not delete or move it as part of the next sprint.

| Location | Classification | Action |
| --- | --- | --- |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V00-A03` | Accepted baseline with omissions | Preserve immutably; use the actual repository path in new records, not stale `C:\tmp` path strings inside older receipts. |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V01B-A01` | Accepted reused f210 verifier packet | Preserve; do not rerun without an invalidating change. |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V02-A01` | Accepted reused f200 verifier packet | Preserve; do not rerun without an invalidating change. |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V03-A01` | Accepted fresh static packet | Preserve; reconcile manifest/coverage metadata without rerunning static checks. |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V04-A01` | Partial V04 preparation | Preserve as input; never overwrite. Use `V04-A02` or a later attempt for completion. |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V01-A02` | Blocked original f210 attempt | Preserve as historical missing-input evidence; do not promote. |
| `tmp\MIR4-audit\20260819-spark-48h\attempts\V01R1-A01`, `V01R2A-A01`, `V01R2B-A01` | Investigation and recovery attempts | Preserve for provenance; use only the canonical V01B receipt for accepted performance status. |
| `tmp\MIR4-audit\20260819-spark-48h\v00` and `SHA256-TREE.json` | Campaign-level inventory material | Preserve until V05 corpus census binds or supersedes it. |
| `tmp\mir4-full-platform-m4c01` | Retained M4C01 checkout and generated candidates | Preserve exactly; no rebuild or source edit during read-only V04. |
| `tmp\run_v01b_v02.ps1` | Reproducibility helper for the pure f210/f200 verifier receipts | Preserve as historical tooling; do not treat it as the canonical validator. |
| `tmp\cleanup-receipts` | Cleanup decision and dry-run receipt | Preserve; it says `PASS_WITH_RETENTION`, `target_lines_deleted: false`, and `UNIQUE_EVIDENCE_PRESENT`. |
| `tmp\target-lines` | Historical source/evidence corpus | Preserve. It is not the active M4C01 checkout and must not be packaged or deleted without a separate custody decision. |
| `tmp\MIR4-rescue` | Rescue and recovery material | Preserve until release closeout confirms the external rescue bundle and custody chain. |
| `tmp\t` | Unclassified scratch | Inventory before any cleanup; do not infer that it is disposable. |

The V00 rescue bundle is recorded as `D:\MIR4-rescue\20260818-213140\mir4-m4c01-e190836c8b8f.bundle` with SHA-256 `753E46A13C651148CE1DF449898F71516CF1460FF52D7F0B4ECFA6E6D5835DE8`; its recorded bundle verification exited 0.

The cleanup receipt belongs to a different earlier main-repository identity than the M4C01 checkout. Do not use its `HEAD` or tree as the M4C01 identity. Use it only for the retention decision about `tmp\target-lines`.

## What remains unverified

The following statements are not currently release claims:

- The ten ZIPs are built candidates, not qualified player releases.
- The manual ZIP surface review has no canonical V04 JSON receipt yet.
- f110, f100, and historical f018 through f013 have no accepted runtime qualification in this campaign.
- f018 remains runtime-unqualified when the exact engine is unavailable.
- Preview, Shadow, and Experimental systems have passing conformance checks, but their non-interference against every stable package and runtime output still needs the V04 canonical packet.
- V03 static validation does not prove runtime, migration, playtest, or historical-engine behavior.
- V01B and V02 pure verifier passes do not close complete negative assurance or protected release qualification.
- No M4C01 public publication or Mod Portal admission is authorized.

## Sol mega-sprint plan

This sequence is the planning baseline. Sol must bind each execution task to the repository's current canonical verification plan before generating Codex prompts.

### Phase 0: Adopt the state without invalidating it

1. Read this handoff and the project `AGENTS.md`.
2. Confirm the M4C01 path, branch, HEAD, and tree shown above.
3. Confirm no Factorio, MIR package, performance, or qualification process is active.
4. Treat V00-A03, V01B-A01, V02-A01, and V03-A01 as immutable evidence.
5. Do not rebuild candidate ZIPs, modify the M4C01 checkout, rerun V03, or rerun f210/f200 performance.

### Phase 1: Repair the audit packet, not the source

1. Bind the existing V03 preflight SHA-256 into the V03 manifest/readout if the governing packet format permits it.
2. If the existing manifest cannot be edited safely, create an external reconciliation record that names the preflight path, SHA-256, HEAD, tree, and the omission.
3. Reconcile the `checks_skipped` versus runtime-skip count in a new closeout note; do not rewrite the historical V03 result.
4. Record that the root package version `3.2.11` is expected and that MIR 4 versions are ZIP-local metadata.

### Phase 2: Complete V04 package and boundary assurance

1. Use a fresh Spark-free attempt such as `V04-A02`; never overwrite `V04-A01`.
2. Run the exact V04 read-only prompt from the prior campaign message.
3. Audit all ten available candidate ZIPs and report missing packages rather than regenerating them.
4. Use the canonical package, target-disposition, maturity, package-lock, and non-interference authorities and tests.
5. Emit all required V04 JSON outputs plus `SHA256SUMS.json`.
6. Classify only deterministic unsafe/private/authoritative defects as B0/B1; classify expected lower-target omissions as N; do not repair findings in the audit attempt.
7. If V04 is clean, record `PASS_FRESH`. If it is complete with only bounded B2/B3 findings, record `PASS_WITH_FINDINGS`. Do not call a partial packet a pass.

### Phase 3: V05 corpus census

1. Inventory the active checkout, M4C01 generated files, all audit attempts, rescue material, target-lines historical corpus, engines, package authorities, tests, schemas, and evidence roots.
2. Build a custody map separating current authoritative evidence, reused evidence, superseded evidence, blocked evidence, manual observations, and scratch output.
3. Find stale path strings, stale predecessor identities, stale package hashes, duplicate receipts, missing manifests, and unqualified target claims.
4. Do not delete historical corpus material during the census.
5. Emit a bounded repair packet only after the census identifies a deterministic owner and invalidation impact for each issue.

### Phase 4: Runtime, migration, and negative assurance

1. Use the local engine authorities from `AGENTS.md`: Steam for Factorio 2.1 and preserved `D:\Programs\Factorio\<version>` installations for 2.0 and older engines.
2. Qualify f210 and f200 only when the canonical plan requires fresh runtime evidence or an invalidating change has occurred.
3. Treat f110/f100 and historical packages as unavailable for runtime claims unless their exact engines are present and authorized.
4. Exercise target omissions, unsupported API surfaces, migration behavior, state ownership, and package metadata under the canonical negative-assurance plan.
5. Recheck supersession and revocation paths, including old f210/f200 evidence digests and stale candidate identities.
6. Separate runtime observations from player-package authority and from preview/shadow output.

### Phase 5: Manual playtest and package acceptance

1. Define the smallest authoritative manual playtest matrix for each target that has an available engine.
2. Record engine binary identity, package hash, source/tree identity, save lifecycle, migration path, expected omission behavior, and observed result.
3. Keep manual evidence outside the player ZIP and bind it through a receipt.
4. Re-run package-surface locks after any source or generated-package change.
5. Do not publish or sign a candidate merely because its ZIP opens or its static validators pass.

### Phase 6: M4C01 closeout

1. Produce matrices for target disposition, feature coverage, package contents, engine/runtime coverage, migration coverage, maturity firewall, non-interference, findings, and evidence custody.
2. Confirm all required outputs parse, have unique hashes, and point to the final identity.
3. Confirm B0/B1 are zero or explicitly repaired and requalified.
4. Confirm all remaining I/N limitations are explicit and do not masquerade as support.
5. Decide whether M4C01 is `PASS_FRESH`, `PASS_WITH_FINDINGS`, `FAIL_REPRODUCIBLE`, `BLOCKED_MISSING_INPUT`, or `TOOLING_DEFECT` using the canonical result classes.
6. Only after that decision, prepare the next release or publication plan.

## Sol and Codex todo list

### Immediate todo

- [ ] Adopt this handoff as the planning baseline.
- [ ] Preserve all accepted and partial audit attempts.
- [ ] Reconcile the V03 preflight omission without rerunning V03.
- [ ] Create a fresh V04 attempt and complete the package-surface audit.
- [ ] Bind all ten candidate ZIP hashes and metadata to the V04 inventory.
- [ ] Report missing historical engines as input limitations, not as successful qualification.

### Assurance todo

- [ ] Complete V05 corpus and custody census.
- [ ] Reconcile stale `C:\tmp` and temporary-output path references.
- [ ] Audit package allowlists and target-specific dead surfaces.
- [ ] Audit preview, shadow, and experimental non-interference.
- [ ] Run only the runtime and migration campaigns authorized by the canonical plan.
- [ ] Run negative assurance for stale evidence, supersession, revocation, omissions, and unsupported target APIs.
- [ ] Capture bounded manual playtest evidence for engines that actually exist locally.

### Repair and closeout todo

- [ ] Do not repair inside read-only audit attempts.
- [ ] If a B0/B1 finding is deterministic, produce a bounded repair packet naming files, owner, invalidated evidence, and required reruns.
- [ ] Keep preview and shadow surfaces non-authoritative after any repair.
- [ ] Rebuild only after an explicit repair decision and record new package hashes.
- [ ] Re-run only invalidated evidence; reuse exact trusted evidence otherwise.
- [ ] Generate final M4C01 closeout matrices and completion receipt.
- [ ] Update current documentation and `.mir` authorities only when the closeout decision changes a documented source of truth.

## Prompt-generation rules for the next planning chat

The next planning chat should generate small, bounded Codex prompts from the phases above. Every prompt should state the exact worktree, expected identity, read-only or write mode, output root, attempt ID, canonical commands, forbidden actions, reuse conditions, and result-class rules.

The first Codex prompt should be V04 completion, not a rebuild and not another V03 run. The second should be V05 corpus census. Repair prompts should be generated only from a recorded B0/B1 finding or from an explicit documentation/packet discrepancy with no source behavior impact.

## Definition of done

The work is complete only when the M4C01 candidate set has a canonical package-surface receipt, explicit target dispositions, a closed maturity firewall, non-interference evidence, runtime and migration coverage appropriate to available engines, negative assurance, manual evidence where applicable, complete custody and supersession records, and a final closeout result class. Until then, preserve the artifacts and describe the candidate ZIPs as private, built, and unqualified.
