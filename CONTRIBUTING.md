---
title: "Contributing to MIR"
status: current
applies_to: "MIR development"
audience: contributor
doc_type: guide
owner: mir-maintainers
last_reviewed: 2026-11-06
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-contributor-entrypoint
---

# Contributing

MIR development happens on `dev`. Start with a small fix or improvement, check the affected behavior and open a pull request against `dev`.

## Build or change a feature

The [development guide](docs/development.md#build-a-local-zip) gives the local ZIP command and prerequisites. Building a ZIP needs Git and Python, without Factorio, release credentials, a private worker or a paid AI service.

Use the [source responsibility map](docs/architecture.md#where-to-change-a-feature) to find the feature. Read [AGENTS.md](AGENTS.md) and the relevant [contract](spec/README.md#task-routing), then change the owning source and its affected tests or documentation. Player code lives in `source/`; keep developer tools and test output outside player ZIPs.

Preserve published technology and setting IDs, API paths, saved-state keys and migration filenames. Keep the authored README and release history. A file move can change package imports even when its Lua behavior is unchanged.

Use a task branch from current `dev`. Maintenance of an older published MIR version starts from its exact tag on a separate branch; see [branch routing](docs/development.md#development-line-and-maintenance-branches). `main` contains the published product.

## Check the change

Inspect the current host plan before choosing checks:

```powershell
.\tests\Test-MIR5HostControls.ps1 -Plan
python -B tools/check_repository.py
```

Run the narrow controls relevant to the change first. The [test guide](docs/development.md#test-selection) explains the full host driver and its pinned Lua runtime. Host checks do not launch Factorio or prove gameplay, save, client or performance behavior; report those limits when they matter.

For native tests, use the matching installed engine and coordinate with the active test owner so two jobs do not compete. Preserve original saves, selected mod archives and settings. Do not retarget Steam for historical engines. Current commands and custody rules are in the development guide.

Keep unique work, failed observations and existing output under the documented retained locations. In particular, `build/qualification` contains evidence and saves; it is not a disposable build directory.

## Open a pull request

Explain:

- What changed and why.
- Which checks ran and what they showed.
- Any affected compatibility, settings or save behavior.
- Anything still unverified.

Link the relevant issue or historical decision when there is one. Preserve independent expectations rather than changing a test just to accept the new output. The [PR template](.github/PULL_REQUEST_TEMPLATE.md) provides the same short checklist.

Commit and push a reviewable unit. Ordinary development integration uses the repository's required checks and standing maintainer authorization. Preserve other contributors' work and original commits; never reset, force-push or rebase shared work to synchronize it.

For a release-history change, edit `CHANGELOG.md` and run `python -B tools/changelog.py --write`; commit its rendered `source/changelog.txt` together. Write player-facing notes about actual behavior and support limits.

## Official releases

Official publication follows the [release procedure](docs/development.md#github-publication-after-a-reviewed-verdict), including its candidate, package, upgrade-safety, review and delivery checks. A local build or green host run does not establish release readiness. MIR5 stable acceptance remains separate from a GitHub prerelease.

The integration owner coordinates main promotion and GitHub publication. The maintainer handles Mod Portal delivery. Published package bytes and tags stay preserved.
