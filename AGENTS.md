# AGENTS.md

## Project

More Infinite Research 4 is a proof-governed Factorio research product line. MIR 4.0.0 combines stable F210/F200 player targets, separately distributed developer previews, and executable package-excluded shadow architecture.

## Standing dev workflow authorization

- Creating implementation branches, pushing them to this repository, opening and merging PRs into `dev`, synchronizing the primary checkout with `origin/dev`, and removing completed disposable work branches are standing maintainer-authorized actions. Do not ask for confirmation for this routine dev workflow.
- Complete required automated checks and obey enforced branch rules without treating them as a requirement for another maintainer approval. Changes to `main` and release publication retain their separate policy requirements.

## Release identity and publication

- The numeric distribution codec is `100 * integer(CCC) + SOURCE_PATCH`, padded to five digits. The final two digits are never an RC counter, build number or packaging retry: source 4.2.0 uses CCC00 and source 4.2.1 uses CCC01. Validate the ZIP root, info.json, changelog, manifest, filename, tags and download copy together.
- Keep GitHub releases mutable. Do not enable repository or organization release immutability, restore removed rulesets, or infer permission to change external controls. Run the existing GitHub administration preflight and require the separate release-immutability probe to pass before publication. Repository governance, exact-source review, checksums and readback enforce the release contract.
- `v4.2.0-stable` is a one-time maintainer-authorized tag exception for source `6d19c874ea7d026d297865b96aa1b2b0916e9e61`, because GitHub permanently reserved the former immutable `v4.2.0` name. It changes no numeric version. Future final source tags use canonical `vMAJOR.MINOR.PATCH`; never infer another suffix exception.
- Freeze the exact committed source and accepted assets before tagging. Stage the complete asset inventory in one draft, reconcile lost responses by release ID, verify names and hashes, publish, then verify anonymous downloads. Preserve historical receipts and reconcile existing remote objects before replacing anything.

## MIR Development housekeeping

- Keep Git/GitHub execution available. Development health belongs in bounded observations, checkpoint requirements and the existing guarded cleanup commands; do not use housekeeping as a reason to deny commits, pushes, PRs or corrective Git actions.
- Before a batch that creates engine stages, package copies, logs or linked worktrees, run `tools/commands/workspace/Test-MIRDevelopmentHealth.ps1`. Resolve observed disk pressure through an eligible storage audit/cleanup or a smaller bounded batch before creating more output. Treat incomplete sizes as lower bounds and reuse exact trusted or matching in-progress evidence instead of producing duplicate runs.
- Commit and push each completed, reviewable unit with its validation and remaining limitations. Finish its required checks and PR merge into `dev` while later work continues; do not accumulate all completed changes until the end of MIR 4.2.
- Respond to the development Stop checkpoint with a concrete commit/push, guarded cleanup, or explicit preservation disposition. Preserve dirty worktrees, unique commits, active evidence and delivered packages. Remove completed clean disposable branches/worktrees after remote readback, and retain unique material at a discoverable primary-checkout location. Older or partially scanned material requires review; age alone is never deletion authority.
- Test mod profiles contain small selection definitions only. Keep each required exact archive once in its engine-family library and launch normal serial tests directly against that library. Switch only the active mod-list and settings under exclusive ownership, preserve and recover the previous controls, and keep run output separate. Do not create dependency copies, hard links, extracted mods or replacement populated profile directories. Retire old profile archive entries only after verified master membership and migration checks; retain unique fixtures and saves. This direct-library rule supersedes the earlier hard-link staging requirement.
- Never create a hard link with either endpoint outside the executing Git checkout. External `testmods` paths are disposable machine-local input locators, not repository dependencies or reproducibility guarantees. Supply the selected archive library explicitly; retain portable profile definitions and unique reproducers in the checkout. Missing archives must be reported, never recovered by recreating retired profiles.
- Select changed behavior and reported defects through the existing verification plan, source checks and captured prototypes. Reuse native evidence only for its exact trusted inputs. Do not rerun unrelated historical mod profiles. Required current-package, save, production and multiplayer evidence still needs its affected native scenario; source checks do not establish those results.

## Source layout: maintainer-directed cutover

The maintainer has selected `source/` as the single canonical editable product-source root and authorized replacement of the era-based layout. This supersedes earlier project instructions to preserve `src/`, `src/mod/`, or parallel modern/legacy source families. It does not claim that the physical cutover is already complete.

- Adopt the existing root-contraction checkpoint and active source-layout work. Preserve the maintainer's deletions/moves and unique or dirty worker material; never discard them merely to synchronize with remote.
- Decompose by semantic responsibility and actual capability. Share research, ownership, progression, configuration, and presentation implementations; select narrowly scoped platform adapters by their real contracts. Do not rename the old split to `source/mod/`, `source/families/modern`, `source/families/legacy`, or equivalent whole-version copies.
- Extend the existing package-source mapping and materializer to compose those components. Target records select capabilities and adapters; they are not alternate editable mod trees. Generated self-contained packages may contain the same shared bytes without creating duplicate source authorities.
- Update active path/module authorities, generators, tests, command imports, editor/CI configuration, and documentation links with the cutover. Preserve published objects and validate historical references against their pinned source. Old path assertions are migration work, not a veto or a reason to restore obsolete root copies.
- Preserve package import contracts, technology/settings identities, and published migration identities unless a separately reviewed semantic change requires a migration. Keep authored README/Portal prose intact apart from affected source-map facts and links.
- Completion requires removal of superseded current source roots and parallel implementations, dependency-closure and collision checks, actual materialized-package parity or explicitly reviewed semantic differences, and verified adoption of the preserved local cleanup. A rename-only PR or this instruction change is not completion of the repository overhaul.

## Local Factorio engine authority

- Use `C:\Program Files\Steam\steamapps\common\Factorio` only for the current Factorio 2.1 engine.
- Use `D:\Programs\Factorio\<version>` for Factorio 2.0 and every older engine; Factorio 2.0 is `D:\Programs\Factorio\2.0\bin\x64\factorio.exe`.
- Never download, replace, retarget, or mutate Steam depots for historical engines without explicit maintainer authority.

## Required reading by task

- Documentation: Markdown front matter, generated `.mir/docs.yml`, and `docs/maintainer/documentation-governance.md`.
- Architecture or repository roots: `.mir/modules.yml`, `.mir/control/paths.yml`, and `docs/architecture/module-boundaries.md`.
- Compatibility: `.mir/compatibility.yml`, `.mir/streams.yml`, and `docs/compatibility/claim-levels.md`.
- Generated streams: `.mir/streams.yml` and `docs/reference/schemas/stream-spec.md`.
- Fixtures: `.mir/fixtures.yml` and `docs/maintainer/fixture-workflow.md`.
- Release operations: `.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json` and `docs/RELEASE-RUNBOOK.md`.
- Backports: `.mir/branches.yml`, `docs/releases/mir4-post-4.0-roadmap.md`, and the MIR 3 history in `docs/maintainer/backporting.md`.

## Non-negotiable rules

- Keep docs, fixtures, scripts, tests, `.mir`, `.codex`, `.github`, `build`, `dist`, and repository guidance out of player ZIPs.
- Update the existing README in place: preserve its badges, sections, research catalog, settings explanations, examples, and troubleshooting detail unless the maintainer explicitly requests their removal. Repository/package documentation separation does not authorize shortening the repository README.
- Use the primary checkout as the completed-work handoff. Synchronize its active branch with the target remote branch, copy accepted or published packages into its `dist` with hash verification, and make the matching release notes and upload text available there. External custody and temporary worktrees do not replace local delivery. Remove disposable clean worktrees after completion; retain dirty or unique material with an explicit reason and a discoverable location in the primary checkout.
- Compatibility policy never mutates prototypes. Only admitted emission code may create or mutate generated technology prototypes.
- Every generated technology needs a stable stream manifest row; every public claim needs named exact evidence.
- Preserve one emitter and package-source parity unless a separately authorized cutover changes them.
- Preview, shadow, and experimental systems do not gain player mutation, release, signing, publication, or support authority by implementation alone.
- Regenerate `.mir` projections when authorities change. Never hand-edit generated queues, dashboards, indexes, or receipts.
- Finish completed work through PR merge, remote readback, and every required forward-port or promotion disposition. Leave the active local branch clean and exactly equal to its remote; do not require `main` and `dev` tree equality while next-release work is active.

## Verification

Before tests, materialize or inspect the MIR verification plan. Reuse evidence only for its exact trusted fingerprint and adopt matching in-progress work rather than duplicating it.

Run the narrowest selected checks first. The broad static fallback is:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Treat GitHub failures from the offline sandbox identity as execution-context failures. Retry in the approved machine/network context and request reauthentication only if `gh auth status` fails there.
