# v2.0.5 Pre-Manual Readiness Report

Updated: 2026-07-01

This report records the state after automated remediation, Lua API review, validation hardening, package rebuilds, and pre-manual runtime checks.

## Current Decision

`v2.0.5` is ready for manual gameplay validation.

The non-scripted quick-patch work is automated-test ready. The scripted spoilage preservation and agricultural growth speed streams are implemented, load-tested, and disabled by default. They should stay disabled by default unless the manual gameplay matrix proves their behavior clearly enough for public release claims.

## Remediation Completed

- Spoilage preservation now clears stored `effective_level` when MIR stops applying or restores its multiplier.
- Static validation now fails if `research_spoilage_preservation` or `research_agricultural_growth_speed` stops being default-off before manual proof is recorded.
- Runtime validation now includes force-enabled scripted-candidate scenarios:
  - base-only: both scripted streams must skip because Space Age is missing;
  - Space Age: both scripted streams must generate with one visible `nothing` effect.
- Runtime validation no longer copies the whole repository into every Factorio temp mod folder. It copies only mod source/package files, avoiding `.git`, `build`, `dist`, `fixtures`, and `scripts`.
- Successful runtime validation runs now clean their generated temp user-data directory.
- Old MIR temp validation directories were removed from `%TEMP%` after the previous harness behavior filled the temp drive.

## Lua API Practice Check

Official latest Factorio API docs checked on 2026-07-01 are `2.1.9`. Local runtime validation is still on Factorio `2.1.8` build `86744`.

The current implementation follows the API boundary:

- `control.lua` is used only for runtime scripting.
- Scripted effects use event hooks, not `on_tick` or `script.on_nth_tick`.
- `DifficultySettings.spoil_time_modifier` is treated as a global setting, not a per-force setting.
- Spoilage preservation stores MIR's baseline and effective multiplier so it can avoid compounding its own prior writes.
- Agricultural growth speed uses `on_tower_planted_seed` and guarded `LuaEntity.tick_grown` access.
- Existing plants, inventories, belts, labs, containers, rockets, platforms, surfaces, and item stacks are not broadly scanned.
- Visible scripted technologies use `NothingModifier` effects for player-facing UI text.
- Space Age-only scripted streams have Space Age gates and are tested to skip in base-only mode.

## Automated Validation Completed

Commands run:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Validation status:

- Static validation passed.
- Runtime fixture validation passed across 22 isolated scenarios.
- Package/source parity passed.
- Locale parity passed across 9 locale files.
- Changelog format passed.
- No-runtime-tick guard passed.
- Scripted default-off guard passed.
- The rebuilt release archive is `dist/more-infinite-research_2.0.5.zip`.

## What You Need To Manually Test

### Minimum If Scripted Streams Stay Disabled

These are still worth doing before publishing the default-off `2.0.5` package:

- `normal-mod-folder-load`: load `dist/more-infinite-research_2.0.5.zip` from a normal Factorio mods folder and confirm the game sees version `2.0.5`.
- `vanilla-locale-icons`: base game without Space Age; confirm Electric Shooting Speed uses discharge defense art/description and flamethrower/electric descriptions display.
- `fresh-space-age`: fresh Space Age save; confirm Electric Shooting Speed has both `electric` and `tesla` effects.
- `circuit-productivity-ownership`: base-only green/red/blue circuits are MIR-owned; Space Age green/red stay MIR-owned while processing unit stays vanilla-owned.
- `quality-module-productivity`: with real Quality enabled, confirm module productivity includes quality module recipes.
- `omega-drill-productivity`: with real Omega Drill or representative mod installed, confirm mining drill productivity includes its drill recipes.
- `tank-uranium-shell-speed`: confirm tank cannon fire rate with uranium shells is not reduced after finite vanilla weapon speed techs.
- `existing-mir-2.0-save`: load an existing MIR save and confirm no migration/runtime error.

### Required Before Enabling Scripted Streams By Default

Enable `research_spoilage_preservation` and/or `research_agricultural_growth_speed` from startup settings in a test copy only.

Spoilage preservation:

- Fresh Space Age save: tech appears, researches, and displays scripted effect text.
- New spoilable stacks before/after research: confirm spoil deadline behavior.
- Existing stacks on belts, in chests, in labs, in rocket/platform inventories: record whether deadlines change or stay fixed.
- Partially spoiled stacks and split/merge stacks: record behavior.
- Research reversal: confirm the global modifier recomputes to the expected value.
- Disable/re-enable path: confirm MIR restores or preserves the baseline as documented.
- Non-1 baseline: start from a changed `spoil_time_modifier` and verify no compounding.
- External mutation: manually change `spoil_time_modifier` after MIR applies, then research/reverse again.
- Multi-force: confirm the highest non-enemy/non-neutral force level policy.

Agricultural growth speed:

- Fresh Space Age save: tech appears, researches, and displays scripted effect text.
- Newly planted tower crops: confirm `tick_grown - game.tick` is shortened after research.
- Level off-by-one: confirm the first completed level gives one level of effect.
- High level cap: confirm it clamps at the documented `10x`.
- Existing plants: confirm they are untouched in `2.0.5`.
- Save/load: research, save, reload, plant again, and confirm the effect still applies.
- Multi-force: confirm tower force determines the multiplier.
- Large Gleba farm: plant many crops and confirm there is no visible performance issue.

## Not Finished Or Not Ready

- Scripted spoilage preservation is not ready to enable by default until manual save behavior is recorded.
- Scripted agricultural growth speed is not ready to enable by default until the tower planting behavior and large-farm behavior are recorded.
- Changelog/README must not claim measured spoilage existing-stack behavior yet.
- Existing agricultural plant rescale is intentionally not implemented for `2.0.5`.
- Factorio `2.0.x` legacy backport is not started; the next plan is to backport the tested `2.0.5` quick-patch snapshot as `1.9.0` after the minimum `2.0.5` manual smoke checks pass.
- Factorio `2.1.9` runtime validation has not been run locally; only official API docs were rechecked at `2.1.9`.
- Real-mod manual checks for Quality and Omega Drill remain separate from fixture proof.

## Release Recommendation

Ship `2.0.5` only after the manual UI/package smoke checks pass.

If the scripted streams remain disabled by default, the package can ship as a safe quick patch after the minimum manual checks. If either scripted stream is enabled by default, complete and record the full scripted manual matrix first.
