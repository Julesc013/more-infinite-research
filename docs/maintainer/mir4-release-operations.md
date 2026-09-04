---
title: "MIR 4 Release Operations"
status: current
applies_to: "MIR 4.0.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-release-operations-runbook
---

# MIR 4 release operations

## Preflight

Fetch and read back protected branches, require a clean worktree, reconcile the programme through its normative writer, materialize the exact verification plan, and run the release doctor. A registered fail-closed workflow is not the same as an implemented, rehearsed, or production-authorized executor.

## Human ceremonies

Protected signing/recovery acceptance records the approved signer identity, public-key fingerprint, custody and recovery test, ledger head, and separation of duties. F210/F200 playtest acceptance records the exact sealed candidate/environment and explicit `GO` or `NO-GO`. Automation prepares and validates the session but cannot fill the decision.

## Freeze through restore

1. For a minor or major release, freeze one exact `dev` commit/tree after explicit authorization. For a patch or hotfix, freeze one exact `main` commit/tree. Record the source lane and base explicitly.
2. Allocate the candidate only after freeze. Build A and B serially for every affected target, compare exact archive bytes and normalized content, retain the accepted archive, and release expanded success data.
3. Qualify every technical-required target independently: fresh exact-engine loads, predecessor upgrade, repeated reload, settings, research, migrations, canaries, target omissions, performance telemetry, package exclusion, and deterministic reconstruction.
4. Obtain independent aggregate verification, create a technical seal with human acceptance and publication still pending, and restore the complete release-window capsule offline.
5. Prepare a signed annotated tag object locally or in protected signing custody without pushing it.
6. For a minor or major release, fast-forward protected `main` to the exact sealed `dev` object ID. Temporarily remove only the pull-request rule that prevents an exact fast-forward, restore it in `finally`, and read back both remote refs. Do not insert a merge, squash, receipt, or documentation commit.
7. Run the maintainer playtest against the sealed F210/F200 packages already represented by `main`. A `NO-GO` appends rejection evidence and publishes nothing; it never force-resets `main`. A correction creates a new candidate.
8. On explicit `GO`, push the already verified signed tag, create the GitHub release with `--verify-tag`, attach only sealed assets, publish, and redownload every public byte. No build, test, qualification, or source rewrite occurs in this window.
9. Upload the identical target package and prepared target copy to the Mod Portal through the maintainer account, then record its public-byte identity.

An outage pauses at the current event. Resume with the same event identity and bytes. A defect after seal creates a new candidate; it never modifies the seal. The complete MIR 4.1 procedure and resource bounds are in [MIR 4.1 release readiness](mir4-4.1-release-readiness.md).

For branch and PR cleanup, every merged work package ends with the protected target branch read back exactly, all required forward-port or promotion dispositions recorded, and the active local branch clean and equal to its remote. `main` and `dev` are expected to diverge during next-release development.
