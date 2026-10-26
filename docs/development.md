---
title: "Development guide"
status: draft
applies_to: "MIR replacement development"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-development-guide
---

# Development guide

## Start with a bounded task

Read root agent instructions, the [specification index](../spec/README.md), and the one or two relevant contracts. Inspect current `git status`, exact source and active jobs once. Preserve dirty/untracked work and unique receipts. Do not reset to a historical planning commit.

A useful task packet is short:

```text
Outcome:
Existing requirement/incident IDs:
Input source/package/engine refs:
Permitted files:
Independent expected behavior:
Simplest implementation and work bound:
Tests and actual existing commands:
Stop condition:
```

For the first port, recover actual identity/tuning/settings from the pinned baseline. Do not invent a cleaner-looking replacement ID. Host expected output must not be generated from the candidate and then declared independent.

## Community bugs and request continuity

Maintain the [existing community request ledger](../spec/programmes/community-requests.json) through `CONT-15`; preserve original IDs, MIR 4 crash/failure evidence, unresolved bugs and technology-tuning requests. Carry them into affected MIR 5 work and regression selection rather than closing them because the architecture changes. `SCI-UNLOCK-01` records the recurring approved science binding startup failures, the reported unsuccessful mod-removal attempts and missing reproduction evidence. It remains open until exact affected-package qualification supports closure. This intake does not claim a fix.

## Work in small vertical slices

The additional F001–F012 request is a separate best-effort GitHub delivery obligation under the [target contract](../spec/targets.md#additional-historical-editions), with F013–F210 retaining release priority. Buildable extra editions receive explicit feature/installation/qualification limits; unavailable inputs do not become invented support or implicit release blockers. The separate [early target record](../targets/early-editions.json) selects only the actual finite data adapter. F018/0.18.47 is selected as a normal edition, with its shared-source port and applicable native qualification required.

Follow the maintainer's [edition scheduling order and product priorities](../spec/targets.md#primary-target-and-earlier-editions) when selecting MIR5 work. Preserve the normal edition set, including selected F018, through the same capability-based source and version encoding, with common feature, setting and presentation semantics wherever native capabilities permit. Scheduling priority does not waive final current-package and affected native checks for every delivered target subset. Reuse exact unchanged evidence under its original identity and state remaining gaps by edition; an unqualified normal edition remains an open release obligation.

Make a native family work end to end, then exercise a different native effect, a staged/native-owner integration and stateful caps/runtime. Keep partial packages off production saves. A successful tiny package is not a full-product migration or performance claim.

Use one implementer, one independent review responsibility and one test worker within the existing three-slot capacity. Workers must have nonoverlapping edits. Reuse running native campaigns; at most one heavy scenario per admitted machine. Exact archive libraries/settings are preserved and restored by existing qualified tools.

## Coordinate Black Glass and Aero through GitHub

Black Glass owns the current integration branch, the sole native-test lane and release coordination. The current branch and frozen test inputs are named in [progress](progress.md). Aero15X independently reviews pushed commits and may prepare corrections on separate branches and PRs. Use a bounded file responsibility in each task/PR, fetch remote changes before integration, and reconcile overlapping edits explicitly. Never reset another worker's changes, force-push a shared review branch or substitute a moving branch head for a test's full source commit.

Push each reviewable unit promptly. Commit bodies and PR descriptions record the concrete defect or outcome, changed behavior, independent expected result, actual commands and results, exact source/package identities where applicable, and remaining limitations. Finish required checks and merge completed units into `dev` while later qualification continues. Merge updated `dev` into an already published work branch when needed; preserve the commit identities that Aero reviews and native workers consume. Keep frozen-input custody branches reachable until their jobs and evidence readback finish.

After accepted MIR5.0.0 publication and verified local delivery, continue with5.0.1 bug fixes, measured performance improvements and further stress qualification. Use actual review findings and observed failures to select that work. This follow-up authorization does not waive any5.0.0 acceptance gate or permit an untested release.

## Local development builds, upstream changes and advanced forks

For a local replacement build, keep the official mod name `more-infinite-research`. Factorio selects one enabled version of a named mod, so this is an upgrade-style replacement of the installed MIR rather than a side-by-side installation. That identity deliberately keeps the packaged `__more-infinite-research__` imports, existing settings, technologies, migration history and draft API consumers pointed at the local build.

For MIR5 development, start from dev: main remains the published release until qualified promotion. A local build needs the existing Python packager, not release credentials or Factorio archives. Clone, branch from dev, make the bounded source change, and build a selected ordinary edition into a new directory outside the checkout:

```powershell
git clone https://github.com/Julesc013/more-infinite-research.git
cd more-infinite-research
git switch dev
git switch -c fix/my-bounded-change
python tools/package.py --source source --target f210 --output ../mir-local/more-infinite-research_5.0.21000.zip
```

`--target` selects an implemented edition and derives its numeric version from `source/info.json`; it is not native qualification. For a one-off same-name package without target adaptation, use a valid five-digit distribution version and a matching output filename:

```powershell
python tools/package.py --source source --version 5.0.21001 --output ../mir-local/more-infinite-research_5.0.21001.zip
```

`--version` and `--target` are intentionally mutually exclusive. To change a selected edition's local version or ordinary presentation metadata, edit the working-tree `source/info.json` while retaining the official name, then use `--target`; the target packager derives the selected edition's version, Factorio line and minimum Base dependency from that source codec and the tracked target record. Do not use `tools/release.py` for this: it freezes the canonical ten-edition release identity and rejects a private product version/name. The F006–F012 best-effort data-only path separately regenerates its finite metadata, so it is not a private-branding path.

A higher private version can complicate selecting a later official build. Keeping MIR's name preserves identity, not proof that your changed prototypes/effects are save-compatible. Preserve the original save and matching archives/settings before testing; switching back to an official ZIP is not an automatic undo. Factorio records applied migration filenames per save, so rebuilding a ZIP does not rerun an already applied migration. Do not rename migrations to force replay; see the [native migration rules](https://lua-api.factorio.com/latest/auxiliary/migrations.html).

Before sharing a proposed change upstream, inspect the plan, run the narrow affected controls and repository checks, and commit the bounded change. Create your own GitHub fork when ready to contribute, add its URL as a separate remote, push the feature branch there and open a PR targeting official dev. Keep personal version/branding edits out of an unrelated upstream fix. Official repository push permission is unnecessary for a local build or contribution. A local package, passing host control or successful load is not release, compatibility or native acceptance. Keep original saves and use a disposable profile for experiments.

For a companion or extension, prefer the documented draft MIR API/SDK surface and declare the official dependency; do not copy MIR merely to call its data or runtime interface. API maturity remains draft until its independent-consumer and native/client gates pass, so the companion must check the documented version/capability boundary and handle optional absence.

An advanced renamed fork is a separate product-design task, not a metadata-only build option. Before attempting it, audit its own absolute `__more-infinite-research__` imports, API/browser/settings interfaces, settings and generated technology identities, locale/shortcut/command names, `mod_changes` and active-mod references, native ownership/override/aggregate-contribution behavior, migration policy and every external consumer. Keep Base and upstream-mod recipe/prototype IDs intact; decide explicitly which fork-owned identities change and how effects interact when both products load. Factorio already gives each mod its own `storage`/legacy `global` Lua state, so do not apply a blanket storage rename. Likewise, preserve or deliberately replace only the fork's own migration history after a save-compatibility decision. A renamed fork needs its own exact package, load, API-consumer, save and coexistence evidence; it inherits none from the official package.

## Changelog ownership and formatting

Edit the root [CHANGELOG.md](../CHANGELOG.md) as the single authored release history. Keep each Markdown paragraph or bullet on one logical line and use editor soft wrapping; aim for short readable sentences rather than manually wrapping repository prose. Retain the selected MIR1–3 master releases once, all MIR4 and later source releases, and edition-specific historical scope. Reduced backport logs are not separate master release entries.

Run `python -B tools/changelog.py --write` after an edit. The small formatter writes the tracked [source/changelog.txt](../source/changelog.txt) projection with Factorio separators, indentation and132-character lines. Its only distribution-version placeholder belongs to the current release; the packager replaces it with the selected edition version. Check freshness with `python -B tools/changelog.py`; never hand-edit the projection. Commit both files together. The [reconciliation inventory](../spec/inventory/changelog-history.json) preserves the exact prior history fingerprints and recovery sources; it is outside player packages.

## Before creating an abstraction

Show the real repeated code or concrete safety boundary, why native Factorio behavior is insufficient, what new state it retains, and which tests protect its removal/replacement. Do not create an adapter for an imagined future engine or an API function without a consumer.

Code should be concise enough to follow, not minified. Prefer ordinary arrays/maps and direct field changes. Do not hide complexity in generated data. Explain any shared Generator growth together with the total declarations/adapters/UI/tooling footprint.

## Test selection

Follow [verification](../spec/verification.md). Run cheap affected checks first, native slices for changed gameplay, migrations/clients when state is affected, and the full relevant frozen-candidate campaign before release. A documentation typo is not a new native campaign. A new engine is not covered by an old native receipt.

The ATAN, K2, automatic-family and BobTech controls read their historical selectors, profile/qualification source and automatic-family logs from published commit `bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1`, checking each original captured SHA256. The named prerequisite-repair control additionally reads its published 4.7.3 source baseline at `8643cc91bc915e008556a5315dbb0a743247e7ab`, checking both recorded blob IDs. They do not require editable MIR4 source or historical files in the current tree. A shallow checkout needs `git fetch --no-tags --depth=1 origin bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1` and `git fetch --no-tags --depth=1 origin 8643cc91bc915e008556a5315dbb0a743247e7ab` before those controls; the hosted workflow performs both exact fetches. The readers have no network or current-file fallback. Current MIR5 settings/catalogue assertions continue to read current source.

The F210 K2 capture controls read their two original profile blobs from exact native-input commit `5c51ed46d1762b4fca7480f05a057482bbbedb0a` and verify the captured SHA256 values. Current profiles may rebind observer or candidate archives without changing that historical observation. A shallow checkout also needs `git fetch --no-tags --depth=1 origin 5c51ed46d1762b4fca7480f05a057482bbbedb0a`; the hosted plan/host jobs fetch this exact object before controls. The reader has no moving-HEAD, network or current-file fallback.

A test correction needs independent evidence. A resource refusal is not a pass, fail or timing sample. A path-only rename still needs package member equality and final-layout smoke, because import and package mistakes are real defects.

## Isolated client launches

Reuse the selected engine by its exact executable path. Keep each client's ordinary `config.ini`, `write-data`, logs and saves beneath that assignment's existing `build/tmp` output root; keep verified dependency archives in the engine-family direct `testmods` library. Each client needs a separate writable directory, not a second game installation or a `TestProfiles` directory inside Steam. The existing native harness generates these configurations and owns their restoration/custody.

`--config` selects a normal `config.ini`, whose `[path]` section supplies explicit `read-data` and `write-data` paths; it does not select an alternate `config-path.cfg` or disable Steamworks. Leave the installed `config-path.cfg`, Steam Cloud settings, normal profile and Steam depot untouched. The installed `use-system-read-write-data-directories` option controls default data paths, not Steam authentication. See the official [command-line options](https://wiki.factorio.com/Command_line_parameters) and [application-directory guide](https://wiki.factorio.com/Application_directory).

Factorio's [developer explanation for2.1](https://forums.factorio.com/viewtopic.php?t=131164) says the Steam build uses Steam Cloud player data while the non-Steam build uses local data. The retained exact2.1.23 client attempts in [progress](progress.md) independently observe failed Steam initialization with Steam closed and one Cloud-backed identity with Steam available. Path isolation therefore does not establish two distinct client identities. Keep the strict multiplayer oracles and require a supported exact-engine route before another full attempt; headless results do not substitute for graphical clients.

## Contribution completion

Return exact changed files/responsibilities, real commands/results, active regressions covered, any measured seconds/uncertainty, unresolved gaps and next action. No generic 'all tests passed' when native tests were unavailable. Stop after the assigned batch; new work gets a new bounded assignment.

Release and branch/control permissions remain explicit. Documentation adoption is not permission to publish or change repository security controls.

## Offline player asset freeze

The [release adapter](../tools/release.py) builds the normal edition set from one committed player tree and its tracked edition record. For release delivery, explicitly include the buildable best-effort early cohort from that same commit. Select a full commit and a new output directory outside the checkout:

```powershell
python tools/release.py --source source --revision <full-commit> --output ../mir5-freeze/<new-directory> --early-target-record targets/early-editions.json
python tools/release.py --source source --output ../mir5-freeze/<new-directory> --verify
```

The output contains the normal edition ZIPs and `SHA256SUMS.txt`, plus seven best-effort F006–F012 ZIPs and `SHA256SUMS-early.txt`, all bound by `MIR5ReleaseAssetInventoryV1.json`. The optional `early_cohort` explicitly records missing native qualification, delivery mode and its exact target-record blob; it does not expand or qualify the retained native matrix. F006–F008 require extraction before use. Omitting the early selector retains the normal-only freeze format for source reconstruction; it is not the complete intended release inventory when the early cohort is buildable.

The inventory binds the source commit/trees, edition records, complete package members, archive bytes and frozen controller identity: both Python tools, Python/zlib versions and compression policy. Verification rebuilds the recorded packages in temporary custody and compares exact bytes; an independent verifier's local controller provenance must be recorded separately. Existing freeze destinations and changed, absent, extra, cross-record or misidentified assets are refused. The early closure is checked before creating an output directory. Preserve failed output for inspection.

This command performs no signing, tagging or publication and grants no native-test acceptance. The final release still needs every applicable verdict in [verification](../spec/verification.md), administration and separate release-immutability checks, exact main/tag reconciliation and public download readback. Agent-managed publication is GitHub-only for all releases; the maintainer handles Mod Portal publication, credentials and readback. The maintainer separately authorizes unsigned MIR5 publication when the enrolled signing key is unavailable; retain accurate checksums and do not describe them as signatures. Accepted packages must also reach the primary checkout's `dist` with verified hashes. The inventory is developer custody; public assets remain individual player ZIPs and useful integrity files.

## GitHub publication after acceptance

This MIR5 procedure uses the maintainer's explicit publication authorization. It does not grant acceptance to an incomplete candidate or change the historical MIR4 release commands and seals. Keep the enrolled signing observation as history; an unsigned MIR5 release contains checksums without a claimed signature. Use the real `BLACKGLASS-WIN1\Jules` Windows context and verified `Julesc013` GitHub session for credential-dependent commands.

1. Close every applicable release verdict in [verification](../spec/verification.md), including complete retained scope, current positive fixtures, native/save/client results, the matched performance comparison, canonical layout and all normal package identities. Complete README, documentation and target changelogs. Have a fresh independent review check the frozen source, adverse observations and required evidence. Record the actual verdicts and limitations; a list of registered scenarios is insufficient.
2. Freeze one committed candidate with the offline adapter above. Retain its inventory and acceptance evidence in developer custody. Keep every selected ZIP and checksum file unchanged through publication. Retained editions require their applicable acceptance; optional historical artifacts retain explicit best-effort limits. Run development health before output batches. Re-run the existing `tools/commands/release/Test-MIRGitHubAdministration.ps1` and the separate read-only release-immutability probe immediately before publication; both must pass. Never enable immutable releases or change repository controls to make publication succeed.
3. Finish required PR/check/promotion work and read back `origin/main`. Require its entire tree to equal the qualified tree, or review and qualify any differences before continuing. If the promotion produces another commit with the identical tree, record both full commits and that equality; this does not rename an earlier native execution. Verify the frozen inventory and exact accepted package hashes again. Do not rebuild or replace accepted public assets during publication.
4. Reconcile the remote `v5.0.0` ref and existing releases before creating anything. An existing tag must resolve to the accepted main commit. An existing release must match that tag and the intended draft/published state. Preserve unexpected objects and resolve the discrepancy rather than deleting or force-updating them. After acceptance, create and push the canonical tag against the read-back main commit. An unsigned annotated tag is authorized when the enrolled key is unavailable.
5. Prepare concise release notes in a local UTF-8 file: summary first, then the largest changes and exact edition requirements. Title is exactly `MIR 5.0.0`; do not repeat it as a body heading. Create or reuse one draft and retain its numeric release ID. Use structured API fields or `gh release create ... --notes-file <file>`; do not interpolate a multiline body into a shell command. Reconcile a lost response by listing existing objects and reading that release ID before retrying any creation.
6. Derive the complete public set from `assets` plus any `early_cohort.assets` and their checksum files; stage exactly those individual ZIPs and sums in the draft. Keep canonical filenames. Label retained assets by their exact engine minimum; label each early asset explicitly `best effort; not natively qualified`, adding `extract to mods folder` where its recorded delivery requires it. State the fixed finite subset and omitted runtime/settings/UI/migrations in the release notes. Keep the developer inventory, bundles, upload instructions and receipts out of public assets. Reconcile existing asset IDs/names before a retry; do not overwrite a mismatched asset automatically. Download every staged asset and compare lengths and SHA256 hashes with the frozen inventory and sums.
7. Verify the tag/main identity, release title/body, complete inventory-derived public names/labels and mutable-release probes once more, then publish that same release ID. If the response is lost, read the release ID to determine whether it is already public; do not create a second release. Record its URL and publication state.
8. Download every inventory-selected public asset anonymously with no authorization header and verify exact bytes/hashes. Copy the identical ZIPs, sums, matching release notes and upload text into primary `dist`, with hash verification. Retain developer inventory and publication/download receipts separately. Synchronize the primary branch with its remote and dispose only of completed clean disposable work after readback. Verified GitHub publication completes agent-managed distribution; the maintainer handles Mod Portal for all releases.

## Determinism and visual context

Read [the architecture explainer](architecture.md) once, then only the relevant spec/diagram. For ordering, runtime, migration or package work, include [determinism](../spec/determinism.md) in the task packet. Do not supply all diagrams or old transcripts to every task.

The imported pack's original case catalogue remains a set of requirement examples rather than an execution receipt. Current host controls exercise implemented player behavior and tooling; exact native results live in the linked evidence chains and [progress](progress.md). Do not infer product acceptance from the old case statuses, rename an earlier execution, or copy a candidate's unexpected output into its oracle.

The `source_selection.path`/SHA256 objects in the Bob/Angel and Bob Core profiles describe historical derivation inputs in published commit `bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1`; they are not current runner paths. Both complete source-selection documents and BobTech's three qualification inputs match that Git object byte-for-byte. Current `mods`, archive hashes and engine/settings fields remain the execution inputs. Removing the historical MIR4 runner or observer files from the active tree never changes these captured source identities.

K2SO's `source_profile` in the comparison inventory and the MIR4 fixture-contract paths in the runtime-continuity inventory likewise refer to that published Git commit. The K2 profile's original SHA256 `DC6EE665BDE9D734CF325F1C91902914CE6D6EB79038C1F6A4D7A52425E2F788` matches the published blob exactly. These historical records do not reactivate the old runner, current `.mir` authority or compiled MIR4 observer.
