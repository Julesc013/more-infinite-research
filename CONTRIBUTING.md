# Contributing

MIR 4.0 is a whole-platform source programme with a deliberately narrow authority model. Contributions are welcome when they preserve exact target identity, one writer per fact, one authorized emitter, and evidence-bound claims.

## Branch routing

- Target protected `dev` for next-minor or next-major implementation, architecture, preview, shadow, target, and release-engine work.
- Target protected `main` for bounded corrections to the latest stable MIR 4.x line, repository-governance maintenance, and exact qualified promotions from `dev`.
- Use a short-lived branch and a pull request. Do not leave completed work only in a local branch.
- Use `release/4.0` only for admitted 4.0.x player corrections. Bind stable-line, current-main, and dev implementations with one finding identity and explicit forward-port dispositions.
- Historical and backport branches change only under their explicit terminal programme.

After a PR merges, fetch and read back the exact protected target branch, complete every required forward-port or promotion disposition, leave the active local branch clean and equal to its remote, and remove the local topic branch. `main` and `dev` may intentionally have different trees while next-release work is active.

## Authority and maturity

Every change must identify its maturity: stable, preview, shadow, experimental, or omitted. Preview and shadow code may be complete and executable without gaining player mutation, signing, publication, or support authority.

- Compatibility policy describes decisions; it never mutates prototypes.
- Only the admitted emitter creates or mutates generated technologies.
- Every generated technology has a stable stream manifest row.
- Every public compatibility claim names fixture or exact load-check evidence.
- Target behavior needs an explicit disposition and target-local proof.
- Changes to authorities must update their machine-readable manifests.

See [Governance](GOVERNANCE.md), [Extension Protocol](EXTENSION-PROTOCOL.md), and [the module boundaries](docs/architecture/module-boundaries.md).

## Development workflow

1. Start next-minor or next-major work from clean `origin/dev`; start a latest-stable correction from `origin/main`; start a 4.0.x correction from `origin/release/4.0`.
2. Read the task-specific authorities listed in `AGENTS.md`.
3. Make one bounded change and classify its package visibility.
4. Materialize or inspect the exact verification plan.
5. Run the selected narrow checks, then the broader profile required by the risk.
6. Regenerate governed projections through their writers; never hand-edit generated dashboards or queues.
7. Open a PR, wait for the aggregate evidence gate, merge, and read back the protected branch.

For documentation, edit Markdown front matter and regenerate:

```powershell
.\tools\commands\docs\Update-MIRDocumentationIndex.ps1
.\tools\commands\docs\Update-MIRDocumentationIndex.ps1 -Check
```

For the static gate:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Use the current Factorio 2.1 Steam engine only for F210. Use the preserved Factorio 2.0 installation for F200. Do not retarget Steam depots for historical testing.

## Pull-request evidence

A PR should state:

- exact base commit and tree;
- writable paths and authorities changed;
- maturity and player-package visibility;
- proof obligations and verification-plan identity;
- package-source fingerprint result;
- rollback or compensation boundary;
- remaining human, credential, or external-service blockers.

Release-changing PRs additionally require the phase-engine receipt and independent evidence specified by [the release runbook](RELEASE-RUNBOOK.md).

## Changelog and player copy

Write package-facing text for players. Keep `changelog.txt` lines at or below 132 characters. Record shipped behavior, settings, compatibility, and migration effects; omit abandoned experiments and internal candidate churn.
