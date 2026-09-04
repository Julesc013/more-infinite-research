# MIR 4 release runbook

MIR 4 releases use one event-sourced engine with seven lifecycle operations:

```text
Plan -> DryRun -> Execute -> Resume -> Verify -> Compensate/Rollback -> Receipt
```

Its ten phase adapters are source freeze, target build, target qualification, preview assets, independent verification, release seal, promotion, target publication, public readback, and restore drill.

## Readiness order

1. Reconcile exact repository, programme, queue, branch, and external-state identity.
2. Run the release doctor. Distinguish registered, fail-closed, executor-implemented, dry-run-passed, production-rehearsal-passed, and production-authorized. Until the first official 2.1 stable release, F210 selects the latest official Steam experimental 2.1.x at or above the current governed floor and records its exact version and executable hash in every proof. A Steam update selects a new execution identity, invalidates cross-patch evidence reuse, and materializes the API and opportunity review task set; it does not permanently pin the former patch. If newer APIs are adopted, raise the declared compatibility floor through an exact qualified change. When official 2.1 stable appears, stop and reopen the channel, floor, and release policy with the maintainer.
3. Close release-blocking defects under independent review, then freeze one exact source commit and allocate the candidate identity.
4. Build the four target packages twice, serially, from the frozen source and retain only the accepted archives plus compact construction receipts.
5. Qualify F210, F200, F110, and F100 independently on their exact engines, including direct predecessor upgrade and two reloads. F210 re-observes the current installed experimental engine immediately before its lane.
6. Independently recompute package, engine, runtime, transition, resource, and custody identities; create the technical seal and pass the offline restore drill.
7. Prepare and verify the signed annotated tag locally without pushing it, then fast-forward protected `main` to the exact sealed `dev` commit and restore every temporarily suspended branch rule.
8. Run the final F210/F200 maintainer playtest against the already sealed bytes represented by `main`. On `NO-GO`, publish nothing and correct forward through a new candidate. On `GO`, push the existing tag and publish the existing assets without building, testing, or rewriting source.
9. Read back public bytes and close publication receipts. Mod Portal upload remains a separate maintainer action using the identical sealed target ZIPs and prepared copy.

Historical T17 sessions retain their original command and evidence contract. MIR 4.1 uses the sealed release-window launcher and `Finalize-MIR410.ps1 -Decision <GO|NO-GO> -Reviewer <identity>` because technical qualification, restore, tag preparation, and exact-main promotion have already completed. The finalizer verifies exact source, tag, and asset identities and contains no build or test operation.

## Non-negotiable behavior

- Never infer a human receipt or invent credentials.
- Never rebuild after seal.
- Never promote `main` before exact qualification.
- Never publish preview assets as Factorio player packages.
- Never run a build, test, qualification, or documentation rewrite after the MIR 4.1 playtest gate; a defect creates a new candidate.
- On an external outage, preserve the sealed candidate and resume the publication event; do not create new bytes.
- Every retry uses the event identity and is idempotent. Partial work is verified, resumed, or compensated.

Detailed operator procedures live in `docs/maintainer/mir4-release-operations.md`, with freeze and promotion specifics in the existing MIR4 qualification documents.
