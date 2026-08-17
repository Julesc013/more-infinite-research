# AGENTS.md

## Project

More Infinite Research is a Factorio mod. The 3.x direction is a modular compatibility compiler for infinite research technologies.

## Local Factorio Engine Authority

- Use the Steam installation at `C:\Program Files\Steam\steamapps\common\Factorio` only for the current Factorio 2.1 engine.
- Use the preserved installations under `D:\Programs\Factorio\<version>` for Factorio 2.0 and every older engine; for example, Factorio 2.0 is `D:\Programs\Factorio\2.0\bin\x64\factorio.exe`.
- Do not download, replace, retarget, or mutate Steam depots to obtain historical engines unless the maintainer explicitly requests it.

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
- Before running tests, materialize or inspect the MIR verification plan and run only its required work unless a broader profile or `--no-reuse` was explicitly requested. Reuse evidence only for an exact trusted fingerprint; adopt a matching in-progress worker instead of cancelling it or starting duplicate work; never substitute mutable job status for the aggregate evidence gate.
- In Codex sessions, treat `gh` failures from the `codexsandboxoffline` Windows identity or blocked outbound sockets as sandbox-context failures, not evidence that the maintainer's GitHub token is invalid. Retry GitHub operations in the approved machine/network context and ask for reauthentication only if `gh auth status` fails there.

## Validation

Run the narrowest relevant validation first, then the broader gate before a release.

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

