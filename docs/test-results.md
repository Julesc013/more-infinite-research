# Test Results

This file records local release-candidate validation runs. It is not a substitute for the manual mod matrix in `docs/compatibility.md`.

## 2026-07-01 Legacy Backport Planning and Branch-Aware Validation

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Rebuilt the `2.0.5` release archive after README/docs updates for the future `v2.1.0 -> v1.9.0` legacy backport strategy and the v2.0.5/v2.1.0 release split.
- Static validation passed with the new branch-aware metadata check.
- Static validation passed with the new no-`on_tick` control-stage guard.
- Package validation now requires `docs/api-proof-points.md` and `docs/manual-test-plan.md`.
- Static validation now reads `info.json` to distinguish the normal Factorio `2.1` line from future Factorio `2.0` legacy metadata.
- On the Factorio `2.1` line, validation still requires the Space Age cargo streams and cargo modifier strings.
- For future Factorio `2.0` legacy metadata, validation rejects Factorio `2.1` dependency floors and rejects `max-cargo-bay-unloading-distance` / `cargo-landing-pad-count` direct-effect stream definitions.
- Runtime fixture validation passed on the current Factorio `2.1` line, including the existing cargo scenarios.
- Actual Factorio `2.0.x` runtime validation remains future work for the `legacy` branch port.

Representative validation harness evidence:

```text
[check] release metadata matches Factorio line
[check] control runtime avoids tick handlers
[run] Factorio load check with fixture mods (base-cargo-space-age-gate)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[run] Factorio load check with fixture mods (space-age-cargo-logistics-shape)
[ok] Validation completed.
```

## 2026-07-01 v2.1.0-Bound Scripted-Tech Slice

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version metadata `2.0.5`; scripted runtime work is now treated as v2.1.0-bound until manual save validation is complete.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Rebuilt the development archive with `control.lua` and `control/` included.
- Static validation passed, including release metadata policy, docs policy scan, old science-pack authority scan, icon scan, locale parity, progression-setting wiring, changelog syntax, package metadata, package source/docs/locale/control parity, and `git diff --check`.
- Runtime fixture validation passed across the existing thirteen isolated scenarios: `reduce-policy`, `skip-policy`, `space-pack-policy`, `base-space-promethium-pack-policy`, `space-age-space-pack-policy`, `space-age-space-promethium-pack-policy`, `all-official-pack-policy`, `all-pack-policy`, `base-extension-boundary-policy`, `end-game-prerequisite-gate`, `base-cargo-space-age-gate`, `space-age-cargo-pad-enabled`, and `space-age-cargo-logistics-shape`.
- The existing Space Age fixture scenarios loaded with the new scripted technology manager present.
- Space Age fixture validation now asserts that MIR skips parallel productivity streams for vanilla-owned `processing-unit-productivity`, `low-density-structure-productivity`, `plastic-bar-productivity`, and `rocket-fuel-productivity`.
- Static validation now asserts that electric shooting speed includes both the Space Age `tesla` ammo category and the older `electric` ammo category.
- Manual gameplay validation is still required before public runtime feature release claims: spoilage deadline behavior, research reversal/configuration changes in a live save, multiple-force behavior, existing spoilable stacks, and agricultural tower planting on a large Gleba farm.

Representative validation harness evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
[run] Factorio load check with fixture mods (space-age-space-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[run] Factorio load check with fixture mods (space-age-cargo-logistics-shape)
[ok] Validation completed.
```

## 2026-06-30 Final 2.0.0 Mod-Page Release Prep

Environment:

- Mod version `2.0.0`.
- Release archive: `dist/more-infinite-research_2.0.0.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Results:

- Rebuilt the `2.0.0` release archive after the final documentation and mod-page summary pass.
- Reformatted the repo README and changelog for clearer mod-page ingestion.
- Added branch-policy and contribution guidance for the permanent `main`, `dev`, and `legacy` origin branches.
- Static validation passed, including release metadata policy, docs policy scan, old science-pack authority scan, icon scan, locale parity, progression-setting wiring, changelog syntax, package metadata, package source/docs/locale parity, and `git diff --check`.
- Manually confirmed the rebuilt release archive contains no `graphics/` entries.
- Confirmed repo release docs and generated mod-page Markdown do not advertise the deferred science-pack productivity custom art.

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
- Runtime fixture validation passed across thirteen isolated scenarios: `reduce-policy`, `skip-policy`, `space-pack-policy`, `base-space-promethium-pack-policy`, `space-age-space-pack-policy`, `space-age-space-promethium-pack-policy`, `all-official-pack-policy`, `all-pack-policy`, `base-extension-boundary-policy`, `end-game-prerequisite-gate`, `base-cargo-space-age-gate`, `space-age-cargo-pad-enabled`, and `space-age-cargo-logistics-shape`.
- The default `reduce` lab policy generated science-pack productivity with the custom item-based fixture science pack included.
- Science-pack productivity used the vanilla `research-productivity` technology art.
- The forced `skip` lab policy skipped the intentionally incompatible science-pack productivity stream with `lab_status=invalid`.
- The `space` science-pack ingredient policy added `space-science-pack` in base-only and Space Age modes without adding promethium science.
- The `space-and-promethium` science-pack ingredient policy added `space-science-pack` in base-only mode and both `space-science-pack` and `promethium-science-pack` with Space Age enabled.
- The `all-official` science-pack ingredient policy added official base and Space Age packs while excluding the custom fixture science pack from both synthetic streams and MIR-created vanilla-chain extensions.
- The `all` science-pack ingredient policy added the custom fixture science pack discovered from active lab inputs to synthetic streams and MIR-created vanilla-chain extensions.
- The base-extension boundary scenario preserved an existing finite `research-speed-7` level from a fixture mod and generated MIR's infinite continuation at `research-speed-8`.
- The late-game prerequisite gate added `space-science-pack` as a prerequisite without adding it to the generated technology science ingredients.
- Forced cargo landing pad count research skipped in base-only mode with `missing required mod space-age` and generated successfully when Space Age was enabled.
- The Space Age cargo logistics shape scenario verified cargo effect types, modifier values, research times, cost formulas, prerequisites, and all-official science-pack ingredients.
- Static validation checked that cargo bay unloading distance defaults to `120` seconds, cargo landing pad count defaults to `240` seconds, both cargo streams use official science packs only, and cargo landing pad count has a modifier-description locale key.

Representative validation harness evidence:

```text
Factorio 2.1.8 (build 86744, win64, steam, space-age)
[run] Factorio load check with fixture mods (space-pack-policy)
[run] Factorio load check with fixture mods (base-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-pack-policy)
[run] Factorio load check with fixture mods (space-age-space-promethium-pack-policy)
[run] Factorio load check with fixture mods (all-official-pack-policy)
[run] Factorio load check with fixture mods (all-pack-policy)
[run] Factorio load check with fixture mods (base-extension-boundary-policy)
[run] Factorio load check with fixture mods (end-game-prerequisite-gate)
[run] Factorio load check with fixture mods (base-cargo-space-age-gate)
[run] Factorio load check with fixture mods (space-age-cargo-pad-enabled)
[run] Factorio load check with fixture mods (space-age-cargo-logistics-shape)
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
