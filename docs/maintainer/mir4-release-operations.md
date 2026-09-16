---
title: "MIR 4 Release Operations"
status: current
applies_to: "MIR 4.0.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-16
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

1. For a minor or major release, freeze one exact `dev` commit/tree and the observed `main` base after explicit freeze authorization. For a patch or hotfix, freeze one exact `main` commit/tree. Record the source lane and base explicitly.
2. Allocate the candidate only after freeze. For a minor or major release, construct its create-only candidate ref through the accepted protected promotion procedure: one commit parented by the observed `main` base and carrying the exact frozen `dev` tree. Reject unintegrated stable changes, ref drift, or a conflicting pre-existing candidate ref.
3. Build A and B serially for every affected target from the exact candidate, compare exact archive bytes and normalized content, retain the accepted archive, and release expanded success data.
4. Qualify every technical-required target independently against that exact candidate commit/tree: fresh exact-engine loads, predecessor upgrade, repeated reload, settings, research, migrations, canaries, target omissions, performance telemetry, package exclusion, and deterministic reconstruction.
5. Obtain independent aggregate verification, create a technical seal with human acceptance and publication still pending, and restore the complete release-window capsule offline.
6. Promote only through the protected pull-request path with required checks and rules intact. The accepted squash boundary may change commit identity, so read back `main`, require ancestry from the observed base plus exact qualified tree and package-byte equality, and record the candidate-to-main commit rebinding. No routine operation suspends rules, force-pushes, deletes a protected ref, or treats a tree/package mismatch as success.
7. Present the maintainer playtest against the sealed F210/F200 packages already represented by read-back `main`. Until explicit `GO`, do not create, push, or publish a tag; a `NO-GO` appends rejection evidence and publishes nothing. It never force-resets `main`; a correction creates a new candidate.
8. On explicit `GO`, prepare and push the signed annotated tag against the verified `main` commit, create the GitHub release with `--verify-tag`, attach only sealed assets, publish, and redownload every public byte. No build, test, qualification, or source rewrite occurs in this window.
9. Upload the identical target package and prepared target copy to the Mod Portal through the maintainer account, then record its public-byte identity.

An outage pauses at the current event. Resume with the same event identity and bytes. A defect after seal creates a new candidate; it never modifies the seal. [MIR 4.1 release readiness](mir4-4.1-release-readiness.md) is a dated historical procedure, not a current operator contract.

For branch and PR cleanup, every merged work package ends with the protected target branch read back exactly, all required forward-port or promotion dispositions recorded, and the active local branch clean and equal to its remote. `main` and `dev` are expected to diverge during next-release development.
