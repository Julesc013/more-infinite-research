---
title: "Development guide"
status: current
applies_to: "MIR development"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-development-guide
---

# Development guide

## Development line and maintenance branches

`dev` is dedicated to MIR5 in the canonical layout: `source/`, `spec/`, `docs/`, `tests/`, `tools/`, `targets/` and `sdk/`. Implement the final product directly in those roots. Tests use version-neutral roles such as `published` and `successor`; fixture IDs, product versions and immutable historical references keep their actual identities.

MIR4 maintenance starts from the exact published tag that needs a fix, currently `v4.7.3`, on a bounded task branch. Check and tag that release from its maintenance branch. Keep its implementation in the preserved Git refs rather than restoring a parallel MIR4 source or documentation tree on `dev`. Any shared correction needed by MIR5 receives its own reviewed integration.

Main promotion and the canonical `v5.0.0` tag follow the remaining acceptance and publication gates. Current documentation and canonical paths do not imply release qualification. The maintainer handles Mod Portal publication; agent-managed releases remain GitHub-only.

Use neutral names for new output batches: `build/host-gate` for hosted control output, `build/qualification` for new test evidence and packets, and `build/packages` for new candidate package custody. Accepted delivery remains in `dist`. Existing `build/mir5` paths are retained where exact receipts or active frozen jobs consume them; preserve those bytes and locators instead of moving recorded evidence or retargeting a live job.

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

The additional F001–F012 request is a separate best-effort GitHub delivery obligation under the [target contract](../spec/targets.md#additional-historical-editions), with the nine stable editions retaining release priority. Buildable extra editions receive explicit feature/installation/qualification limits; unavailable inputs do not become invented support or implicit release blockers. The separate [early target record](../targets/early-editions.json) selects only the actual finite data adapter. F018/0.18.47 remains selected by the ordinary target record but is permanently GitHub-only experimental/best effort: its target-specific scope is metadata/package information and an actual0.18 native load/crash smoke, not a stable save, modpack, science, client or performance campaign.

Follow the maintainer's [edition scheduling order and product priorities](../spec/targets.md#primary-target-and-earlier-editions) when selecting MIR5 work. Preserve the nine stable editions through the same capability-based source and version encoding, with common feature, setting and presentation semantics wherever native capabilities permit. F018 uses the same shared implementation and codec but remains explicitly experimental/best effort. Scheduling priority does not waive final current-package and affected native checks for every stable delivered target subset. Reuse exact unchanged evidence under its original identity and state remaining gaps by edition; an unqualified stable edition remains an open release obligation.

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

`--version` and `--target` are intentionally mutually exclusive. `--version` retains the source target's CCC edition codec while changing `info.json`, the generated changelog and the runtime API product version together for a same-edition local package; selecting a different CCC requires `--target` adaptation. To change a selected edition's local version or ordinary presentation metadata, edit the working-tree `source/info.json` while retaining the official name, then use `--target`; the target packager derives the selected edition's version, Factorio line and minimum Base dependency from that source codec and the tracked target record. Do not use `tools/release.py` for this: it freezes the canonical ten-edition release identity and rejects a private product version/name. The F006–F012 best-effort data-only path separately regenerates its finite metadata, so it is not a private-branding path.

A higher private version can complicate selecting a later official build. Keeping MIR's name preserves identity, not proof that your changed prototypes/effects are save-compatible. Preserve the original save and matching archives/settings before testing; switching back to an official ZIP is not an automatic undo. Factorio records applied migration filenames per save, so rebuilding a ZIP does not rerun an already applied migration. Do not rename migrations to force replay; see the [native migration rules](https://lua-api.factorio.com/latest/auxiliary/migrations.html).

Maintain the shared cumulative migration set under the [migration contract](../spec/migrations.md#required-origin-coverage). The modern qualification matrix starts at MIR 1.0.0, whose published tag targets Factorio 2.0, and covers every applicable published origin rather than only MIR 4.7.3 or selected changelog entries. Recover actual historical filenames, mappings and necessary schema readers without restoring retired subsystems. A new filename is required for new exactly-once work on saves that already applied an older migration; idempotent current reconciliation is a separate responsibility. For every release, preserve origin saves, qualify direct upgrades into the candidate and record engine/edition limits explicitly.

Before sharing a proposed change upstream, inspect the plan, run the narrow affected controls and repository checks, and commit the bounded change. Create your own GitHub fork when ready to contribute, add its URL as a separate remote, push the feature branch there and open a PR targeting official dev. Keep personal version/branding edits out of an unrelated upstream fix. Official repository push permission is unnecessary for a local build or contribution. A local package, passing host control or successful load is not release, compatibility or native acceptance. Keep original saves and use a disposable profile for experiments.

For a companion or extension, prefer the documented draft MIR API/SDK surface and declare the official dependency; do not copy MIR merely to call its data or runtime interface. API maturity remains draft until its independent-consumer and native/client gates pass, so the companion must check the documented version/capability boundary and handle optional absence.

An advanced renamed fork is a separate product-design task, not a metadata-only build option. Before attempting it, audit its own absolute `__more-infinite-research__` imports, API/browser/settings interfaces, settings and generated technology identities, locale/shortcut/command names, `mod_changes` and active-mod references, native ownership/override/aggregate-contribution behavior, migration policy and every external consumer. Keep Base and upstream-mod recipe/prototype IDs intact; decide explicitly which fork-owned identities change and how effects interact when both products load. Factorio already gives each mod its own `storage`/legacy `global` Lua state, so do not apply a blanket storage rename. Likewise, preserve or deliberately replace only the fork's own migration history after a save-compatibility decision. A renamed fork needs its own exact package, load, API-consumer, save and coexistence evidence; it inherits none from the official package.

## Changelog ownership and formatting

Edit the root [CHANGELOG.md](../CHANGELOG.md) as the single authored release history. Keep each Markdown paragraph or bullet on one logical line and use editor soft wrapping; aim for short readable sentences rather than manually wrapping repository prose. Retain the selected MIR1–3 master releases once, all MIR4 and later source releases, and edition-specific historical scope. Reduced backport logs are not separate master release entries.

Run `python -B tools/changelog.py --write` after an edit. The small formatter writes the tracked [source/changelog.txt](../source/changelog.txt) projection with Factorio separators, indentation and132-character lines. Every release header retains its source version across editions. A private same-edition build changes only the current header to its selected source version; historical entries remain unchanged. Check freshness with `python -B tools/changelog.py`; never hand-edit the projection. Commit both files together. The [reconciliation inventory](../spec/inventory/changelog-history.json) preserves the exact prior history fingerprints and recovery sources; it is outside player packages.

## Before creating an abstraction

Show the real repeated code or concrete safety boundary, why native Factorio behavior is insufficient, what new state it retains, and which tests protect its removal/replacement. Do not create an adapter for an imagined future engine or an API function without a consumer.

Code should be concise enough to follow, not minified. Prefer ordinary arrays/maps and direct field changes. Do not hide complexity in generated data. Explain any shared Generator growth together with the total declarations/adapters/UI/tooling footprint.

## Test selection

Follow [verification](../spec/verification.md). Run cheap affected checks first, native slices for changed gameplay, migrations/clients when state is affected, and the full relevant frozen-candidate campaign before release. A documentation typo is not a new native campaign. A new engine is not covered by an old native receipt.

The ATAN, K2, automatic-family and BobTech controls bind their recorded historical selectors, qualification source and automatic-family logs; the named prerequisite-repair control binds its published 4.7.3 source; F210 capture and prepared-fixture controls bind their recorded raw sources and runtime members. In a shallow checkout, run the exact [`Fetch exact published historical sources`](../.github/workflows/validate.yml) block used by CI before those controls, including the relevant original published/captured source for ATAN, K2, automatic-family, BobTech, prerequisite repair and F210 capture or fixture provenance. The readers have no network, moving-HEAD or current-file fallback. Historical package-helper receipts remain immutable; when the helper later changes, current code must instead prove exact selected-member and archive-output equivalence. Current MIR5 settings/catalogue assertions continue to read current source.

A test correction needs independent evidence. A resource refusal is not a pass, fail or timing sample. A path-only rename still needs package member equality and final-layout smoke, because import and package mistakes are real defects.

For a native fixture, the caller must provision the selected, hash-pinned ZIP in the direct library before invoking `Invoke-NativeFixture.ps1`; that runner verifies fixtures but never packages or stages them. Build each `FixtureSources` directory as a checkout-local temporary projection containing exactly the package record's members, then verify it against the selected container before admission. For a committed input, package with `--revision <full-commit>` and project the selected raw Git blobs from that same commit; do not copy a Windows working tree whose `autocrlf` policy may have changed the selected Lua or JSON bytes. A deliberately local, unpinned experiment may use its working-tree bytes, but it is not interchangeable with a strict profile archive pin. Do not pass a canonical fixture directory wholesale when it includes alternate metadata such as `info-f200.json` that is intentionally absent from the selected F210 ZIP.

```powershell
$revision = git rev-parse HEAD
$packageRecord = python .\tools\package.py --source $canonicalFixtureSource --revision $revision --output $selectedArchive | ConvertFrom-Json
$projection = Join-Path $OutputRoot 'fixture-source'
if (Test-Path -LiteralPath $projection) { throw "Preserve existing fixture projection: $projection" }
$sourceRoot = 'tests/fixtures/<selected-fixture>' # repository-relative; not an absolute working-tree path
@'
from pathlib import Path
import subprocess, sys
revision, source_root, projection, *members = sys.argv[1:]
for member in members:
    raw = subprocess.check_output(["git", "show", f"{revision}:{source_root}/{member}"])
    destination = Path(projection, member)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(raw)
'@ | python - $revision $sourceRoot $projection $packageRecord.members.path
.\tools\Invoke-NativeFixture.ps1 -ArchiveLibrary $library -FixtureSources $projection <other exact arguments>
```

The library archive must already match the profile's selected archive SHA256; a same-name container with different bytes is refused. The projection is caller-owned temporary input, not a ZIP extraction, dependency copy or a substitute for the profile's engine/archive admission. Do not pipe `git show` through text cmdlets when creating that projection: its selected blobs are binary input, even where an individual member happens to be text.

## Recover an exact published catalogue

`tools/recover_modern_catalogue.py recover` accepts `--published-version` for an exact same-target MIR4.7 numeric distribution, such as `4.7.21003` or `4.7.20003`. Omitting it retains the original `4.7.21000`/`4.7.20000` recovery contract. Every supplied published arm, including optional K2SO, must match that version; engine, archive, capture-hash and paired-input checks still apply. MIR5 is never admitted as the published oracle.

For the outstanding default F2104.7.3 row-set check, the native owner can use `tests/profiles/base-f210-2123.json` and `tests/profiles/space-age-f210-2123.json`. Both select only their exact official2.1.23 closure and Defaults, omitting MIR and every gameplay fixture. Capture a no-MIR and exact B6 arm for each through `tools/Invoke-PrototypeCapture.ps1`; the published arms pass `-MIRArchive` and `-ExpectedMIRArchiveSha256` together. Bind the real engine/library/output/resource inputs under the existing exclusive native assignment. A seeded or accelerated upgrade fixture is not an unmodified default reference.

After those four actual captures, the following recovery command uses their caller-supplied roots and a new output path. It does not run Factorio or turn host/synthetic captures into native evidence:

```powershell
$recoveryArguments = @(
  '--target', 'f210', '--published-version', '4.7.21003',
  '--base-no-mir', $baseNoMirCapture, '--base-published', $baseB6Capture,
  '--space-age-no-mir', $spaceAgeNoMirCapture, '--space-age-published', $spaceAgeB6Capture,
  '--output', $newCataloguePath
)
python -B tools/recover_modern_catalogue.py recover @recoveryArguments
```

Preserve `spec/inventory/modern-f210-470.json` and existing receipts as the original fixed4.7.21000 inputs. Compare the newly recovered complete B6 public/native-owner rows with the finite upgrade fixture plan before claiming complete B6 coverage. Resolve omissions or deliberate differences independently; raw catalogue recovery alone does not qualify MIR5 effects, saves, clients or performance.

## Isolated client launches

Reuse the selected engine by its exact executable path. Keep each client's ordinary `config.ini`, `write-data`, logs and saves beneath that assignment's existing `build/tmp` output root; keep verified dependency archives in the engine-family direct `testmods` library. Each client needs a separate writable directory, not a second game installation or a `TestProfiles` directory inside Steam. The existing native harness generates these configurations and owns their restoration/custody.

`--config` selects a normal `config.ini`, whose `[path]` section supplies explicit `read-data` and `write-data` paths; it does not select an alternate `config-path.cfg` or disable Steamworks. Leave the installed `config-path.cfg`, Steam Cloud settings, normal profile and Steam depot untouched. The installed `use-system-read-write-data-directories` option controls default data paths, not Steam authentication. See the official [command-line options](https://wiki.factorio.com/Command_line_parameters) and [application-directory guide](https://wiki.factorio.com/Application_directory).

Factorio's [developer explanation for2.1](https://forums.factorio.com/viewtopic.php?t=131164) says the Steam build uses Steam Cloud player data while the non-Steam build uses local data. The retained exact2.1.23 client attempts in [progress](progress.md) independently observe failed Steam initialization with Steam closed and one Cloud-backed identity with Steam available. Path isolation therefore does not establish two distinct client identities. Keep the strict multiplayer oracles and require a supported exact-engine route before another full attempt; headless results do not substitute for graphical clients.

## Contribution completion

Return exact changed files/responsibilities, real commands/results, active regressions covered, any measured seconds/uncertainty, unresolved gaps and next action. No generic 'all tests passed' when native tests were unavailable. Stop after the assigned batch; new work gets a new bounded assignment.

Release and branch/control permissions remain explicit. Documentation adoption is not permission to publish or change repository security controls.

## Offline player asset freeze

Keep the existing extended-version build and qualification workflow. After acceptance, follow [final Portal copies](../spec/targets.md#final-portal-copies) to export selected finished packages for the maintainer, preserving the GitHub originals. This final output operation does not introduce a source/runtime codec or another build configuration.

The [release adapter](../tools/release.py) builds ten target packages from one committed player tree and its tracked edition record: nine stable editions plus the GitHub-only experimental F018 package. For release delivery, explicitly include the buildable best-effort early cohort from that same commit. Select a full commit and a new output directory outside the checkout:

```powershell
python tools/release.py --source source --revision <full-commit> --output ../mir5-freeze/<new-directory> --early-target-record targets/early-editions.json
python tools/release.py --source source --output ../mir5-freeze/<new-directory> --verify
```

The output contains the nine stable ZIPs and the GitHub-only experimental F018 ZIP in `SHA256SUMS.txt`, plus seven best-effort F006–F012 ZIPs and `SHA256SUMS-early.txt`, all bound by `MIR5ReleaseAssetInventoryV1.json`. F018 remains a separately labelled experimental asset with only its metadata/package and native load/crash-smoke scope; it does not expand the stable native matrix. The optional `early_cohort` explicitly records missing native qualification, delivery mode and its exact target-record blob; it does not expand or qualify the retained native matrix. F006–F008 require extraction before use. Omitting the early selector retains the ten-target freeze format for source reconstruction; it is not the complete intended release inventory when the early cohort is buildable.

The inventory binds the source commit/trees, edition records, complete package members, archive bytes and frozen controller identity: both Python tools, Python/zlib versions and compression policy. Verification rebuilds the recorded packages in temporary custody and compares exact bytes; an independent verifier's local controller provenance must be recorded separately. Existing freeze destinations and changed, absent, extra, cross-record or misidentified assets are refused. The early closure is checked before creating an output directory. Preserve failed output for inspection.

This command performs no signing, tagging or publication and grants no native-test acceptance. The final release still needs every applicable verdict in [verification](../spec/verification.md), administration and separate release-immutability checks, exact main/tag reconciliation and public download readback. Agent-managed publication is GitHub-only for all releases; the maintainer handles Mod Portal publication, credentials and readback. The maintainer separately authorizes unsigned MIR5 publication when the enrolled signing key is unavailable; retain accurate checksums and do not describe them as signatures. Accepted packages must also reach the primary checkout's `dist` with verified hashes. The inventory is developer custody; public assets remain individual player ZIPs and useful integrity files.

## GitHub publication after acceptance

This MIR5 procedure uses the maintainer's explicit publication authorization. It does not grant acceptance to an incomplete candidate or change the historical MIR4 release commands and seals. Keep the enrolled signing observation as history; an unsigned MIR5 release contains checksums without a claimed signature. Use the real `BLACKGLASS-WIN1\Jules` Windows context and verified `Julesc013` GitHub session for credential-dependent commands.

1. Close every applicable release verdict in [verification](../spec/verification.md), including complete retained scope, current positive fixtures, native/save/client results, the matched performance comparison, canonical layout and all nine stable package identities. Complete README, documentation and target changelogs. Have a fresh independent review check the frozen source, adverse observations and required evidence. Record the actual verdicts and limitations; a list of registered scenarios is insufficient.
2. Freeze one committed candidate with the offline adapter above. Retain its inventory and acceptance evidence in developer custody. Keep every selected ZIP and checksum file unchanged through publication. The nine stable editions require their applicable acceptance; F018 and optional historical artifacts retain their explicit best-effort limits. Run development health before output batches. Re-run the existing `tools/commands/release/Test-MIRGitHubAdministration.ps1` and the separate read-only release-immutability probe immediately before publication; both must pass. Never enable immutable releases or change repository controls to make publication succeed.
3. Finish required PR/check/promotion work and read back `origin/main`. Require its entire tree to equal the qualified tree, or review and qualify any differences before continuing. If the promotion produces another commit with the identical tree, record both full commits and that equality; this does not rename an earlier native execution. Verify the frozen inventory and exact accepted package hashes again. Do not rebuild or replace accepted public assets during publication.
4. Reconcile the remote `v5.0.0` ref and existing releases before creating anything. An existing tag must resolve to the accepted main commit. An existing release must match that tag and the intended draft/published state. Preserve unexpected objects and resolve the discrepancy rather than deleting or force-updating them. After acceptance, create and push the canonical tag against the read-back main commit. An unsigned annotated tag is authorized when the enrolled key is unavailable.
5. Prepare concise release notes in a local UTF-8 file: summary first, then the largest changes and exact edition requirements. Title is exactly `MIR 5.0.0`; do not repeat it as a body heading. Create or reuse one draft and retain its numeric release ID. Use structured API fields or `gh release create ... --notes-file <file>`; do not interpolate a multiline body into a shell command. Reconcile a lost response by listing existing objects and reading that release ID before retrying any creation.
6. Derive the complete public set from `assets` plus any `early_cohort.assets` and their checksum files; stage exactly those individual ZIPs and sums in the draft. Keep canonical filenames. Label stable assets by their exact engine minimum; label F018 explicitly `experimental best effort; GitHub-only; native load/crash smoke scope`, and label each early asset explicitly `best effort; not natively qualified`, adding `extract to mods folder` where its recorded delivery requires it. State the fixed finite subset and omitted runtime/settings/UI/migrations in the release notes. Keep the developer inventory, bundles, upload instructions and receipts out of public assets. Reconcile existing asset IDs/names before a retry; do not overwrite a mismatched asset automatically. Download every staged asset and compare lengths and SHA256 hashes with the frozen inventory and sums.
7. Verify the tag/main identity, release title/body, complete inventory-derived public names/labels and mutable-release probes once more, then publish that same release ID. If the response is lost, read the release ID to determine whether it is already public; do not create a second release. Record its URL and publication state.
8. Download every inventory-selected public asset anonymously with no authorization header and verify exact bytes/hashes. Copy the identical ZIPs, sums, matching release notes and upload text into primary `dist`, with hash verification. Retain developer inventory and publication/download receipts separately. Synchronize the primary branch with its remote and dispose only of completed clean disposable work after readback. Verified GitHub publication completes agent-managed distribution; the maintainer handles final Portal copies for qualified stable outputs.

## Determinism and visual context

Read [the architecture explainer](architecture.md) once, then only the relevant spec/diagram. For ordering, runtime, migration or package work, include [determinism](../spec/determinism.md) in the task packet. Do not supply all diagrams or old transcripts to every task.

The imported pack's original case catalogue remains a set of requirement examples rather than an execution receipt. Current host controls exercise implemented player behavior and tooling; exact native results live in the linked evidence chains and [progress](progress.md). Do not infer product acceptance from the old case statuses, rename an earlier execution, or copy a candidate's unexpected output into its oracle.

The `source_selection.path`/SHA256 objects in the Bob/Angel and Bob Core profiles describe historical derivation inputs in published commit `bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1`; they are not current runner paths. Both complete source-selection documents and BobTech's three qualification inputs match that Git object byte-for-byte. Current `mods`, archive hashes and engine/settings fields remain the execution inputs. Removing the historical MIR4 runner or observer files from the active tree never changes these captured source identities.

K2SO's `source_profile` in the comparison inventory and the MIR4 fixture-contract paths in the runtime-continuity inventory likewise refer to that published Git commit. The K2 profile's original SHA256 `DC6EE665BDE9D734CF325F1C91902914CE6D6EB79038C1F6A4D7A52425E2F788` matches the published blob exactly. These historical records do not reactivate the old runner, current `.mir` authority or compiled MIR4 observer.
