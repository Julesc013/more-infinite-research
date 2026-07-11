---
title: "Build And Package"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Build And Package

Build a release package with:

```powershell
.\scripts\Build-MIRPackage.ps1
```

Package validation builds from the current source tree and checks that repository-only material is excluded.

## Published Archives

Files in `dist/` are upload artifacts for specific versions. Once a version has been published, its archive is immutable repository evidence.

Do not refresh these archives during later architecture or backport work:

- `dist/more-infinite-research_2.2.0.zip`;
- `dist/more-infinite-research_1.9.2.zip` on `legacy` after upload.

The current post-`2.2.0` development line targets `3.0.0`. Its planned target-line ports are `2.3.0` for Factorio `2.0` and `1.9.3` for Factorio `1.1`. Build or refresh `dist/<mod>_<version>.zip` only for the unpublished target version being released.

For regression or architecture work before the version bump, prefer validation archives under `build/validation-dist/` and restore any accidental published archive rebuilds before committing.

## Repository-Only Evidence

The source repository intentionally keeps governance and release evidence that must not ship in the mod zip:

- `todo.md` is the executable future-work ledger.
- `.mir/` is the machine-readable governance manifest set.
- `docs/` contains maintainer, user, architecture, release, and reference docs.
- `fixtures/`, `scripts/`, `tests/`, and `tools/` are validation and maintainer workspaces.
- `build/` and `dist/` are generated or published artifact locations.

Package validation rejects those repository-only paths inside the generated archive. Keeping them tracked in source does not make them release contents.
