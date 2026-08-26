# MIR 4 release runbook

MIR 4 releases use one event-sourced engine with seven lifecycle operations:

```text
Plan -> DryRun -> Execute -> Resume -> Verify -> Compensate/Rollback -> Receipt
```

Its ten phase adapters are source freeze, target build, target qualification, preview assets, independent verification, release seal, promotion, target publication, public readback, and restore drill.

## Readiness order

1. Reconcile exact repository, programme, queue, branch, and external-state identity.
2. Run the release doctor. Distinguish registered, fail-closed, executor-implemented, dry-run-passed, production-rehearsal-passed, and production-authorized.
3. Obtain protected signing/recovery acceptance and explicit F210/F200 maintainer playtest receipts.
4. Close defects under independent review.
5. Receive explicit source-freeze authorization and allocate the candidate identity.
6. Build once from the frozen source; qualify the exact bytes for both mandatory targets.
7. Independently verify, seal, promote, publish, and read back the public bytes.
8. Run the offline restore drill and close the release ledger.

## Non-negotiable behavior

- Never infer a human receipt or invent credentials.
- Never rebuild after seal.
- Never promote `main` before exact qualification.
- Never publish preview assets as Factorio player packages.
- On an external outage, preserve the sealed candidate and resume the publication event; do not create new bytes.
- Every retry uses the event identity and is idempotent. Partial work is verified, resumed, or compensated.

Detailed operator procedures live in `docs/maintainer/mir4-release-operations.md`, with freeze and promotion specifics in the existing MIR4 qualification documents.
