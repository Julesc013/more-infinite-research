# Contributing

MIR 4.0 is a whole-platform source programme with a deliberately narrow authority model. Contributions are welcome when they preserve exact target identity, one writer per fact, one authorized emitter, and evidence-bound claims.

## Branch routing

- Target protected `dev` for MIR 4 implementation, documentation, governance, preview, shadow, target, and release-engine work.
- Use a short-lived branch and a pull request. Do not leave completed work only in a local branch.
- `main` advances only through the release promotion executor from a sealed, independently qualified candidate.
- Historical and backport branches change only under their explicit terminal programme.

After a PR merges, fetch the remote, fast-forward local `dev`, verify `dev == origin/dev`, verify divergence is `0/0`, and remove the local feature branch.

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

1. Start from clean, current `origin/dev`.
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
