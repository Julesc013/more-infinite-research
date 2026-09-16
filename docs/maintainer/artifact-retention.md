---
title: "MIR 4 Local Artifact Retention And Storage"
status: current
applies_to: "MIR 4.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-09-16
supersedes: []
superseded_by: []
source_of_truth_for:
  - local-artifact-retention
  - mir4-local-artifact-classes
  - mir4-worktree-and-run-state-retention
---

# MIR 4 Local Artifact Retention And Storage

Local storage retains enough exact material to replay or diagnose a result without turning every worktree, engine run, or staging directory into a second archive. This page is the current retention policy. It does not widen a cleanup command's implementation scope or grant deletion, candidate, release, or publication authority.

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
| `build/tests/<series>/<32-lowercase-hex-guid>` | Private test-run boundary | Audited and removed only as one exact run root; never expanded into individual files from copied `repo`, `source`, `mods`, profiles, saves, or logs. |
| `build/mir4/<campaign>` | Governed local campaign root | Direct child only. It is eligible only when stale, ignored, lease-free, unreferenced across every selected worktree, free of direct and descendant custody markers, and no-follow-safe. It is not a blanket authority to remove arbitrary `build/` children. |
| `build/mir4/<campaign>/<run>` | Governed campaign-run scope | Audited only when the operator explicitly selects its immediate parent with `--campaign-root`. A run-level `result.json` identifies the attempt but is not permanent custody by itself; exact tracked references, other custody markers, live/interrupted leases, recent writes, and reparse points still retain the run. |
| `build/` | The sole repository-local generated root: package staging, caches, generated target material, temporary files, results, and any active linked-worktree placement selected by the resolved worktree policy | Reconstructible output may be removed after active commands have stopped and required compact authorities have been promoted. Git worktrees remain governed by the resolved `MIR_WORKTREE_HOME` policy and are never cleanup candidates merely because they are physically beneath `build/`. |
| `dist/playtest/` | Current local playtest handoff | May be refreshed only from qualified exact bytes; immutable rolling revisions are never overwritten. |

## Audit And Cleanup

Preview stale output in the current worktree:

```powershell
.\tools\mir.ps1 storage audit
```

Preview stale output across the registered worktrees for the current Git common directory:

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

Preview and then remove superseded child runs inside one governed campaign without selecting the campaign root itself:

```powershell
.\tools\mir.ps1 storage audit --artifact-type campaign --campaign-root build/mir4/a05-k2-materials
.\tools\mir.ps1 storage clean --artifact-type campaign --campaign-root build/mir4/a05-k2-materials --apply
```

Cleanup is dry-run-first unless `--apply` is present. Its typed roots are immediate children of `build/results/` (excluding protected `assurance` and `validation`), run boundaries below `build/tests/` (including canonical 32-lowercase-hex GUID leaves), immediate children of `build/packages/` (excluding `development-contracts`), direct canonical 32-lowercase-hex child directories of `build/packages/development-contracts/`, and governed direct children of `build/mir4/`. Noncanonical development-contract children are reported but never selected. `--campaign-root` requires `--artifact-type campaign` alone and must name exactly one repository-relative direct child of `build/mir4`; it changes the candidates to that campaign's immediate child runs. A governed campaign is protected by tracked references in every selected worktree and by direct or descendant custody markers such as `result.json`, `receipt.json`, `evidence.json`, candidate/predecessor records, offline-input records, package custody, seals, source proof, or `*pin*.json`. In explicit child-run scope, `result.json` is non-pinning because superseded attempts normally contain one; exact tracked references and every other custody/lease rule remain fail-closed. Every selected target must be ignored by Git and passes a second exact typed-root, custody/lease/reference, age, and recursive no-follow reparse audit immediately before deletion; applied cleanup refuses to run while Factorio is running. Registered worktrees are resolved through Git metadata, including a primary checkout initialized with `--separate-git-dir`, rather than by parent-directory inference. Deletion is permanent, so promote any compact evidence needed for a release or future diagnosis before applying it.

The scanner holds only pending directory paths, not an entire copied mod library or checkout in memory. It batches tracked-reference inspection per selected worktree instead of starting one Git search for each candidate. A normal audit has a 90-second whole-audit limit and a 250,000-entry no-follow limit per candidate; it prints periodic progress and stops before deletion when the whole-audit limit is reached. A candidate that reaches the per-candidate limit is reported as `scan-budget-exceeded` and is never selected. A root newer than the retention cutoff can be reported as recent without recursively sizing every member, but it remains ineligible; any stale candidate must complete the no-follow scan before selection and again immediately before deletion. `logical_size=not-scanned` means the row was already ineligible and was intentionally not recursively sized, not that it consumes zero bytes. The canonical command also accepts the distinct `campaign` artifact type; keep the public CLI router and command inventory synchronized when exposing that selector.

The retired `.work/` path is forbidden and its reappearance fails the layout gate. Existing ignored `artifacts/`, `out/`, and root `tmp/` content is a read-only legacy quarantine until an explicit governed retirement records its disposition; ordinary commands must not write there, and routine cleanup does not delete it.

## Run Finalization

When a run finishes, retain its compact summary, failure packet, or authority-bound evidence in the governed destination, verify that the retained record identifies the exact source, candidate, verifier, target, and input/evidence identity where applicable, then remove the bulky run directory. A reused immutable input is not an independent cold construction or qualification observation. Do not retain copied Factorio installations, scenario mod directories, decompressed caches, duplicate candidate archives, or raw performance campaigns merely because they may be useful later. `Invoke-MIRPerformanceQualification.ps1` enforces this by keeping raw performance directories on failure and removing them after compact evidence validates successfully; pass `-KeepArtifacts` only for a deliberate diagnostic investigation.

The scenario runners may use an NTFS hardlink for a verified immutable local mod ZIP when the source and staging directory share a volume. An input materializer must verify the expected identity before and after use and record whether it realized a `hardlink` or a `copy`; a compatible runner may copy when a link is preferred. Hardlinks are not copy-on-write isolation: aliases share bytes, attributes, and security metadata. Windows and Explorer report each alias in logical directory totals even though the file content occupies physical disk once, so logical artifact size can substantially exceed physical storage use. Keep `testmods_*` as the shared source library and remove stale staging links instead of deleting or duplicating the library. Never junction or symlink a whole mutable `mods` directory, profile, mod-list, settings override, save, userdata, or log tree into a run: each run owns those mutable files privately. Cross-volume hardlinks are unavailable; uncertain identities, mutable inputs, reparse points, and link/access failures require an explicit verified private-copy fallback after capacity admission. Do not clear read-only attributes or alter permissions through a hardlink alias.

Use a different output drive for deliberately long campaigns when practical. The retention rules still apply to that output root, but the repository cleanup command intentionally operates only on worktrees registered to the current Git common directory and does not roam arbitrary disks.
