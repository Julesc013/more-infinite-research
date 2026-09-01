# MIR 4 release runbook

MIR 4 releases use one event-sourced engine with seven lifecycle operations:

```text
Plan -> DryRun -> Execute -> Resume -> Verify -> Compensate/Rollback -> Receipt
```

Its ten phase adapters are source freeze, target build, target qualification, preview assets, independent verification, release seal, promotion, target publication, public readback, and restore drill.

## Readiness order

1. Reconcile exact repository, programme, queue, branch, and external-state identity.
2. Run the release doctor. Distinguish registered, fail-closed, executor-implemented, dry-run-passed, production-rehearsal-passed, and production-authorized. Until the first official 2.1 stable release, F210 selects the latest official Steam experimental 2.1.x at or above the current governed floor and records its exact version and executable hash in every proof. A Steam update selects a new execution identity, invalidates cross-patch evidence reuse, and materializes the API and opportunity review task set; it does not permanently pin the former patch. If newer APIs are adopted, raise the declared compatibility floor through an exact qualified change. When official 2.1 stable appears, stop and reopen the channel, floor, and release policy with the maintainer.
3. Obtain protected signing/recovery acceptance and explicit F210/F200 maintainer playtest receipts.
4. Close defects under independent review.
5. Receive explicit source-freeze authorization and allocate the candidate identity.
6. Build once from the frozen source; qualify the exact bytes for both mandatory targets.
7. Independently verify, seal, promote, publish, and read back the public bytes.
8. Run the offline restore drill and close the release ledger.

For T17, prepare each exact session with `tools/mir.ps1 playtest prepare --target <F210|F200> ... --json`, run the generated isolated launcher, retain logs/saves/screenshots/notes in its capture queue, and record the exact scenario outcomes in `observations.json`. Then run `tools/mir.ps1 playtest capture --session <path> --json`. Only the maintainer may run `tools/mir.ps1 playtest finalize --session <path> --decision <ACCEPTED|CHANGES-REQUESTED|REJECTED> --reviewer <identity> --json`; the non-evidence template cannot satisfy the gate, and even an explicit `ACCEPTED` is rejected unless all expected scenarios and capture requirements match.

## Non-negotiable behavior

- Never infer a human receipt or invent credentials.
- Never rebuild after seal.
- Never promote `main` before exact qualification.
- Never publish preview assets as Factorio player packages.
- On an external outage, preserve the sealed candidate and resume the publication event; do not create new bytes.
- Every retry uses the event identity and is idempotent. Partial work is verified, resumed, or compensated.

Detailed operator procedures live in `docs/maintainer/mir4-release-operations.md`, with freeze and promotion specifics in the existing MIR4 qualification documents.
