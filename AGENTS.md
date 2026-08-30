# AGENTS.md

## Project

More Infinite Research 4 is a proof-governed Factorio research product line. MIR 4.0.0 combines stable F210/F200 player targets, separately distributed developer previews, and executable package-excluded shadow architecture.

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
- Release operations: `.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json` and `RELEASE-RUNBOOK.md`.
- Backports: `.mir/branches.yml`, `docs/releases/mir4-post-4.0-roadmap.md`, and the MIR 3 history in `docs/maintainer/backporting.md`.

## Non-negotiable rules

- Keep docs, fixtures, scripts, tests, `.mir`, `.codex`, `.github`, `build`, `dist`, and repository guidance out of player ZIPs.
- Compatibility policy never mutates prototypes. Only admitted emission code may create or mutate generated technology prototypes.
- Every generated technology needs a stable stream manifest row; every public claim needs named exact evidence.
- Preserve one emitter and package-source parity unless a separately authorized cutover changes them.
- Preview, shadow, and experimental systems do not gain player mutation, release, signing, publication, or support authority by implementation alone.
- Regenerate `.mir` projections when authorities change. Never hand-edit generated queues, dashboards, indexes, or receipts.
- Finish completed work through PR merge, remote readback, and protected `main` to `dev` synchronization. Leave local `dev` clean and exactly equal to `origin/dev`, with the remote `main` and `dev` trees equal.

## Verification

Before tests, materialize or inspect the MIR verification plan. Reuse evidence only for its exact trusted fingerprint and adopt matching in-progress work rather than duplicating it.

Run the narrowest selected checks first. The broad static fallback is:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Treat GitHub failures from the offline sandbox identity as execution-context failures. Retry in the approved machine/network context and request reauthentication only if `gh auth status` fails there.
