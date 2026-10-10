---
title: "MIR 4 Local Artifact Retention And Storage"
status: current
applies_to: "MIR 4.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-07
supersedes: []
superseded_by: []
source_of_truth_for:
  - local-artifact-retention
  - mir4-local-artifact-classes
  - mir4-worktree-and-run-state-retention
---

# MIR 4 Local Artifact Retention And Storage

Local storage retains enough exact material to replay or diagnose a result without turning every worktree, engine run, or staging directory into a second archive. This page is the current retention policy. It does not widen a cleanup command's implementation scope or grant deletion, candidate, release, or publication authority.

The development-contract command-inventory drift check uses a tiny text fixture under `build/tmp` and the canonical inventory writer. It verifies the baseline, changes one source input and requires the stale-inventory rejection, then removes the verified fixture root. It creates no Git clone or worktree and needs no engine, dependency archive or package payload. Full package-construction checks retain their separate evidence requirements.

## Storage Classes

| Location | Class | Retention |
| --- | --- | --- |
| `C:\Projects\Factorio\testmods\<Factorio line>` or an explicitly selected library | Unique shared mod archives | Protected; never cleaned by repository tooling. Retired profiles do not require another copy of these archives. |
| `C:\Projects\Factorio\qualification-installs` | Exact local runtime installation | Protected; never cleaned by repository tooling. |
| `.mir/evidence/` | Tracked portable evidence | Governed release evidence; never cleaned as a local artifact. |
| `dist/` | Ignored local delivery and upload cache | Keep only the exact candidate, playtest, or portal-upload bytes needed on this machine. It is never Git-tracked custody and is not selected by routine build cleanup. |
| `build/results/assurance/` | Local content-addressed assurance and reuse copies | Protected from routine stale-result cleanup; promote any durable authority before deleting `build/`. |
| `build/results/validation/` | Current validation diagnostics and failure packets | Protected from routine stale-result cleanup. |
| Other `build/results/<run>` directories and top-level files | Ephemeral run output | Delete after the useful result has been summarized; the default stale threshold is seven days. |
| `build/tests/<series>/<32-lowercase-hex-guid>` | Private test-run boundary | Audited and removed only as one exact run root; never expanded into individual files from copied `repo`, `source`, `mods`, profiles, saves, or logs. |
| `build/mir4/<campaign>` | Governed local campaign root | Direct child only. It is eligible only when stale, ignored, lease-free, unreferenced across every selected worktree, free of direct and descendant custody markers, and no-follow-safe. It is not a blanket authority to remove arbitrary `build/` children. |
| `build/mir4/<campaign>/<run>` | Governed campaign-run scope | Audited only when the operator explicitly selects its immediate parent with `--campaign-root`. A run-level `result.json` identifies the attempt but is not permanent custody by itself; exact tracked references, other custody markers, live/interrupted leases, recent writes, and reparse points still retain the run. |
| `build/` | The sole repository-local generated root: package staging, caches, generated target material, temporary files, results, and any active linked-worktree placement selected by the resolved worktree policy | Reconstructible output may be removed after active commands have stopped and required compact authorities have been promoted. Git worktrees remain governed by the resolved `MIR_WORKTREE_HOME` policy and are never cleanup candidates merely because they are physically beneath `build/`. |
| `dist/playtest/` | Current local playtest handoff | May be refreshed only from qualified exact bytes; immutable rolling revisions are never overwritten. |

## Historical Distribution Custody

The repository does not track historical ZIP payloads in current trees. `.mir/distributions.json` binds every retained historical identity to one pinned Git predecessor tree, with its byte count and SHA-256. The materializer streams one requested blob into an ignored content-addressed cache, verifies its size and SHA-256 before use, and can make a verified private output copy beneath `build/` or `dist/`.

```powershell
# Inspect the pinned inventory without writing an archive.
.\tools\mir.ps1 mir4 distribution status

# Verify a historical blob exists and has its recorded Git-object size.
.\tools\mir.ps1 mir4 distribution verify --version 4.0.21000

# Restore exact local upload bytes only when they are needed.
.\tools\mir.ps1 mir4 distribution restore --version 4.0.21000 --output dist
```

`MIR_CACHE_HOME` selects a reusable cache root; otherwise every linked worktree resolves the registered primary checkout through Git metadata and shares its ignored `build/cache/mir-distributions`. Only immutable, digest-verified archives are shared. Mutable mod lists, settings, saves, logs, fixtures, and run output remain private to their run. No materializer downloads from GitHub or claims that GitHub assets are complete custody. The current observation records that 72 of 74 historical inventory rows match a GitHub asset digest and size, while `2.0.0` and `2.2.0` do not. The pinned Git predecessor is therefore required to recover all recorded historical bytes. This path has no tag, release, upload, or publication authority.

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

## Immutable Archive Optimization

`storage optimize` replaces a duplicate immutable mod ZIP with a verified same-volume hardlink to its exact existing library archive. It preserves the archive bytes and run evidence. The default discovery still scans `build/tests`; select one completed run to bound discovery to its direct `mods` archive files and avoid traversing copied checkouts, saves, userdata or child directories:

```powershell
# Preview one existing completed run; replace the example GUID with its exact identity.
.\tools\mir.ps1 storage optimize --test-run-root build/tests/suite/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# Apply only after reviewing that same scope.
.\tools\mir.ps1 storage optimize --test-run-root build/tests/suite/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --apply
```

The selector must be repository-relative under `build/tests` and end in a canonical 32-lowercase-hex GUID. The run must be stale under the selected age cutoff, have a terminal result, and have no immutable-input lease or reparse path. Application rechecks those conditions, the selected run boundary, source and target hashes, and exact file identities. Open handles prevent source mutation during replacement; failed replacement verification restores the original target. Recent, running, leased and ambiguous runs remain ineligible. Direct script callers can retain small `MaxScannedEntries`, `MaxPendingDirectories` and `MaxScanSeconds` budgets. Existing hardlinks yield no new optimization; preview counts and logical archive sizes are not measurements of physical space reclaimed. This command neither deletes a run nor changes native resource admission limits.

## Native Inputs And Run Finalization

Profiles are definition-only. Retain each required exact dependency archive once in the selected engine-family library, and launch normal serial tests directly against it. The repository owns the profile, versions/hashes, settings specification and scenario; the machine supplies explicit engine/library locations. Historical absolute paths remain provenance, not required directories on a new checkout. Missing selected inputs produce precise refusals and do not authorize restoring a retired profile, copying a modpack, extracting dependencies, downloading the whole collection or relocating archives to another volume.

The existing library activation adapter owns the actual library exclusively across cooperating checkouts. It verifies selected versions, dependency constraints and archive hashes, disables unrelated installed mods, and protects selected archive bytes with held read handles. It preserves the previous mod-list/settings controls in a durable journal before activating the selected controls or explicit defaults. It verifies the actual loaded selection and restores the previous controls after all owned processes exit. Interrupted activation requires journal recovery before another selection. Saves, configuration, logs and temporary output remain in the approved checkout run root. Neither an update nor `--sync-mods` is part of execution.

No normal native test creates dependency copies, archive hard links, extracted mods or replacement populated profiles. Useful immutable build/custody hard links remain permitted only when both endpoints are inside the executing checkout. They are not independent snapshots: aliases share data, attributes and security metadata. Removing one alias does not free the archive payload while another remains, and changing permissions or read-only attributes through an alias changes shared state. Retiring profile entries therefore requires verified surviving membership and a measured free-space delta, not a sum of directory-entry lengths.

The migrated upgrade, package-smoke/release-engine, Research Library, personal-state continuity, F200 settings-cap transition, community power manufacturing and current F210 Tin consumers use the configured flat library. Small MIR-owned fixture archives are prepared through their existing input operations and verified before installation; this does not authorize dependency staging. The K2 continuation consumer also uses the flat library, but its retained exact 2.1.20/K2 2.1.3 observation lock still requires those genuine inputs. Library migration does not qualify a newer engine or package. See [testing and fixture strategy](testing.md) for current commands and exact native observations.

Unmigrated entry points refuse execution before resolving engines or allocating output. This includes the older candidate-retention runner, material/route observers, historical private-runtime, V2/V3 migration and standalone no-MIR Library runners. Their code, fixtures and historical results remain available for review; source-side tests of old bounded internal leases do not authorize a native staging run. Convert a required affected scenario through the existing activation adapter before executing it. The direct-library suite invokes all 29 retired entry points in fresh PowerShell hosts with absent inputs and verifies the retirement diagnostic and absence of output. Its tiny-file A/B/A, exclusion, exact-version/hash, settings, concurrency and interruption checks are host-side evidence, not replayed gameplay campaigns.

Before output-producing batches, run the existing development-health check and declare measured workload and new-output budgets through `NativeProbeResources`. One heavyweight process tree includes its materializer/generator and engine children. Library archives are existing inputs, not newly written run payload. Count genuinely new packages, fixtures, settings, saves, logs and temporary output separately from retained system disk/RAM/commit reserves. Existing internal lease accounting excludes only verified same-file aliases and rechecks their identities. A process budget is a sampled watchdog allowance, not a measured peak or a hard allocation guarantee. Never reduce system reserves to make a run pass; correct obsolete workload estimates only against actual comparable measurements.

At completion retain the compact result, exact identities, relevant failure logs and necessary unique reproducers. Preserve failed receipts as failed and keep evidence at its original source/package/environment identity. A post-MIR prototype capture is not a clean compiler input. Repeated source/captured-fact checks require no populated profile or game launch; native checks remain necessary for affected package loading, actual production, saves, graphical interaction, multiplayer and performance.

Retire proven disposable surrounding output through the existing scoped cleanup commands after required evidence is preserved and active owners have stopped. Do not keep copied engine installations, complete failed modpacks or raw success campaigns merely because they might be useful later. Do not delete unique saves, selected current inputs, delivered packages or interrupted transaction custody. `Invoke-MIRPerformanceQualification.ps1` retains failure directories and removes success directories only after its compact evidence validates; `-KeepArtifacts` remains an explicit diagnostic choice. Reused input bytes do not become an independent cold construction or qualification result.

The former per-run hard-link staging description is retained in Git history for its historical receipts. Current execution follows this direct-library contract; no retained old receipt makes its populated directory a continuing dependency. Current campaign scratch stays in approved primary-checkout paths, and cleanup never scans arbitrary disks or creates replacement archive stores.
