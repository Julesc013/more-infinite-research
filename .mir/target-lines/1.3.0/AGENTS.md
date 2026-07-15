# AGENTS.md

## Project

More Infinite Research is a Factorio mod. The 3.x direction is a modular compatibility compiler for infinite research technologies.

## Required Reading By Task

- Docs work: read `.mir/docs.yml` and `docs/maintainer/documentation-governance.md`.
- Architecture work: read `.mir/modules.yml` and `docs/architecture/module-boundaries.md`.
- Compatibility work: read `.mir/compatibility.yml`, `.mir/streams.yml`, and `docs/compatibility/claim-levels.md`.
- Generated stream work: read `.mir/streams.yml` and `docs/reference/schemas/stream-spec.md`.
- Fixture work: read `.mir/fixtures.yml` and `docs/maintainer/fixture-workflow.md`.
- Backport work: read `.mir/branches.yml` and `docs/maintainer/backporting.md`.

## Rules

- Do not put docs, fixtures, scripts, tests, `.mir`, `.codex`, `.github`, `build`, `dist`, `AGENTS.md`, `CONTRIBUTING.md`, or `todo.md` in the release zip.
- Do not let compatibility policy files mutate prototypes directly.
- Only emission code may create or mutate generated technology prototypes.
- Every generated technology needs a stable stream manifest row.
- Every public compatibility claim needs fixture or named load-check evidence.
- Update `.mir/` manifests when docs, capabilities, streams, compatibility claims, fixtures, branch policy, module boundaries, or agent routing change.

## Validation

Run the narrowest relevant validation first, then the broader gate before a release.

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

