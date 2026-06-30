# Test Results

This file records local release-candidate validation runs. It is not a substitute for the manual mod matrix in `docs/compatibility.md`.

## 2026-06-30 Progression Settings and Space Age Cargo Gate Validation

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Static validation passed, including release metadata policy, docs policy scan, old science-pack authority scan, icon scan, locale parity, progression-setting wiring, changelog syntax, package metadata, package source/docs/locale parity, and `git diff --check`.
- Runtime fixture validation passed across eleven isolated scenarios: `reduce-policy`, `skip-policy`, `space-pack-policy`, `base-space-promethium-pack-policy`, `space-age-space-pack-policy`, `space-age-space-promethium-pack-policy`, `all-official-pack-policy`, `all-pack-policy`, `end-game-prerequisite-gate`, `base-cargo-space-age-gate`, and `space-age-cargo-pad-enabled`.
- The default `reduce` lab policy generated science-pack productivity with the custom item-based fixture science pack included.
- The forced `skip` lab policy skipped the intentionally incompatible science-pack productivity stream with `lab_status=invalid`.
- The `space` science-pack ingredient policy added `space-science-pack` in base-only and Space Age modes without adding promethium science.
- The `space-and-promethium` science-pack ingredient policy added `space-science-pack` in base-only mode and both `space-science-pack` and `promethium-science-pack` with Space Age enabled.
- The `all-official` science-pack ingredient policy added official base and Space Age packs while excluding the custom fixture science pack from both synthetic streams and MIR-created vanilla-chain extensions.
- The `all` science-pack ingredient policy added the custom fixture science pack discovered from active lab inputs to synthetic streams and MIR-created vanilla-chain extensions.
- The late-game prerequisite gate added `space-science-pack` as a prerequisite without adding it to the generated technology science ingredients.
- Forced cargo landing pad count research skipped in base-only mode with `missing required mod space-age` and generated successfully when Space Age was enabled.

Representative validation harness evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
[run] Factorio load check with fixture mods (space-pack-policy)
[run] Factorio load check with fixture mods (base-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (all-official-pack-policy)
[run] Factorio load check with fixture mods (all-pack-policy)
[run] Factorio load check with fixture mods (end-game-prerequisite-gate)
[run] Factorio load check with fixture mods (base-cargo-space-age-gate)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[ok] Validation completed.
```

## 2026-06-30 Official DLC Split Matrix

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam install.
- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
# For each case, run Factorio with an isolated mod directory and --dump-data.
```

Matrix cases:

- Base only.
- Elevated Rails only.
- Recycler only.
- Quality with Recycler.
- Space Age with Elevated Rails and Recycler, Quality disabled.
- Space Age with Elevated Rails, Recycler, and Quality enabled.

Results:

- Static validation passed after rebuilding the release archive.
- All official DLC matrix cases completed `--dump-data` without prototype errors or fatal log markers.
- Base-only, Elevated Rails-only, Recycler-only, and Quality-with-Recycler cases skipped absent DLC-shaped streams through `no_matching_recipes` or explicit missing prototype checks.
- Space Age without Quality loaded successfully and generated Space Age-backed streams while keeping Quality disabled.
- Science-pack productivity used `tech:research-productivity` when the Space Age technology was present and falls back to the automation science pack item icon when it is absent.

## 2026-06-30 v2.0.0 Release-Candidate Hardening

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Test-MIRLocales.ps1 -AllowMissingSupportedLanguages
git diff --check
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Locale validation passed for 9 locale files.
- Static validation passed, including metadata, no compatibility-mod dependency policy, docs policy scan, no old `data.raw.tool` science-pack authority, no generated `icon_mipmaps`, changelog format, release package metadata, source-to-zip comparison, and `git diff --check`.
- Runtime fixture validation passed and created the expected save.
- Runtime diagnostics generated `research_science_pack_productivity` with `mir-fixture-science-pack` included.
- The post-MIR assertion fixture `mir-fixture-assert-science-pack-productivity` loaded successfully, proving the custom item-based science-pack recipe received a `change-recipe-productivity` effect.

Representative runtime log evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
Loading mod more-infinite-research 2.0.0 (data-final-fixes.lua)
report kind=stream key=research_science_pack_productivity status=generated ... effects=13 lab_status=reduced ... mir-fixture-science-pack
Loading mod mir-fixture-assert-science-pack-productivity 0.1.0 (data-final-fixes.lua)
Factorio initialised
```
