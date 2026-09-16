---
title: "MIR 4 Release Runbook"
status: current
applies_to: "MIR 4.0.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-16
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-release-runbook
---

# MIR 4 release runbook

MIR 4 releases use one event-sourced engine with seven lifecycle operations:

```text
Plan -> DryRun -> Execute -> Resume -> Verify -> Compensate/Rollback -> Receipt
```

Its ten phase adapters are source freeze, target build, target qualification, preview assets, independent verification, release seal, promotion, target publication, public readback, and restore drill.

## Current workflow boundary

Use the [active operating programme](../spec/programmes/mir4-4x-operating-programme-v1.json), [branch authority](../.mir/branches.yml), and [current integration and delivery plan](releases/mir4-integration-and-delivery-plan.md#recoverable-release-and-local-delivery) for the candidate being prepared. Their accepted target commitments, qualification and human-acceptance requirements govern execution. This entry point does not allocate a release, select a new promotion topology, or authorize publication.

Resolve and rehearse promotion topology and effective rules before freeze. A routine release does not suspend or edit protections. A historical finalizer or past one-use exception is not a controller or authorization for a new candidate.

## Readiness order

1. Reconcile exact repository, programme, queue, branch, and external-state identity.
2. Run the release doctor. Distinguish registered, fail-closed, executor-implemented, dry-run-passed, production-rehearsal-passed, and production-authorized. Until the first official 2.1 stable release, F210 selects the latest official Steam experimental 2.1.x at or above the current governed floor and records its exact version and executable hash in every proof. A Steam update selects a new execution identity, invalidates cross-patch evidence reuse, and materializes the API and opportunity review task set; it does not permanently pin the former patch. If newer APIs are adopted, raise the declared compatibility floor through an exact qualified change. When official 2.1 stable appears, stop and reopen the channel, floor, and release policy with the maintainer.
3. Close release-blocking defects under independent review, then freeze one exact source commit and allocate the candidate identity.
4. Build each target committed by the accepted candidate plan twice, serially, from the frozen source and retain the accepted archives plus compact construction receipts. Do not silently omit a committed target.
5. Qualify each committed target independently on its exact engine, including its required predecessor upgrade and reload evidence. F210 re-observes the current installed experimental engine immediately before its lane. A previous four-target result does not qualify a new candidate or replace its target commitments.
6. Independently recompute package, engine, runtime, transition, resource, and custody identities; create the technical seal and pass the offline restore drill.
7. Promote only the exact qualified candidate through the accepted protected procedure, with required checks and protections intact. Read back the resulting `main` commit and require the exact qualified tree and package bytes before recording its commit rebinding. Unresolved ancestry, rules, tree identity, or package identity is a preflight blocker, not permission to suspend protections.
8. Present the candidate-bound human gameplay playtest against the sealed packages represented by read-back `main`. On `NO-GO`, publish nothing and correct forward through a new candidate. Until actual `GO`, do not create, push, or publish a tag.
9. Only with actual `GO` and publication authority, prepare and push the tag against verified `main` and publish the existing sealed assets without rebuilding or rewriting their source. Read back public bytes and close publication receipts. Mod Portal upload remains a separate maintainer action using the identical sealed target ZIPs and prepared copy.

## Historical MIR 4.1 closeout

Historical T17 sessions and the completed MIR 4.1 release retain their original command and evidence contracts. `Finalize-MIR410.ps1 -Decision <GO|NO-GO> -Reviewer <identity>` belongs to that already-qualified, source/tag/asset-bound release window. Do not execute it to prepare or publish MIR 4.2 or another candidate, and do not replay completed publication. Preserve historical receipts and published bytes unchanged.

## Non-negotiable behavior

- Never infer a human receipt or invent credentials.
- Never rebuild after seal.
- Never promote `main` before exact qualification.
- Never publish preview assets as Factorio player packages.
- Do not alter candidate bytes after their bound acceptance or seal; a required product change creates a new candidate and the affected qualification. Current repository-documentation maintenance does not rewrite an old release or confer new gameplay acceptance.
- On an external outage, preserve the sealed candidate and resume the publication event; do not create new bytes.
- Every retry uses the event identity and is idempotent. Partial work is verified, resumed, or compensated.

Detailed operator procedures live in [MIR 4 release operations](maintainer/mir4-release-operations.md), with freeze and promotion specifics in the existing MIR4 qualification documents.
