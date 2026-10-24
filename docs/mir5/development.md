---
title: "Development guide"
status: draft
applies_to: "MIR replacement development"
audience: developer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-10-24
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-development-guide
---

# Development guide

## Start with a bounded task

Read root agent instructions, the [specification index](../../spec/mir5/README.md), and the one or two relevant contracts. Inspect current `git status`, exact source and active jobs once. Preserve dirty/untracked work and unique receipts. Do not reset to a historical planning commit.

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

Maintain the [existing community request ledger](../../spec/programmes/community-requests.json) through `CONT-15`; preserve original IDs, MIR 4 crash/failure evidence, unresolved bugs and technology-tuning requests. Carry them into affected MIR 5 work and regression selection rather than closing them because the architecture changes. `SCI-UNLOCK-01` records the recurring approved science binding startup failures, the reported unsuccessful mod-removal attempts and missing reproduction evidence. It remains open until exact affected-package qualification supports closure. This intake does not claim a fix.

## Work in small vertical slices

Make a native family work end to end, then exercise a different native effect, a staged/native-owner integration and stateful caps/runtime. Keep partial packages off production saves. A successful tiny package is not a full-product migration or performance claim.

Use one implementer, one independent review responsibility and one test worker within the existing three-slot capacity. Workers must have nonoverlapping edits. Reuse running native campaigns; at most one heavy scenario per admitted machine. Exact archive libraries/settings are preserved and restored by existing qualified tools.

## Coordinate Black Glass and Aero through GitHub

Black Glass owns the current integration branch, the sole native-test lane and release coordination. The current branch and frozen test inputs are named in [progress](progress.md). Aero15X independently reviews pushed commits and may prepare corrections on separate branches and PRs. Use a bounded file responsibility in each task/PR, fetch remote changes before integration, and reconcile overlapping edits explicitly. Never reset another worker's changes, force-push a shared review branch or substitute a moving branch head for a test's full source commit.

Push each reviewable unit promptly. Commit bodies and PR descriptions record the concrete defect or outcome, changed behavior, independent expected result, actual commands and results, exact source/package identities where applicable, and remaining limitations. Finish required checks and merge completed units into `dev` while later qualification continues. Merge updated `dev` into an already published work branch when needed; preserve the commit identities that Aero reviews and native workers consume. Keep frozen-input custody branches reachable until their jobs and evidence readback finish.

After accepted MIR5.0.0 publication and verified local delivery, continue with5.0.1 bug fixes, measured performance improvements and further stress qualification. Use actual review findings and observed failures to select that work. This follow-up authorization does not waive any5.0.0 acceptance gate or permit an untested release.

## Before creating an abstraction

Show the real repeated code or concrete safety boundary, why native Factorio behavior is insufficient, what new state it retains, and which tests protect its removal/replacement. Do not create an adapter for an imagined future engine or an API function without a consumer.

Code should be concise enough to follow, not minified. Prefer ordinary arrays/maps and direct field changes. Do not hide complexity in generated data. Explain any shared Generator growth together with the total declarations/adapters/UI/tooling footprint.

## Test selection

Follow [verification](../../spec/mir5/verification.md). Run cheap affected checks first, native slices for changed gameplay, migrations/clients when state is affected, and the full relevant frozen-candidate campaign before release. A documentation typo is not a new native campaign. A new engine is not covered by an old native receipt.

The ATAN, K2, automatic-family and BobTech controls read their historical selectors, profile/qualification source and automatic-family logs from published commit `bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1`, checking each original captured SHA256. They do not require editable MIR4 source or historical files in the current tree. A shallow checkout needs `git fetch --no-tags --depth=1 origin bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1` before those controls; the hosted workflow performs that exact fetch. The reader has no network or current-file fallback. Current MIR5 settings/catalogue assertions continue to read current source.

A test correction needs independent evidence. A resource refusal is not a pass, fail or timing sample. A path-only rename still needs package member equality and final-layout smoke, because import and package mistakes are real defects.

## Contribution completion

Return exact changed files/responsibilities, real commands/results, active regressions covered, any measured seconds/uncertainty, unresolved gaps and next action. No generic 'all tests passed' when native tests were unavailable. Stop after the assigned batch; new work gets a new bounded assignment.

Release and branch/control permissions remain explicit. Documentation adoption is not permission to publish or change repository security controls.

## Offline player asset freeze

The [release adapter](../../tools/mir5/release.py) builds the nine editions from one committed player tree and its tracked edition record. Select a full commit and a new output directory outside the checkout:

```powershell
python tools/mir5/release.py --source source/mir5 --revision <full-commit> --output ../mir5-freeze/<new-directory>
python tools/mir5/release.py --source source/mir5 --output ../mir5-freeze/<new-directory> --verify
```

The output contains nine canonical player ZIPs, `SHA256SUMS.txt` and `MIR5ReleaseAssetInventoryV1.json`. The inventory binds the source commit/trees, edition blob, complete package members, archive bytes and separate local controller identity: both Python tools, Python/zlib versions and compression policy. Verification requires that same controller and rebuilds packages in temporary custody to compare exact bytes. It rejects existing freeze destinations and changed, absent, extra or misidentified assets. Preserve failed output for inspection.

This command performs no signing, tagging or publication and grants no native-test acceptance. The final release still needs every applicable verdict in [verification](../../spec/mir5/verification.md), administration and separate release-immutability checks, exact main/tag reconciliation and public download readback. The maintainer authorizes unsigned GitHub-only MIR5 publication when the enrolled signing key is unavailable; retain accurate checksums and do not describe them as signatures. Mod Portal publication is outside this goal. Accepted packages must also reach the primary checkout's `dist` with verified hashes. The inventory is developer custody; public assets remain individual player ZIPs and useful integrity files.

## GitHub publication after acceptance

This MIR5 procedure uses the maintainer's explicit publication authorization. It does not grant acceptance to an incomplete candidate or change the historical MIR4 release commands and seals. Keep the enrolled signing observation as history; an unsigned MIR5 release contains checksums without a claimed signature. Use the real `BLACKGLASS-WIN1\Jules` Windows context and verified `Julesc013` GitHub session for credential-dependent commands.

1. Close every applicable release verdict in [verification](../../spec/mir5/verification.md), including complete retained scope, current positive fixtures, native/save/client results, the matched performance comparison, canonical layout and all nine package identities. Complete README, documentation and target changelogs. Have a fresh independent review check the frozen source, adverse observations and required evidence. Record the actual verdicts and limitations; a list of registered scenarios is insufficient.
2. Freeze one committed candidate with the offline adapter above. Retain its inventory and acceptance evidence in developer custody. Keep the nine ZIPs and `SHA256SUMS.txt` unchanged through publication. Run development health before output batches. Re-run the existing `tools/commands/release/Test-MIRGitHubAdministration.ps1` and the separate read-only release-immutability probe immediately before publication; both must pass. Never enable immutable releases or change repository controls to make publication succeed.
3. Finish required PR/check/promotion work and read back `origin/main`. Require its entire tree to equal the qualified tree, or review and qualify any differences before continuing. If the promotion produces another commit with the identical tree, record both full commits and that equality; this does not rename an earlier native execution. Verify the frozen inventory and exact accepted package hashes again. Do not rebuild or replace accepted public assets during publication.
4. Reconcile the remote `v5.0.0` ref and existing releases before creating anything. An existing tag must resolve to the accepted main commit. An existing release must match that tag and the intended draft/published state. Preserve unexpected objects and resolve the discrepancy rather than deleting or force-updating them. After acceptance, create and push the canonical tag against the read-back main commit. An unsigned annotated tag is authorized when the enrolled key is unavailable.
5. Prepare concise release notes in a local UTF-8 file: summary first, then the largest changes and exact edition requirements. Title is exactly `MIR 5.0.0`; do not repeat it as a body heading. Create or reuse one draft and retain its numeric release ID. Use structured API fields or `gh release create ... --notes-file <file>`; do not interpolate a multiline body into a shell command. Reconcile a lost response by listing existing objects and reading that release ID before retrying any creation.
6. Stage exactly the nine individual player ZIPs and `SHA256SUMS.txt` in that draft. Apply descriptive asset labels using each inventory row's exact engine minimum while retaining canonical filenames. Keep the inventory, bundles, upload instructions and developer receipts out of public assets. Reconcile existing asset IDs/names before an upload retry; do not overwrite a mismatched asset automatically. Read back the complete draft asset inventory, download every staged asset and compare byte lengths and SHA256 hashes with the frozen inventory and sums.
7. Verify the tag/main identity, release title/body, ten public asset names/labels and the mutable-release probes once more, then publish that same release ID. If the response is lost, read the release ID to determine whether it is already public; do not create a second release. Record its URL and publication state.
8. Download all ten public assets through anonymous requests with no authorization header and verify their exact bytes/hashes. Copy the identical accepted ZIPs, checksum file, matching release notes and upload text into the primary checkout's `dist`, with hash verification. Retain the developer inventory and publication/download receipts separately in discoverable local custody. Synchronize the active primary branch with its remote and dispose only of completed clean disposable work after remote readback. GitHub-only publication completes the distribution scope of this goal; no Mod Portal operation is required.

## Determinism and visual context

Read [the architecture explainer](architecture.md) once, then only the relevant spec/diagram. For ordering, runtime, migration or package work, include [determinism](../../spec/mir5/determinism.md) in the task packet. Do not supply all diagrams or old transcripts to every task.

The imported pack's original case catalogue remains a set of requirement examples rather than an execution receipt. Current host controls exercise implemented player behavior and tooling; exact native results live in the linked evidence chains and [progress](progress.md). Do not infer product acceptance from the old case statuses, rename an earlier execution, or copy a candidate's unexpected output into its oracle.

The `source_selection.path`/SHA256 objects in the Bob/Angel and Bob Core profiles describe historical derivation inputs in published commit `bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1`; they are not current runner paths. Both complete source-selection documents and BobTech's three qualification inputs match that Git object byte-for-byte. Current `mods`, archive hashes and engine/settings fields remain the execution inputs. Removing the historical MIR4 runner or observer files from the active tree never changes these captured source identities.

K2SO's `source_profile` in the comparison inventory and the MIR4 fixture-contract paths in the runtime-continuity inventory likewise refer to that published Git commit. The K2 profile's original SHA256 `DC6EE665BDE9D734CF325F1C91902914CE6D6EB79038C1F6A4D7A52425E2F788` matches the published blob exactly. These historical records do not reactivate the old runner, current `.mir` authority or compiled MIR4 observer.
