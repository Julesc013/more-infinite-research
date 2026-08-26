---
title: "Target-Line Versioning And Backports"
status: current
applies_to: "MIR 3.2.5 through the authorized 3.2.11/2.5.11 emergency hotfixes and successor terminal aliases"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
source_of_truth_for:
  - backporting-policy
  - backport-target-profile-projection
---

# Target-Line Versioning And Backports

The MIR 3 `.5` wave established one immutable published package for every supported target from Factorio 2.1 through 0.13. All later MIR 3 corrections converge in the matching `.9` release under the [terminal `.9` programme](../releases/mir-3-terminal-dot-9-programme.md).

## Live branch roles

The permanent remote topology contains `main`, `dev`, and `legacy`.

| Branch | Role |
| --- | --- |
| `main` | Published Factorio 2.1 line at immutable `3.2.10`; authorized to advance only through the qualified `3.2.11` emergency hotfix. |
| `dev` | Canonical integration line for the corrected terminal authority and MIR 4 handoff. |
| `legacy` | Movable previous-major terminal alias. It currently points at MIR 3.2.10 through a two-parent exact-tree commit; when MIR 5 opens, it may advance once to the sealed MIR 4 terminal authority and remain pinned there for the MIR 5 lifecycle. |

Temporary target worktrees or candidate branches are disposable qualification surfaces. Delete their remote branches after publication while retaining immutable tags and evidence. Never use `legacy` or a historical target branch as scratch space.

The `legacy` role changed under `MIR3PostTerminalEmergencyHotfixMaintainerReleaseOverrideV1`. Factorio 2.0 releases `2.5.9` and `2.5.10` remain immutable and downloadable through their annotated tags and releases; moving the branch does not replace that history. The authorized `2.5.11` source is rooted at the immutable `2.5.10` release commit, not at `legacy`. This exception supersedes the branch-routing text below only where it describes `legacy` as the active 2.0 lane; the historical materialization records remain authoritative.

Advance `legacy` only at a major-generation handoff after the outgoing major's terminal release is sealed. Preserve the old `legacy` head as the first parent, use the new terminal authority as the second semantic parent, require the alias tree to equal that terminal authority exactly, and never force-push. This makes `legacy` usable as the MIR 4 terminal pin throughout MIR 5 without sacrificing the MIR 3 or Factorio 2.0 tags.

## Target-line map

| MIR line | Exact Factorio target for the `.5` / `.9` wave | Frozen predecessor | Terminal release |
| --- | --- | --- | --- |
| `3.2.x` | `2.1` | `3.2.10` | `3.2.11` authorized emergency continuation |
| `2.5.x` | `2.0` | `2.5.10` | `2.5.11` authorized emergency continuation |
| `1.9.x` | `1.1.110` | `1.9.5` | `1.9.9` |
| `1.8.x` | `1.0.0` only | `1.8.5` | `1.8.9` |
| `1.7.x` | `0.17.79` | `1.7.5` | `1.7.9` |
| `1.6.x` | `0.16.51` | `1.6.5` | `1.6.9` |
| `1.5.x` | `0.15.40` | `1.5.5` | `1.5.9` |
| `1.4.x` | `0.14.23` | `1.4.5` | `1.4.9` |
| `1.3.x` | `0.13.20` | `1.3.5` | `1.3.9` |

Historical transition exceptions remain historical: MIR `1.9.0` through `1.9.2` targeted Factorio 2.0, and MIR `1.8.0` was a one-time Factorio 0.18 bridge. Neither exception expands the current target claim. `1.8.5` and `1.8.9` support Factorio 1.0 only.

## Terminal version rule

The post-terminal `.10` and `.11` maximum-level exceptions and the `legacy` alias are governed by their append-only emergency authorities. The rules in this section remain the historical policy for the completed `.5`/`.9` wave.

- Published `.5` packages and tags never change.
- Do not create `.6`, `.7`, or `.8` releases.
- Route every MIR 3 product, package, migration, compatibility, locale, documentation, performance, and assurance correction to the matching `.9` release or explicitly defer it to MIR 4.
- A documentation change to the packaged root `README.md` is package-visible and therefore belongs to `.9`, even when the runtime is unchanged.
- Release tooling, evidence, and repository-only documentation may be corrected package-excluded when the exact `.5` package identity remains unchanged.

## One finding, one disposition

Before implementation, add each finding to the unified terminal change set and assign exactly one disposition:

- `portable`: one canonical correction on `dev`, projected without semantic change;
- `portable-with-adapter`: one canonical intent plus a bounded target adapter;
- `target-local`: a correction proven to affect only one historical target;
- `package-excluded-assurance`: repository, evidence, CI, or publication correction that cannot alter package bytes;
- `mir4-deferred`: platform or feature work held for MIR 4;
- `rejected`: recorded with the reason it will not ship.

Do not cascade lower releases from the previously processed lower release. Materialize each from its own immutable `.5` predecessor plus the exact portable `.9` source and only its named adapters.

## Materialization sequence

1. Reconcile retained `.5` assurance debt without rebuilding a published archive.
2. Freeze the terminal finding inventory and target dispositions.
3. Implement admitted portable work on `dev`.
4. Materialize all nine target shadows before source freeze and repeat the fixed-point sweep until its convergence checks pass.
5. Freeze the common source only after the accepted fixed-point receipt; then assign the next candidate in each governed namespace.
6. Qualify and seal `3.2.9` and every lower target independently before creating any public tag.
7. Build each lower final integration from its `.5` predecessor plus the exact frozen `3.2.9` release commit. The second parent need not be publicly tagged during qualification.
8. Create the family-readiness seal, create local signed annotated tags, then push/publish the already sealed family under the controlled same-byte policy.
9. Download, rehash, and exact-engine smoke every public asset before archiving MIR 3 and creating the MIR 4 handoff packet.

For a lower release integration, require:

```text
first parent  = exact target-line .5 predecessor
second parent = exact frozen 3.2.9 release commit (public tag not required during qualification)
tree          = exact admitted target candidate tree
```

Reconstruct the integration and package before tagging. The tree, archive SHA-256, normalized content SHA-256, byte count, entry count, settings, features, omissions, migrations, and package composition must equal the admitted candidate.

## Qualification boundaries

- Factorio 2.1 evidence never substitutes for Factorio 2.0 or historical-engine evidence.
- Each target needs its own metadata, binary identity, load proof, compatibility scope, package record, and public verification.
- Bind existing evidence only through exact source-tree and package identity.
- Run the verification plan selected for the exact change fingerprint; do not duplicate a matching in-progress worker.
- Use normal manual, protected, seal, promotion, tag, publication, and public-byte gates where the target policy requires them.
- The `.5` publication exceptions do not automatically apply to `.9`.

## Hard stops

Stop the affected target when its predecessor identity is lost, its reconstructed tree or package differs, the target engine cannot load it, transition evidence cannot be established, a tag conflicts, or downloaded public bytes differ. Stop the whole wave if shared source custody is lost, `main` would require history rewriting, or a shared semantic defect invalidates the family.

Transport failure is resumable publication work. Verify remote state and retry only the failed operation with the same frozen bytes; never rebuild, move a correct tag, or invent evidence.

## Machine-readable authority

For MIR 4.0, `dev` is the only active integration branch. `release/mir4-4.0.0` remains an inactive policy template until a separate source-freeze authorization names one exact `dev` commit. `main` remains at published MIR 3.2.11 until that identical tree and its already-built bytes have passed qualification, manual acceptance, independent acceptance, signing, sealing, and production go/no-go. Do not rebuild or add a commit between qualification and promotion.


- `.mir/branches.yml` defines branch and target routing.
- `.mir/targets.json` defines target capabilities.
- `.mir/releases/records/current.json` assigns current release roles.
- `.mir/releases/records/<version>.json` holds each release state and identity.
- `.mir/releases/waves/MIR3-Terminal-ChangeSet.json` owns the terminal wave.
- `docs/releases/mir-3-terminal-dot-9-programme.md` is the canonical human-readable plan.

If these surfaces disagree, stop and reconcile them before implementation or publication.
