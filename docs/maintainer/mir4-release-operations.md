---
title: "MIR 4 Release Operations"
status: current
applies_to: "MIR 4.0.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-release-operations-runbook
---

# MIR 4 release operations

## Preflight

Fetch and read back protected branches, require a clean worktree, reconcile the programme through its normative writer, materialize the exact verification plan, and run the release doctor. A registered fail-closed workflow is not the same as an implemented, rehearsed, or production-authorized executor.

## Human ceremonies

Protected signing/recovery acceptance records the approved signer identity, public-key fingerprint, custody and recovery test, ledger head, and separation of duties. F210/F200 playtest acceptance records the exact candidate/environment, required scenarios, observations, and explicit `ACCEPTED` or `REJECTED`. Automation prepares and validates blank forms but cannot fill either decision.

## Freeze through restore

1. Freeze one exact `dev` commit/tree after explicit authorization.
2. Allocate M4RC1 and build F210/F200 plus preview assets once.
3. Qualify exact packages: fresh load, predecessor upgrade, repeated reload, settings, research, migrations, canaries, performance, package exclusion, and deterministic reproduction.
4. Obtain independent aggregate verification.
5. Seal exact bytes with protected signing and append the release ledger.
6. Promote the sealed tree to `main`, create governed tags, and publish target-specific assets.
7. Redownload public bytes and compare hash, size, archive root, metadata, signature, and smoke result.
8. Restore offline from preserved source, tools, locks, and assets; compare to the public seal.

An outage pauses at the current event. Resume with the same event identity and bytes. A defect after seal creates a new candidate; it never modifies the seal.

For branch and PR cleanup, every merged work package ends with local `dev == origin/dev`, divergence `0/0`, and a clean worktree.
