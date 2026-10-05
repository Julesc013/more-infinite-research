---
title: "MIR 4 Local Artifact Retention And Storage"
status: current
applies_to: "MIR 4.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-06
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

## Run Finalization

When a run finishes, retain its compact summary, failure packet, or authority-bound evidence in the governed destination, verify that the retained record identifies the exact source, candidate, verifier, target, and input/evidence identity where applicable, then remove the bulky run directory. A reused immutable input is not an independent cold construction or qualification observation. Do not retain copied Factorio installations, scenario mod directories, decompressed caches, duplicate candidate archives, or raw performance campaigns merely because they may be useful later. `Invoke-MIRPerformanceQualification.ps1` enforces this by keeping raw performance directories on failure and removing them after compact evidence validates successfully; pass `-KeepArtifacts` only for a deliberate diagnostic investigation.

Native test mod profiles contain manifests, small writable settings and verified same-volume hard links to a shared archive library. Keep each distinct archive once; do not keep complete copied mod sets or repeatedly copy and delete them. Native lease consumers use `New-MIRImmutableInputLease -RequireHardLinks`; the compatibility audit accepts only `Hardlink` and requires a materialized MIR ZIP. Link failure, missing inputs, mismatched hashes or unrelated existing aliases refuse staging without an archive-copy fallback. Historical records retain their original staging policy and do not become current native passes. Hardlinks share bytes, attributes and security metadata: they are not copy-on-write isolation. Logical directory totals count every alias although content occupies disk once. Keep mod lists, settings overrides, saves, userdata and logs private to the selected run; writable settings must never be hardlinked. Do not junction or symlink entire mutable profile trees. Cross-volume input links require selecting the retained same-volume library, not copying a profile to another drive. Do not clear read-only attributes or alter permissions through a hardlink alias.

The exact ProcessIR capture command requires explicit `-CaptureId` selections for live execution and admits the whole selected job before staging. Each repetition leases candidate and dependency archives through strict hardlinks, with private observer files, settings, logs and saves. `-Check` verifies the retained reference offline. Live outputs use unique run roots; existing runs and populated reference directories are preserved. `-PublishReference` requires the complete authority selection and repetition count plus an empty reference destination. It exports compact records without copying archives or internal runtime files. These developer preview captures do not grant player or release acceptance.

The controlled material-route and current F210 Tin and final Bob/Angel observer harnesses use `tools/lib/validation/NativeProbeResources.ps1` to compose the existing resource governor and immutable lease. Their default output roots are under `build/p`; callers must supply a positive `ExpectedPeakMemoryMiB` budget and may select a bounded `MaxNewOutputMiB` budget. Admission precedes staging, materialization and every engine call, including both observers' `PrepareOnly` paths. The materializer runs as a monitored child through the canonical package library and selects source 4.2.1 / F210 distribution 4.2.21001. Engine probes retain streamed stdout/stderr and resource ledgers, including failed actors, and keep temporary directories private to the owned job. Both observers link immutable archives under strict leases and retain terminal custody; settings, mod-list, saves and userdata remain private files. Their `AuditLogPath` modes only read existing diagnostic logs. The final observer's `RecoverRunRoot` reads a completed governed observation whose committed source, harness, four fixture files, stage receipt, engine, package version, strict input custody, process inventory, logs and save still match. It rechecks the existing observation oracles without launching an engine, materializing a package or rewriting historical receipts. Historical schema-1 and incomplete rows remain preserved and do not qualify as current governed observations. Controlled resource and recovery-reader fixtures do not qualify native packages or material outcomes.

The consumed Research Library harness uses the same admission, monitored materializer, streamed process ledgers and strict candidate lease. F210 selects the current Steam 2.1 executable; F200 selects `D:\Programs\Factorio\2.0\bin\x64\factorio.exe`. Before engine use, a supplied candidate must have the exact source 4.2.1 numeric identity, filename and ZIP root, contained canonical paths, and five browser modules matching current source bytes. Default construction uses the existing materializer for 4.2.21001 or 4.2.20001. Every engine phase, including version detection, runs inside the owned process tree; Steam launch identifiers remain in the child environment and UTF-8 preserves diagnostic text. Result receipts bind source commit/tree, engine, candidate, harness, resource adapter, driver, process inventory and terminal input custody. The existing native GUI, headless and graphics save/reload oracles remain required; controlled admission and argument fixtures do not qualify those behaviors.

The personal-state continuity harness also admits its complete server and two-client process tree before staging. Its default source is 4.2.1, with 4.2.0 retained as an explicit historical selection. Candidate README bytes are checked against the canonical source binding and the materializer's version transformation. Initial, configuration-change, removal and re-addition profiles lease the same archives through strict hardlinks; private settings move between completed phases. The removal profile omits the MIR archive, and re-addition links the original candidate again. The parent binds a read-only request to its owned worker and verifies the terminal input receipts and lifecycle result. All profile aliases count conservatively toward this job's output budget. Controlled small actors and archive admission checks do not establish Factorio lifecycle, physical input or multiplayer acceptance; the preserved gameplay oracles must execute on the affected package.

The retained Angel Tin, combined Bob/Angel Tin, route-safety and Aluminium audit runners also lease their candidate and exact dependency archives through strict hardlinks. Their shared input adapter verifies the original archive locks and embeds terminal custody in new results; private fixture archives, settings and logs remain separate. Their historical engine, dossier and outcome assertions are preserved. This staging correction neither reruns those historical profiles nor widens their original acceptance to the current release.

The Tin browser explanation runner uses that same strict input adapter for its candidate and three Bob archives. It admits an explicit memory/output budget before engine lookup or staging and governs version queries, package generation and engine runs through the existing native probe adapter. New candidate identity is `4.2.21001`; the original Factorio 2.1.17 hash, dependency locks, dossier and gameplay/browser assertions remain unchanged. Its unavailable historical engine lock remains a qualification boundary: do not retarget Steam or treat source and staging checks as a current native browser pass.

The impact manifest explicitly maps the two Research Library harnesses, the shared material-audit adapter and its four consumers. Changes to these known test paths retain the baseline compiler and package checks instead of triggering the full runtime fallback through missing mappings. Immutable-input checks remain selected. Unknown runtime harnesses still escalate, and player runtime source retains its broader checks. `Test-MIRAssurance.ps1 -ImpactRoutingOnly` verifies these selections without creating engine stages, packages, clones or worktrees. Current gameplay qualification still uses the affected native profile and exact trusted inputs; a narrow impact mapping is not evidence of its acceptance.

The passive-repair host probe also leases its selected MIR archive through a strict hardlink and records terminal input custody. Its version probe and original enabled/default-off save and reload calls use the shared resource governor with declared 2048 MiB memory and 120 MiB output budgets. It refuses an omitted memory budget before staging, preserves the original failure during cleanup, and keeps fixture code, settings, saves and logs private. Its exact harness path has a focused impact mapping. Controlled tests exercise the actual input and engine adapters without Factorio; the original gameplay assertions still require the affected native run. Other historical runners that still copy archives remain conversion work.

Both current Bob/Angel observers retain the original exact archive names and hashes. When an archive is absent from the preserved stage, `LocalModLibraryDirs` may supply its existing checksum-matching library file; the local default is `C:\Projects\Factorio\testmods\2.1`. An existing staged archive with different bytes fails rather than falling back. Resolution reads only the named files, creates no restored staging copy, records each source and its provenance, and retains strict lease checks before engine use. Missing inputs and differing library bytes remain failures; no newer or same-version replacement is silently substituted.

The retained Tin level-four production consumer now takes `CandidateZip`, its `SourceMaterializationPath`, and the small exact `SettingsPath` separately, with five checksum-bound Bob inputs resolved from `LocalModLibraryDirs`. Fresh execution does not require or rebuild the old copied profile. Its existing materializer receipt must bind the current player source and F210 source 4.2.1 identity; the reader rehashes the ZIP inventory and verifies complete binding membership and current runtime bytes without constructing another package. Declare `ExpectedPeakMemoryMiB` and `MaxNewOutputMiB` before preparation or execution; version, create and reload calls share the native governor and total write allowance. The historical 2.1.20 engine lock, four fixture files, 8% bonus and 108-from-100 output oracle remain unchanged. `RecoverRun` retains its separate historical custody checks and does not rebind old evidence to a current candidate. Controlled input and actor checks establish neither native production nor current-package acceptance.

Each probe's write budget includes cumulative new output and a reserved result allowance. Only verified same-file aliases registered from a strict lease are excluded from logical tree totals; every budget check revalidates their file identities and lengths, including terminal result writing. The generated candidate's original bytes, fixtures, logs, saves and receipts remain counted. This accounting does not measure reclaimed physical space or change the existing free-volume, RAM and system-commit admission limits. Memory enforcement remains a sampled watchdog, and declared budgets must be compared with measured peaks before qualification claims. The selected material-route and Research Library commands forward the actual target engine and line, with declared 2048 MiB memory and 120 MiB new-output budgets; those declarations are not peak measurements. Focused resource fixtures use tiny owned processes and synthetic archive/driver inputs; they do not launch Factorio or construct a real player package and cannot substitute for native evidence.

Keep current campaign scratch in the approved primary-checkout paths and admit a bounded batch only after measuring capacity. Preserve original inputs and delivered packages; inspect eligible owned staging when capacity is insufficient. The repository cleanup command operates only on worktrees registered to the current Git common directory and does not roam arbitrary disks.
