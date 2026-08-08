# Contributing

Thanks for helping improve **More Infinite Research**. MIR 3 is in its terminal stabilization programme across several Factorio target lines, so branch choice and release disposition matter.

## Branch Policy

The repository has **three permanent branches** on `origin`:

- **`main`**: published **Factorio `2.1.x`** line rooted at immutable tag `3.2.5`, plus synchronized release planning and qualified promotions.
- **`dev`**: canonical terminal-planning and implementation line for `3.2.9`, shared tooling, tests, and target-neutral corrections.
- **`legacy`**: published **Factorio `2.0.x`** line at immutable tag `2.5.5`; it advances only through governed `2.5.9` promotion.

Short-lived feature branches are fine, but they should target one of these permanent branches by pull request.

Use this routing:

- Target **`dev`** for admitted MIR 3 corrections, shared tooling, governance, and eventual `3.2.9` work.
- Target **`main`** only for synchronized release records or a qualified promotion from `dev`.
- Target **`legacy`** only through a governed, independently qualified Factorio 2.0 promotion.

Do not merge Factorio `2.1`-only APIs or metadata into **`legacy`** unless the change is guarded or rewritten for Factorio `2.0`.

The `.5` tags and packages are immutable. Do not create `.6`, `.7`, or `.8` releases. Route every later MIR 3 correction to `3.2.9`, `2.5.9`, or the matching `1.x.9` target under the [terminal programme](docs/releases/mir-3-terminal-dot-9-programme.md). Feature and platform redesign belongs to the MIR 4 handoff.

## Compatibility Expectations

More Infinite Research prefers **opportunistic compatibility**:

- Discover recipes, items, technologies, science packs, and labs from visible prototypes.
- Skip unavailable or unsafe generated research instead of hard-failing.
- Keep third-party compatibility mod dependencies out of `info.json` unless there is no safer option.
- Preserve existing generated prototype IDs unless a migration plan exists.
- Leave finite vanilla and other-mod upgrade chains alone.

For `legacy`, keep Factorio `2.0.x` constraints in mind:

- `info.json` must keep `factorio_version = "2.0"`.
- Do not depend on Factorio `2.1` technology modifier APIs.
- Do not assume Factorio `2.1` science-pack item behavior unless the backport implements a safe alternative.

## Pull Request Checklist

Before opening a pull request:

- Pick the correct base branch: **`dev`**, **`main`**, or **`legacy`**.
- Keep the change focused on one behavior or release task.
- Update README, changelog, locale, and compatibility docs when behavior changes.
- Classify each change against the terminal programme and its affected target lines.
- Never rebuild a published `.5` ZIP. Build only after a new `.9` source and candidate are explicitly admitted.
- Materialize the exact MIR verification plan before running its selected work.

For most repo changes on `main` or `dev`, first materialize or inspect the exact change-aware plan, then run only its selected work. The static command remains the narrow fallback for changes that select it:

```powershell
.\tools\commands\package\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

For risky generation, science-pack, cargo logistics, or compatibility changes, also run runtime validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

For branch policy changes:

```powershell
.\validation\tests\release\Test-MIRBranchPolicy.ps1
```

## Changelog and Mod Portal Notes

The Factorio mod portal ingests the packaged README and changelog, so write them for players first:

- Keep changelog bullets concise and useful to players, server admins, or compatibility maintainers.
- Keep each `changelog.txt` line at or below **132 characters**.
- This 132-character line cap applies only to `changelog.txt`; Markdown docs use normal prose.
- Lead with shipped behavior: added research, changed balance, fixed compatibility, changed settings, or migration.
- Keep related details together when they are one user-facing change; do not create fake continuation bullets.
- Mention implementation details only when they affect compatibility, settings, migrations, or save behavior.
- Do not log abandoned experiments, release-candidate churn, validation fixtures, smoke checks, or package mechanics.

## Release Notes

Release commits should leave:

- `info.json` matching the intended Factorio line.
- `changelog.txt` with the release version and date.
- `dist/more-infinite-research_<version>.zip` deterministically built from the admitted unpublished candidate; published archives remain untouched.
- Static validation passing.
- Runtime validation passing when the change touches prototype generation or compatibility behavior.
- The typed ReleaseRecord, release notes, approved delta, tag, and public verification consistent with the exact package identity.
