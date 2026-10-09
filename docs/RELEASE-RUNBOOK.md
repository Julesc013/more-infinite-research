---
title: "MIR 4 Release Runbook"
status: current
applies_to: "MIR 4.0.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-09
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

## Release identity and mutable publication

Source `MAJOR.MINOR.PATCH` and registered target `CCC` produce a five-digit third component using `100 * integer(CCC) + PATCH`. Source 4.2.0 therefore uses `4.2.CCC00`; source 4.2.1 uses `4.2.CCC01`. A prerelease label, build retry or changed evidence never changes the numeric patch. Keep the ZIP root, `info.json`, packaged changelog, filename, manifest, distribution tags and download copy consistent; run the registered strict version regression before publication.

For the nine-target 4.2.1 maintenance cut, `Invoke-MIR42NineTargetReleaseAssets.ps1 -Mode Inventory` takes `-SourceVersion 4.2.1 -ReleaseTag v4.2.1 -PublishedMaintenancePredecessorManifestPath <published-420-manifest>`, alongside the accepted candidate, technical seal, campaign, independent verification, signing, review and restore inputs. It reconstructs the existing promotion plan before freezing the asset inventory. The support records use `mir-4.2.1.{qualification,provenance,components,release}.json` and maintenance record kinds. All four records, the seal, promotion plan and frozen inventory must carry the same published `v4.2.0-stable` predecessor custody. VerifyBytes and PublicReadback consume that inventory; copied local bytes alone do not establish public delivery.

The 4.2.1 conditional authorization contract is `spec/schemas/mir421-maintainer-written-release-authorization-v1.schema.json`. It records the maintainer's authorization to execute and publish after actual technical acceptance, with Portal uploads remaining maintainer-managed. It establishes no technical pass, signature, review or final-byte acceptance. The publication consumer binds it to the exact frozen inventory, protected-main readback and clean current main checkout, including predecessor custody. The separate 4.2.0 authorization and its emergency playtest waiver cannot authorize 4.2.1. Structural release-reader tests establish neither native qualification nor publication.

Keep GitHub release immutability disabled and do not restore removed rulesets. The existing `Test-MIRGitHubAdministration.ps1` separately probes `immutable-releases` and rejects enabled, owner-enforced or unrecognized state. Publication requires a final readback of that setting and of the release's `immutable=false` flag. Preserve recorded byte identities through repository governance and SHA-256 receipts. Never assume that deleting an immutable release frees its tag name: GitHub permanently reserves it.

[MIR 4.2.0](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.0-stable) uses the one-time authorized source tag `v4.2.0-stable`, frozen commit `6d19c874ea7d026d297865b96aa1b2b0916e9e61`, with nine CCC00 packages and three supporting assets. The manifest records this tag-name exception, with no numeric version exception. Future final tags return to canonical `vMAJOR.MINOR.PATCH`. This release is unsigned and mutable; its focused checks do not establish the disclosed NOT RUN native, save, client/multiplayer or performance qualification.

Stage every accepted asset before publication; verify exact tag/source, filenames, sizes and hashes in one draft. Reconcile interrupted operations by actual release ID and server state before retrying. Publish the existing draft as final, then stream anonymous downloads and check their SHA-256. Record the receipt and primary-checkout handoff before starting the maintainer-managed six-hour Portal rollout. Documentation maintenance never rebuilds the published packages.

## Published 4.2.1 acceptance boundary

On 9 October, after the remaining qualification/signing/recovery/review gaps were disclosed, the maintainer instructed immediate tagging and publication and confirmed the exact development tree to promote to main. [PR #599](https://github.com/Julesc013/more-infinite-research/pull/599) used the existing main-based exact-tree squash topology. [v4.2.1](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.1), published on 10 October 2026 AEDT, names main commit `27c4777c27b3287f18df02e200235a1870bac465`, after the package-excluded proof-lineage repair in PR #598; its nine player packages remain byte-identical to development commit `3f93d4f51db02b27d0800fa13ba9de694cab552e`. All nine H ZIP hashes and all sixteen public asset downloads were verified. The release is unsigned and mutable; its manifest and notes disclose the incomplete joined qualification, graphical/client/historical checks, signing, independent review and restore work.

This later maintainer acceptance superseded the earlier conditional publication timing only for those accepted bytes. The original conditional authorization, blocked readiness records and 4.2.0 receipts retain their original meaning. No missing result was converted to a pass, no signature was invented, and no external protection or immutability setting was changed. The [4.2.2 handoff](https://github.com/Julesc013/more-infinite-research/releases/download/v4.2.1/MIR-4.2.2-backlog.md) carries unfinished work forward. The normal readiness sequence below remains the default for subsequent releases; the 4.2.1 decision is not a reusable waiver.

## Readiness order

1. Reconcile exact repository, programme, queue, branch, and external-state identity.
2. Run the release doctor. Distinguish registered, fail-closed, executor-implemented, dry-run-passed, production-rehearsal-passed, and production-authorized. Until the first official 2.1 stable release, F210 selects the latest official Steam experimental 2.1.x at or above the current governed floor and records its exact version and executable hash in every proof. A Steam update selects a new execution identity, invalidates cross-patch evidence reuse, and materializes the API and opportunity review task set; it does not permanently pin the former patch. If newer APIs are adopted, raise the declared compatibility floor through an exact qualified change. When official 2.1 stable appears, stop and reopen the channel, floor, and release policy with the maintainer.
3. Close release-blocking defects under independent review, then freeze one exact source commit and allocate the candidate identity.
4. Build each target committed by the accepted candidate plan twice, serially, from the frozen source and retain the accepted archives plus compact construction receipts. Do not silently omit a committed target.
5. Qualify each committed target independently on its exact engine, including its required predecessor upgrade and reload evidence. F210 re-observes the current installed experimental engine immediately before its lane. A previous four-target result does not qualify a new candidate or replace its target commitments.
6. Independently recompute package, engine, runtime, transition, resource, and custody identities; create the technical seal and pass the offline restore drill.
7. Promote only the exact qualified candidate through the accepted protected procedure, with required checks and protections intact. Read back the resulting `main` commit and require the exact qualified tree and package bytes before recording its commit rebinding. Unresolved ancestry, rules, tree identity, or package identity is a preflight blocker, not permission to suspend protections.
8. Apply the candidate-bound acceptance decision to the sealed packages represented by read-back `main`. For 4.2.1, the maintainer's written conditional authorization supplies the publication decision only after actual required technical acceptance; a personal playthrough is not a prerequisite. It does not supply signatures, independent review, recovery evidence or a test waiver. Other release windows retain their governed human-playtest requirements. On `NO-GO`, publish nothing and correct forward through a new candidate. Until actual candidate-bound `GO`, do not create, push, or publish a tag.
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
