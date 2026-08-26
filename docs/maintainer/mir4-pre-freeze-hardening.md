---
title: "MIR 4 Pre-Freeze Hardening"
status: current
applies_to: "MIR 4.0.0 pre-freeze development"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-pre-freeze-release-doctor
  - mir4-governed-release-workflow-inputs
  - mir4-manual-playtest-evidence-lifecycle
  - mir4-public-preview-asset-contract
  - mir4-publisher-confinement-and-restore-drill
---
# MIR 4 pre-freeze hardening

This control plane prepares dev for a future MIR 4.0.0 freeze without authorizing one. It is package-excluded and fail-closed. The tracked records, commands, and workflows do not allocate a candidate, accept a playtest, create or use production signing keys, seal or promote distributions, mutate main or a legacy line, create tags, upload artifacts to a public service, or make a public compatibility claim. Ordinary topic-branch pushes do not run a second copy of the pull-request verification matrix; push validation is scoped to governed integration, terminal, and release branch families.

## Immutable inputs

The post-readiness receipt binds PR 152, its merge commit and tree, the 30-of-30 evidence gate, F210 and F200 development packages, and the package-source fingerprint. Later changes may not silently reinterpret those bindings. Typed T02 through T04 authority-evolution receipts form an append-only chain: each records the exact previous and current hashes of evolved authorities, binds the current package-excluded implementation and schemas, and keeps every release-transition flag false. Any missing predecessor, duplicate evolution, or unrecorded live-authority mismatch fails closed. The development plan keeps the packages as rehearsal inputs only. A future release run must supply a clean frozen commit/tree and exact candidate identities; development package hashes never become release identities by implication.

Every production workflow accepts the same eight inputs: source release record, candidate ID, source commit, source tree, target distribution record set, release-plan digest, proof root, and seal root. The dispatcher validates the exact inputs and the checked-out repository identity. T03 adds executable non-production adapters for source freeze and target build. Source-freeze rehearsal records the exact clean commit and tree in an attempt-local manifest without creating a ref, allocating a candidate, or changing tracked content. Target-build rehearsal delegates package construction to the established F210 and F200 materializers, writes only below the attempt artifact root, and verifies the resulting bytes.

T04 adds exact target qualification, deterministic preview assets, and independent verification. Qualification materializes a two-target verification plan, imports self-hashed worker receipts only when source, target, distribution, package, engine, release-plan, and evidence identities agree, and retains an already accepted target receipt if a later target is interrupted. `Resume` adopts that immutable partial result and continues the missing work. Independent verification applies the same retention rule to receipts that explicitly assert an independent producer. Preview execution now owns generation and byte verification of exactly four V1 archives beneath its attempt root; the hosted workflow invokes that adapter directly. None of these records creates a release identity or grants publication authority.

The shared T02 kernel is implemented under `tools/lib/mir4/ReleasePhaseEngine.ps1`, with T03 and T04 adapters under `tools/lib/mir4/ReleaseAdapters.ps1` and the T05 lifecycle adapters under `tools/lib/mir4/ReleaseLifecycleAdapters.ps1`. It gives non-production attempts a deterministic fingerprint, an append-only hash-chained event log, operation-level idempotency keys, replay-based resume, verification and compensation transitions, and an immutable receipt. Its Git port is read-only, build and engine ports are attempt-root sandboxes, and signing and publication ports are denied. The kernel rejects production-capable adapters. Adapter maturity is recorded phase by phase and never inferred from kernel availability.

T05 completes the ten-phase executor surface in rehearsal mode. Release seal assembles an unsigned, self-hashed exact-target closure and rejects any later byte-identity mutation. Promotion emits and re-verifies a fast-forward-only plan without updating refs or tags. Target publication consumes only exact sealed-byte identities, exposes no builder, and reconciles uncertain transfers by the same domain-separated idempotency key. Public readback compares every mandatory target/channel byte hash and byte count. Restore drill reconstructs a clean attempt-local closure and rejects extra or changed files. None of these operations creates a production seal, mutates a protected ref, calls a public service, or grants publication authority.

T06 closes the ten-phase non-production rehearsal and fault-injection programme. The typed fault corpus binds each phase to its complete `Plan`, `DryRun`, `Execute`, `Verify`, and `Receipt` path plus one exact fail-closed injection. It covers unauthorized source freeze, incomplete target cardinality, wrong qualification package, changed preview bytes, wrong independent engine, post-assembly seal mutation, a stale promotion base, wrong publication bytes, wrong readback bytes, and an extra restored file. The aggregate verifier requires the T03, T04, T05, and T06 tests together; a metadata flag alone cannot satisfy rehearsal maturity.

The workflow contract and release doctor use six ordered maturity fields: `workflow_registered`, `workflow_fail_closed`, `workflow_executor_implemented`, `workflow_dry_run_passed`, `workflow_production_rehearsal_passed`, and `workflow_production_authorized`. Registration and fail-closed behavior are safety properties, not evidence that a named release operation can run. All ten phases now truthfully report implementation, dry-run, and non-production production-shaped rehearsal maturity. `workflow_production_authorized` remains false for every phase. Source freeze remains blocked by protected signing/recovery, explicit maintainer F210/F200 playtest acceptance, later dependency work, and the separately authorized freeze decision.

## Pre-freeze checks

Run:

    .\tools\mir.ps1 release doctor --json --explain

Run any of the ten phase dry runs against exact source identities with:

    .\tools\commands\mir4\Invoke-MIR4ReleaseWorkflow.ps1 -Phase source-freeze -Operation DryRun -SourceReleaseRecord <path> -CandidateId <development-id> -SourceCommit <commit> -SourceTree <tree> -TargetDistributionRecordSet <path> -ReleasePlanDigest <sha256> -ProofRoot <path> -SealRoot <path>
    .\tools\commands\mir4\Invoke-MIR4ReleaseWorkflow.ps1 -Phase target-build -Operation DryRun -SourceReleaseRecord <path> -CandidateId <development-id> -SourceCommit <commit> -SourceTree <tree> -TargetDistributionRecordSet <path> -ReleasePlanDigest <sha256> -ProofRoot <path> -SealRoot <path>
    .\tools\commands\mir4\Invoke-MIR4ReleaseWorkflow.ps1 -Phase target-qualification -Operation DryRun -SourceReleaseRecord <path> -CandidateId <development-id> -SourceCommit <commit> -SourceTree <tree> -TargetDistributionRecordSet <path> -ReleasePlanDigest <sha256> -ProofRoot <path> -SealRoot <path>
    .\tools\commands\mir4\Invoke-MIR4ReleaseWorkflow.ps1 -Phase preview-assets -Operation DryRun -SourceReleaseRecord <path> -CandidateId <development-id> -SourceCommit <commit> -SourceTree <tree> -TargetDistributionRecordSet <path> -ReleasePlanDigest <sha256> -ProofRoot <path> -SealRoot <path>
    .\tools\commands\mir4\Invoke-MIR4ReleaseWorkflow.ps1 -Phase independent-verification -Operation DryRun -SourceReleaseRecord <path> -CandidateId <development-id> -SourceCommit <commit> -SourceTree <tree> -TargetDistributionRecordSet <path> -ReleasePlanDigest <sha256> -ProofRoot <path> -SealRoot <path>

Use only repository-descendant package-excluded paths. Qualification execution reads `<proof-root>/qualification-workers/f200.json` and `f210.json`; independent verification reads the corresponding files under `<proof-root>/independent-receipts/`. Their schemas are the tracked worker and independent receipt V1 contracts. `M4RC1` is rejected while allocation is unauthorized. Execute, resume, verify, compensate, and receipt operations are available only inside the same non-production attempt boundary.

The doctor checks the authority schemas and bindings, remote-ruleset snapshot, immutable action pins, publisher confinement, V1 default extension path, package identity, preview contract, the non-production phase kernel, workflow registration, and the distinct executor-maturity fields. Until all phase adapters are implemented and rehearsed, `workflow-executor-maturity` is an automated blocker. Human signing input and explicit playtest acceptance remain separate blockers and are reported as such.

Audit the recorded branch and tag policy with:

    .\tools\mir.ps1 rulesets audit --json

The snapshot is evidence of the observed GitHub configuration, not permission to relax it. dev and main remain merge-only; release refs prohibit deletion and non-fast-forward changes; v4.* and dist/* updates or deletions remain blocked.

## Manual playtest evidence

Prepare isolated F210 or F200 sessions with release playtest-prepare. The command verifies the candidate, predecessor, and engine hashes before copying inputs into the session. Use release playtest-capture to retain only the named log, save, screenshot, and note files. Finish with release playtest-finalize --decision <ACCEPTED|CHANGES-REQUESTED|REJECTED> --reviewer <identity>.

Automation never invents a playtest result. Finalization requires an explicit human decision and records release_authority=false. Steam Factorio is used only for the current 2.1 engine; the preserved D:\Programs\Factorio\2.0 installation is used for 2.0.

## Public preview assets

The only release-facing preview assets are:

- mir4-api-sdk-v1-preview.zip
- mir4-mep-v1-preview.zip
- mir4-reference-extension-v1-preview.zip
- mir4-inspector-v1-preview.zip

Each archive contains source commit/tree/clean-state metadata, the exact contract set and digest, file hashes, MPL-2.0 inventory, generated-source map, conformance status, a preview notice, SPDX 2.3 SBOM, and public-safe provenance. V0 is migration input only and is not emitted as a release asset.

## Publisher and recovery boundaries

Build and qualification workflows cannot publish. The target-publication workflow has no repository checkout or build step, has read-only repository permissions, runs only on the confined mir4-publisher runner, and requires the external seal verifier under MIR_PUBLISHER_HOME to return a matching explicit publication admission before it can invoke the external client. Missing, false, or identity-mismatched admission fails closed. Tokens and signing material must stay outside the repository and all build worktrees.

The restore-drill workflow runs the offline W08 rehearsal only. It does not restore a production private key or publish. Production signing remains blocked until the maintainer provides an approved protected secret authority and completes the human recovery ceremony described in the release-governance runbook.
