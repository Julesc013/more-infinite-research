---
title: "Local Artifact Retention And Storage"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-06
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
| `build/results/assurance/` | Local content-addressed assurance and reuse copies | Protected from routine stale-result cleanup; promote any durable authority before deleting `build/`. |
| `build/results/validation/` | Current validation diagnostics and failure packets | Protected from routine stale-result cleanup. |
| Other `build/results/<run>` directories and top-level files | Ephemeral run output | Delete after the useful result has been summarized; the default stale threshold is seven days. |
| `build/` | The sole repository-local generated root: package staging, caches, generated target material, temporary files, and results | Reconstructible; delete after active commands have stopped and required compact authorities have been promoted. Git worktrees are forbidden here. |
| `dist/playtest/` | Current local playtest handoff | May be refreshed only from qualified exact bytes; immutable rolling revisions are never overwritten. |

## Audit And Cleanup

Preview stale output in the current worktree:

```powershell
.\tools\mir.ps1 storage audit
```

Preview stale output across registered worktrees located beside the current worktree:

```powershell
.\tools\mir.ps1 storage audit --all-worktrees
```

Delete the reviewed set older than seven days:

```powershell
.\tools\mir.ps1 storage clean --all-worktrees --apply
```

Delete completed ephemeral output immediately after inspection by setting the age threshold to zero:

```powershell
.\tools\mir.ps1 storage clean --older-than-days 0 --apply
```

Cleanup is dry-run-first unless `--apply` is present. It considers only immediate children of the canonical `build/results/` root, requires every target to be ignored by Git, refuses reparse points, revalidates each target immediately before deletion, and refuses applied cleanup while Factorio is running. Deletion is permanent, so promote any compact evidence needed for a release or future diagnosis before applying it.

The retired `.work/` path is forbidden and its reappearance fails the layout gate. Existing ignored `artifacts/`, `out/`, and root `tmp/` content is a read-only legacy quarantine until the post-2.5.5 storage inventory; ordinary commands must not write there, and this focused migration does not delete it.

## Run Finalization

When a run finishes, retain its compact summary, failure packet, or authority-bound evidence in the governed destination, verify that the retained record identifies the exact source, candidate, verifier, and target where applicable, then remove the bulky run directory. Do not retain copied Factorio installations, scenario mod directories, decompressed caches, duplicate candidate archives, or raw performance campaigns merely because they may be useful later. `Invoke-MIRPerformanceQualification.ps1` enforces this by keeping raw performance directories on failure and removing them after compact evidence validates successfully; pass `-KeepArtifacts` only for a deliberate diagnostic investigation.

The scenario runners already prefer NTFS hardlinks for local mod ZIPs when the source and staging directory share a volume. Windows and Explorer report each hardlink path in logical directory totals even though the file content occupies physical disk once, so logical artifact size can substantially exceed physical storage use. Keep `testmods_*` as the shared source library and remove stale staging links instead of deleting or duplicating the library.

Use a different output drive for deliberately long campaigns when practical. The retention rules still apply to that output root, but the repository cleanup command intentionally operates only on registered worktrees beneath the current project directory and does not roam arbitrary disks.
