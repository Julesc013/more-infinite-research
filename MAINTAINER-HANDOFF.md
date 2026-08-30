# Maintainer handoff

A handoff is complete only when the successor can reproduce current state without private chat history.

## Required package

- exact `dev`, `main`, tag, commit, and tree identities;
- current execution programme and first dependency-ready task;
- clean-worktree and remote-divergence readback;
- open PR, issue, branch, blocker, and revocation inventory;
- current target locks, package fingerprints, qualification receipts, and release ledger head;
- locations and recovery procedure for external state and archive custody;
- public verification keys and a private transfer ceremony for protected credentials;
- latest offline restore receipt and known unsupported environments.

## Acceptance

The successor independently verifies hashes and signatures, restores into a clean location, regenerates projections, runs the selected assurance profile, and signs a new custody receipt. The outgoing maintainer records discrepancies but cannot approve the successor's own proof.

Never paste production secrets into the handoff, commit them, or treat possession of a repository clone as signing authority. See [Security](SECURITY.md) and [Release runbook](RELEASE-RUNBOOK.md).
