# Contributing

Thanks for helping improve **More Infinite Research**. This project is maintained for two active Factorio lines, so branch choice matters.

## Branch Policy

The repository has **three permanent branches** on `origin`:

- **`main`**: latest stable release line for **Factorio `2.1.x`**.
- **`dev`**: experimental and development branch for the **Factorio `2.1.x` main line**.
- **`legacy`**: backport branch for **Factorio `2.0.x`** players.

Short-lived feature branches are fine, but they should target one of these permanent branches by pull request.

Use this routing:

- Target **`dev`** for normal new work, experiments, compatibility changes, and unreleased fixes for the current `2.1.x` line.
- Target **`main`** only for release-ready hotfixes or promotion from `dev`.
- Target **`legacy`** only for backports that must remain compatible with Factorio `2.0.x`.

Do not merge Factorio `2.1`-only APIs or metadata into **`legacy`** unless the change is guarded or rewritten for Factorio `2.0`.

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
- Rebuild the release zip when packaged files change.
- Run the relevant validation commands.

For most repo changes on `main` or `dev`:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

For risky generation, science-pack, cargo logistics, or compatibility changes, also run runtime validation:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

For branch policy changes:

```powershell
.\scripts\Test-MIRBranchPolicy.ps1
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
- `dist/more-infinite-research_<version>.zip` rebuilt.
- Static validation passing.
- Runtime validation passing when the change touches prototype generation or compatibility behavior.
