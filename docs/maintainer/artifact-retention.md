---
title: "Local Artifact Retention And Storage"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Local Artifact Retention And Storage

Local validation must leave enough evidence to diagnose and summarize a run without turning every worktree into a permanent copy of transient Factorio staging data.

## Storage Classes

| Location | Class | Retention |
| --- | --- | --- |
| `C:\Projects\Factorio\testmods_*` | Shared local mod library | Protected; never cleaned by repository tooling. |
| `C:\Projects\Factorio\qualification-installs` | Exact local runtime installation | Protected; never cleaned by repository tooling. |
| `.mir/evidence/` | Tracked portable evidence | Governed release evidence; never cleaned as a local artifact. |
| `dist/` tracked release archives | Release authority | Never cleaned as a local artifact. |
| `artifacts/assurance/` | Content-addressed assurance and reuse evidence | Protected from stale-artifact cleanup. Prune only through its own evidence lifecycle. |
| `artifacts/validation/` | Current validation diagnostics and failure packets | Protected from stale-artifact cleanup. |
| Other `artifacts/<run>` directories and top-level files | Ephemeral run output | Delete after the useful result has been summarized; the default stale threshold is seven days. |

## Audit And Cleanup

Preview stale output in the current worktree:

```powershell
.\scripts\mir.ps1 storage audit
```

Preview stale output across registered worktrees located beside the current worktree:

```powershell
.\scripts\mir.ps1 storage audit --all-worktrees
```

Delete the reviewed set older than seven days:

```powershell
.\scripts\mir.ps1 storage clean --all-worktrees --apply
```

Delete completed ephemeral output immediately after inspection by setting the age threshold to zero:

```powershell
.\scripts\mir.ps1 storage clean --older-than-days 0 --apply
```

Cleanup is dry-run-first unless `--apply` is present. It considers only immediate children of an `artifacts` root, requires every target to be ignored by Git, refuses reparse points, revalidates each target immediately before deletion, and refuses applied cleanup while Factorio is running. Deletion is permanent, so promote any compact evidence needed for a release or future diagnosis before applying it.

## Run Finalization

When a run finishes, retain its compact summary, failure packet, or authority-bound evidence in the governed destination, verify that the retained record identifies the exact source, candidate, verifier, and target where applicable, then remove the bulky run directory. Do not retain copied Factorio installations, scenario mod directories, decompressed caches, duplicate candidate archives, or raw performance campaigns merely because they may be useful later.

The scenario runners already prefer NTFS hardlinks for local mod ZIPs when the source and staging directory share a volume. Windows and Explorer report each hardlink path in logical directory totals even though the file content occupies physical disk once, so logical artifact size can substantially exceed physical storage use. Keep `testmods_*` as the shared source library and remove stale staging links instead of deleting or duplicating the library.

Use a different output drive for deliberately long campaigns when practical. The retention rules still apply to that output root, but the repository cleanup command intentionally operates only on registered worktrees beneath the current project directory and does not roam arbitrary disks.
