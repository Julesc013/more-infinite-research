---
title: "Deterministic Backport Reconstruction"
status: current
applies_to: "3.2.2+ and maintained backports"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-26
supersedes: []
superseded_by: []
---

# Deterministic Backport Reconstruction

MIR backports use an explicit dual-parent integration boundary. The first parent preserves the target Factorio lineage. The second parent is the immutable modern release tag whose semantics are being projected. The resulting target package is independently built, tested, attested, qualified, and sealed.

The canonical contract for MIR 2.5.0 is `.mir/backports/2.5.0.json`. It binds the immutable MIR 2.4.9 baseline, the exact MIR 3.2.2 package source and release tag, the preintegration Factorio 2.0 checkpoint, every adapted package path, the target capability profile, and the exact expected candidate identities.

Before integration, create and publish the manifest's annotated `archive/2.5-pre-3.2.2` tag at the locked preintegration commit. This tag retains the complete reviewed target projection history even if `tmp/2.0` is later deleted.

Validate the contract while the source and archive tags are still pending:

```powershell
.\scripts\Test-MIRBackportManifest.ps1 -AllowPendingTags
```

After the exact `3.2.2` and preintegration archive tags exist, reconstruct the target line in a disposable worktree:

```powershell
.\scripts\mir.ps1 backport materialize `
  --manifest .mir/backports/2.5.0.json `
  --worktree C:\Projects\Factorio\mir-reconstructed-2.5
```

The materializer verifies both tags and the 2.4.9 ancestry, creates a target-first/source-second merge, reapplies the exact reviewed Factorio 2.0 projection tree, checks the target profile and source lock, builds twice, verifies the expected archive and content hashes, and writes a reconstruction receipt.

Before sealing, delete the disposable reconstruction worktree, rerun the command from the immutable tags, and require the same integration tree and package identities. This branch-loss rehearsal proves that `tmp/2.0` is a workspace rather than unique source authority.

No unclassified package path may pass. Each modern-to-target difference must be one of `shared-unchanged`, `shared-with-target-adapter`, `factorio-2.1-only`, `release-evidence-only`, or `intentionally-excluded`. Runtime, performance, manual, protected, and seal evidence remain target-specific and cannot be inherited from the modern release.
