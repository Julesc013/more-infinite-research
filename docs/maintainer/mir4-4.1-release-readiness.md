---
title: "MIR 4.1 Release Readiness"
status: current
applies_to: "MIR 4.1.0"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-4.1-release-readiness
  - mir4-4.1-resource-bounded-release
  - mir4-4.1-one-minute-playtest-gate
---

# MIR 4.1 release readiness

MIR 4.1.0 is prepared through one public command surface and a set of bounded application modules. Tracked source freezes before construction. The durable release window lives outside the repository and binds the exact source commit, four package archives, four normalized content roots, exact engine identities, runtime and upgrade evidence, release copy, technical seal, signed local tag object, and exact-main promotion receipt.

## Fixed release identities

| Target | Distribution | Engine policy | Direct predecessor |
| --- | --- | --- | --- |
| F210 | `4.1.21000` | Latest installed official Factorio 2.1 experimental, exact identity per proof | `4.0.21000` |
| F200 | `4.1.20000` | Fixed Factorio 2.0.77 executable | `4.0.20000` |
| F110 | `4.1.11000` | Fixed Factorio 1.1.110 executable | `4.0.11000` |
| F100 | `4.1.10000` | Fixed Factorio 1.0.0 executable | `4.0.10000` |

F210 is a moving channel, not a floating proof. Re-observe it before its lane. Any version, executable, runtime API, prototype API, Steam manifest, or changelog change invalidates old F210 evidence and opens API-opportunity, compatibility, implementation, fixture, performance, documentation, and stable-transition review. If MIR adopts a newer API, raise its Factorio floor through an exact qualified change. Reopen this policy when Factorio 2.1 first becomes stable.

## Resource containment

Keep work and evidence on admitted external roots. The system-drive hard stop is 15 GiB free, the work-volume reserve is 30 GiB, admission requires at least twice the estimated peak plus reserve, and runtime admission requires at least 4 GiB free RAM. Abort a child process below 2 GiB free RAM. Run one Factorio process and one materialization at a time; portable static work may use at most two workers.

The monitor appends samples to JSON Lines rather than retaining them in memory. Directory measurement streams file metadata. Each expensive operation runs in a fresh process. Successful expanded work is deleted only after the accepted archive, summary, and custody identity are verified; failed or ambiguous work is retained for classification. Cleanup must pass an absolute containment check and must never target a dirty worktree, unique evidence, public package, or unexplained path.

## Stable-line ancestry precondition

Candidate construction fails before materialization unless the exact local `origin/main` object is an ancestor of the proposed source. MIR 4.1 required one historical lineage reconciliation because the post-4.0 stable commits and the continuing development line shared content but not ancestry. The reconciliation preserves the reviewed development tree, adds exact stable `main` as an ancestor, rewrites neither accepted line, and restores the non-forced exact-promotion precondition. Of the 96 paths changed on stable `main` after the common base, 44 were already byte-identical on `dev`; the remaining paths had evolved under the accepted 4.1 programme, and all eight retired validation paths had registered canonical successors under `tests/`.

This is a one-time ancestry repair, not permission to merge older-lane content wholesale into a newer product line. Subsequent stable corrections continue to require an explicit semantic forward-port disposition.

## Commands

```powershell
.\tools\mir.ps1 mir4 release-engine readiness-check --work-root <external-work>
.\tools\mir.ps1 mir4 release-engine candidate-build --work-root <external-work> --evidence-root <external-evidence>
.\tools\mir.ps1 mir4 release-engine qualification --work-root <external-work> --evidence-root <external-evidence>
.\tools\mir.ps1 mir4 release-engine independent-verify --evidence-root <external-evidence>
.\tools\mir.ps1 mir4 release-engine technical-seal --work-root <external-work> --evidence-root <external-evidence>
.\tools\mir.ps1 mir4 release-engine prepare-tag --evidence-root <external-evidence> --signing-key <protected-ed25519-private-key>
.\tools\mir.ps1 mir4 release-engine promotion-plan --evidence-root <external-evidence>
.\tools\mir.ps1 mir4 release-engine promote --evidence-root <external-evidence>
```

Build and qualification commands resume only from exact verified receipts. Every successful fresh-load scenario, upgrade matrix, and completed target has its own checkpoint bound to the exact source commit/tree, engine executable, candidate archive/content, and evidence digest. Missing checkpoints run; any present but mismatched checkpoint blocks as ambiguous instead of being silently reused. Candidate A is summarized and its expanded tree removed before candidate B. Targets execute serially. Independent verification reopens every ZIP, recomputes archive and normalized content identities, checks package membership and metadata, re-observes each engine, hashes runtime and upgrade summaries, and streams every resource ledger.

## Seal and promotion

The technical seal keeps `human_playtest=pending` and `publication_authorized=false`. The release-window capsule passes an offline extraction and custody comparison before promotion. The signed annotated `v4.1.0` tag object is prepared locally or in protected signing custody but remains absent remotely.

Promotion is a non-forced fast-forward from the exact sealed `origin/dev` object ID to `origin/main`. It temporarily removes only applicable pull-request rules, restores each complete ruleset payload in `finally`, reads the configuration back, and requires `origin/dev == origin/main == sealed source`. Ruleset comparison canonicalizes rules by type because GitHub may normalize their array order without changing policy. It runs no post-promotion tests because that would not change the sealed source or packages.

## Human gate and publication

Run `Start-MIR410Playtest.ps1` from the external release window for F210 and F200. It verifies the sealed package and engine digests before opening the isolated session. The only accepted response is `GO` or `NO-GO` from the maintainer.

On `NO-GO`, `Finalize-MIR410.ps1` records rejection and performs no tag or publication action. Do not reset `main`; correct forward through a new source commit, package set, evidence chain, seal, and promotion.

On `GO`, the finalizer verifies both remote branches, every asset, the signed annotated tag object, and the technical seal. It pushes the existing tag, creates a draft GitHub release with `--verify-tag`, attaches the sealed assets, validates the inventory, publishes, redownloads every asset, and compares public hashes. It cannot build, test, qualify, regenerate documentation, or modify source. The prepared Mod Portal package/copy pairs are then ready for the maintainer to upload unchanged.
