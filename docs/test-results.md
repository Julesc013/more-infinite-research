# Test Results

This file records local release-candidate validation runs. It is not a substitute for the manual mod matrix in `docs/compatibility.md`.

## 2026-07-02 Final v2.0.5 Release-Candidate Validation

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.
- Branch before docs/package commit: `dev` at `4ec2ed6`, synced with `origin/dev`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
git diff --check
git status --short --branch
git log --oneline --decorate --graph --max-count=8
git branch -vv
rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes
rg "on_tick" control prototypes
rg "icon_mipmaps" prototypes
```

Results:

- Rebuilt `dist/more-infinite-research_2.0.5.zip` from the current source tree.
- Static/package validation passed.
- Runtime fixture validation passed against Factorio `2.1.8`.
- Branch policy validation passed for `origin/main`, `origin/dev`, and `origin/legacy`.
- Locale parity validation passed across 9 locale files.
- Package/source parity validation passed, including required `control/`, `migrations/`, `locale/`, and release documentation files.
- No-runtime-tick validation passed for `control.lua` and `control/`.
- Scripted Space Age candidate validation passed: Spoilage preservation and Agricultural growth speed remain default-off in `v2.0.5`.
- Settings confidence validation passed: generated setting names/descriptions, dropdown option descriptions, setting notes, diagnostics order, default bounds, and reader coverage are present.
- Runtime fixture coverage passed for 23 isolated scenarios: base-only generation, Space Age generation, science-pack policies, lab compatibility policies, base extension boundaries, weapon speed overlap safety, Omega Drill style recipe matching, cargo gates, cargo duplicate diagnostics, scripted candidate force-enable generation, icon source checks, icon badge checks, Space Age duplicate productivity skips, and base-game Research productivity.
- Direct release-candidate grep checks found no stale `data.raw.tool`/old science-pack authority patterns, no tick handlers, and no deprecated prototype `icon_mipmaps` usage.
- Release scan found no active `TODO`, `FIXME`, `TBD`, `BROKEN`, or stale player-facing blocker outside documented manual-validation items and historical changelog/roadmap notes.

Remaining release gate:

- Manual in-game smoke testing from a normal Factorio mods folder is still required before tagging and publishing.
- Scripted spoilage/agriculture behavior remains default-off and should not be described with stronger gameplay claims until the manual matrix records measured results.

## 2026-07-02 Base-Game Research Productivity And Icon Source Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
```

Results:

- Processing Unit productivity now borrows the `processing-unit` unlock technology art, with the old `advanced-electronics-2` ID retained as an icon fallback for compatibility.
- Wall productivity now borrows the vanilla `gate` technology art.
- Rocket Fuel productivity now borrows the vanilla `rocket-fuel` unlock technology art.
- Science pack productivity now uses Space Age `research-productivity` art when available and base-game `space-science-pack` technology art otherwise.
- Added base-game Research productivity as a direct-effect stream using Factorio's native `laboratory-productivity` modifier.
- Space Age skips MIR's Research productivity stream because vanilla `research-productivity` already exists.
- Base-game Research productivity uses Military science pack technology art with MIR's productivity badge.
- Runtime fixtures assert the new icon sources, base-game Research productivity generation, Space Age duplicate prevention, and the productivity badge for the native lab-productivity stream.

## 2026-07-02 Agricultural Growth Icon And Pre-Manual Regression Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
.\scripts\Test-MIRBranchPolicy.ps1
```

Results:

- Agricultural Growth Speed now borrows the vanilla Space Age `agriculture` technology art instead of the agricultural science pack item icon.
- The generated technology still receives MIR's speed badge after inherited constant badges are stripped.
- Added runtime fixture coverage that fails if Agricultural Growth Speed stops using the vanilla `agriculture` technology art.
- Static/package validation, runtime fixture validation, branch policy validation, locale parity, package parity, no-`on_tick` guard, scripted default-off guard, and generated icon badge checks passed.
- Manual gameplay validation is still required before enabling scripted streams by default or making stronger measured spoilage/agriculture behavior claims.

## 2026-07-02 Cannon Shell Productivity And Icon Badge Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Renamed the player-facing `research_heavy_ammo` line to Cannon shell productivity while preserving the generated technology ID `recipe-prod-research_heavy_ammo-1`.
- Changed Cannon shell productivity to use cannon shell item art, matching the Cannon Shooting Speed base icon family.
- Kept Cannon shell productivity scoped to ammo recipes: cannon shells, artillery shell, railgun ammo, and compatible modded shell/ammo patterns.
- Left artillery turrets, artillery wagons, railgun turrets, and other machines out of this ammo tech for `v2.0.5`; those belong in a future systems/productivity decision if added.
- Updated generated stream icon construction so inherited vanilla technology constant badges are stripped before MIR applies the badge matching its actual effect.
- Added runtime fixture assertions that generated MIR stream icons have the expected effect badge and no wrong inherited constant badge.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Settings Confidence Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Rebuilt the release archive after settings UI and locale changes.
- Static/package validation passed.
- Runtime fixture validation passed across twenty-three isolated scenarios.
- Locale parity validation passed across nine locale files after normalizing settings UI text to English fallback where translations are not yet refreshed.
- Added validation coverage for default-disabled-first technology setting order, diagnostics ordering, dropdown option descriptions, default-off warning notes, base-extension max-level locale wiring, and README settings guidance.
- No real settings presets were added; preset mode and override behavior remain planned for `v2.1.0`.

## 2026-07-01 Final Smoke Plan Guard

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Added `character-reach-icon` and `merged-inventory-trash-ui` to the canonical manual `v2.0.5` smoke plan.
- Added static validation that required final manual scenario names stay present in `docs/manual-test-plan.md`.
- Added static validation that required API proof links stay present in `docs/api-proof-points.md`, and that the API link list does not contain empty link entries.
- GitHub issue #5 was rechecked through the GitHub API and was already closed as completed.
- Static/package validation passed after rebuilding the release archive.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Electric Shooting Speed Space Age Icon

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Electric Shooting Speed now prefers the Space Age `electric-weapons-damage-1` technology icon when Space Age is active.
- Electric Shooting Speed still falls back to the base discharge defense technology icon when Space Age is absent.
- Runtime diagnostics now assert the Space Age scenario resolves `icon=tech:electric-weapons-damage-1`; the existing base/no-Space-Age scenario still asserts `icon=tech:discharge-defense-equipment`.
- Static/package validation passed after rebuilding the release archive.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Character Reach Icon

Environment:

- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Character reach bonus now uses the same base pickaxe technology icon texture as character mining speed.
- Static/package validation passed after rebuilding the release archive.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Spoilage Icon And Character Slot Merge

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Official Factorio migration and command-line docs checked on 2026-07-01.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Scripted `nothing` effects now use compact base stream icons, not full technology icon stacks with floating constant overlays.
- Character inventory slot research now grants both `character-inventory-slots-bonus` and `character-logistic-trash-slots`.
- Removed the separate generated `research_character_trash_slots` stream, setting, and current locale key.
- Added `migrations/more-infinite-research_2.0.5.json` to map `recipe-prod-research_character_trash_slots-1` into `recipe-prod-research_inventory_capacity-1` for existing saves.
- Package/build/runtime-copy validation now includes `migrations/`.
- Runtime validation now uses an isolated Factorio config and write-data/log directory, so the fixture matrix does not read the live GUI profile log.
- Added runtime scenario `character-inventory-merged-effects`, verifying `research_inventory_capacity` generates with `effects=2` and no old `research_character_trash_slots` stream diagnostics.
- Static validation passed.
- Runtime fixture validation passed across twenty-three isolated scenarios.

## 2026-07-01 Legacy Cadence Reorder

Environment:

- Mod version `2.0.5`.
- Planning/docs-only change.

Results:

- Reordered the planned Factorio `2.0.x` legacy cadence so `v1.9.0` is now a compatibility backport of the tested `v2.0.5` quick-patch snapshot.
- Kept `v2.1.0` as the next larger Factorio `2.1.x` feature wave after `v2.0.5` and `v1.9.0`.
- Kept later backport cadence as `v2.1.5 -> v1.9.5` and final `v1.9.9` from the latest tested `2.x.x` source snapshot at the verified upstream cutoff.
- Preserved the requirement that `v1.9.0` remove or guard Factorio `2.1`-only cargo modifier surfaces unless Factorio `2.0.x` validation proves support.

## 2026-07-01 Diagnostic Cargo Overlap Pull-Forward

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Added diagnostic-only native modifier overlap reporting for direct-effect streams.
- Added `mir-fixture-duplicate-cargo-tech`, a Maraxis-like Space Age fixture with infinite `cargo-landing-pad-count` and `max-cargo-bay-unloading-distance` technologies.
- Runtime fixture validation now includes `space-age-duplicate-cargo-diagnostics`.
- The duplicate cargo scenario force-enables MIR cargo landing pad count, keeps cargo bay unloading distance enabled, and verifies both generated MIR cargo technologies still load.
- The duplicate cargo scenario verifies non-blocking `native_modifier_overlap` diagnostics for both cargo native modifiers and their fixture owners.
- Static validation passed.
- Runtime fixture validation passed across twenty-two isolated scenarios.

## 2026-07-01 Pre-Manual Hardening And Harness Repair

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Official latest API docs checked on 2026-07-01: `2.1.9`.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
# Separately: load dist/more-infinite-research_2.0.5.zip from isolated base-only and Space Age mod folders.
```

Results:

- Added `docs/pre-manual-2.0.5-report.md` with the manual test checklist, not-ready list, and Lua API practice check.
- Static validation now requires scripted spoilage preservation and agricultural growth speed to remain default-off until manual proof is recorded.
- Runtime fixture validation now force-enables both scripted candidate streams in base-only and Space Age scenarios. Base-only must skip them for missing Space Age; Space Age must generate each with one visible `nothing` effect.
- Fixed the runtime validation harness so it copies only package/source files into isolated Factorio mod folders instead of recursively copying the entire Git repository.
- Successful runtime validation runs now clean the generated temp user-data directory.
- Spoilage preservation now resets stored `effective_level` when MIR restores or stops applying its multiplier.
- Static validation passed.
- Runtime fixture validation passed across twenty-one isolated scenarios.
- The release zip loaded from isolated base-only and Space Age mod folders and created fresh saves.
- `git diff --check` passed. Git reported line-ending normalization warnings only.
- Manual gameplay validation remains required before enabling scripted streams by default or making measured spoilage/agriculture release claims.

## 2026-07-01 Scripted Defaults And API Recheck

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Official latest API docs checked on 2026-07-01: `2.1.9`.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
# Separately: copy dist/more-infinite-research_2.0.5.zip into isolated temp mod folders and run
# Factorio --create once with base only and once with Space Age/official DLC enabled.
```

Results:

- Rebuilt the release archive after code and documentation changes.
- Scripted spoilage preservation and agricultural growth speed are now disabled by default for `v2.0.5`; manual save validation is required before default enablement or stronger behavior claims.
- Spoilage preservation now stores MIR's actual applied multiplier after the clamped spoil-time value is written, so baseline rebase/restore logic is based on the effective multiplier rather than the requested multiplier.
- Documented scripted runtime storage keys in `docs/architecture.md`.
- Rechecked official latest API docs and filled the API proof ledger links. Local runtime fixture validation remains on Factorio `2.1.8`.
- Static validation passed, including release metadata, hidden Quality ordering, locale parity, changelog format, package parity, required docs/control files, and the no-runtime-tick guard.
- Runtime fixture validation passed across nineteen isolated scenarios.
- The release zip loaded from isolated normal mod folders in both base-only and Space Age modes and created fresh saves.
- `git diff --check` passed. Git reported line-ending normalization warnings only.
- Manual gameplay validation is still not complete for spoilage existing stacks, spoilage reversal/disable behavior, multi-force behavior, normal UI save checks, and large Gleba farms.

## 2026-07-01 Generated Chain Integrity

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
```

Results:

- Replaced narrow processing-unit-only assertions with `mir-fixture-assert-generation-integrity`.
- Runtime fixture validation passed across nineteen isolated scenarios, including `base-generation-integrity`, `base-generation-integrity-inserter-enabled`, `space-age-generation-integrity`, and `space-age-generation-integrity-inserter-enabled`.
- The broad fixture verified every generated `recipe-prod-*` technology is an infinite upgrade with effects and a count formula.
- The broad fixture verified default-enabled vanilla numbered extension chains have exactly one infinite serial continuation in both base-only and Space Age runs.
- The broad fixture verified the normally disabled `inserter-capacity-bonus` chain stays absent by default and generates exactly one serial continuation when force-enabled in both base-only and Space Age runs.
- The broad fixture verified every recipe has at most one infinite recipe-productivity owner.
- Circuit productivity ownership is now checked by recipe ID: base-only green/red/blue circuit recipes are MIR-owned, while Space Age green/red circuits remain MIR-owned and processing-unit productivity remains vanilla-owned.
- Space Age vanilla productivity ownership remained authoritative for processing units, low density structures, plastic, and rocket fuel recipes.
- Static validation now rejects incomplete local fixture directories before runtime fixture validation starts.

## 2026-07-01 Weapon Speed Safety And Quality Enrichment Triage

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Narrowed weapon shooting speed overlap adjustment so it only strips `rocket` and `cannon-shell` from MIR's generated `weapon-shooting-speed` continuation, not finite vanilla weapon shooting speed technologies.
- Added `mir-fixture-assert-weapon-speed-safety`, which failed the load if finite vanilla `weapon-shooting-speed-5` or `weapon-shooting-speed-6` lost `cannon-shell` effects under the overlap setting.
- Runtime fixture validation passed across fifteen isolated scenarios, including the new `weapon-speed-overlap-safety` scenario.
- Documented quality module enrichment as a future spike/add-on candidate, not a `v2.0.5` quick patch. The local Quality prototypes store module quality chance in `effect.quality`, and the official modifier list does not expose a native technology modifier for increasing module quality chance.
- Rebuilt the release archive after code, fixture, locale, and docs updates.

## 2026-07-01 GitHub Issue Fix Pass

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
git diff --check
```

Results:

- Fixed GitHub issue #3 coverage: electric shooting speed now uses the vanilla discharge defense technology as its icon/prerequisite anchor when Space Age is absent, and MIR supplies missing flamethrower/electric/Tesla shooting-speed descriptions.
- Fixed GitHub issue #4 coverage: mining drill productivity now matches Omega Drill style `omega-drill` and `omega-tau` recipes plus broader visible modded `*-mining-drill` / `*-drill` outputs in the high-tier bucket.
- Fixed GitHub issue #5 coverage: `info.json` now declares Quality as a hidden optional dependency, so module productivity generation sees quality module recipes when Quality is active.
- Static/package validation passed, including hidden Quality dependency policy, locale parity across 9 locale files, science-pack wiring, package metadata, and `git diff --check`.
- Runtime fixture validation passed across fourteen isolated scenarios, including the new `omega-drill-productivity` scenario.
- Runtime assertions verified base/no-Space-Age electric shooting speed generates with one `electric` effect and the discharge defense icon, base flamethrower shooting speed generates, and Space Age electric shooting speed generates with both `electric` and `tesla` effects.
- The Omega Drill assertion fixture verified `omega-drill` and `omega-tau` recipe productivity effects after MIR generation; the diagnostics row for `research_mining_drill` reported the expanded effect count.
- Manual UI validation is still recommended for the base-only `vanilla-locale-icons`, real `quality-module-productivity`, and real Omega Drill `omega-drill-productivity` scenarios before publishing the final mod-portal build.

## 2026-07-01 Release Cadence Correction

Environment:

- Mod version `2.0.5`.
- Release archive: `dist/more-infinite-research_2.0.5.zip`.

Commands:

```powershell
.\scripts\Build-MIRPackage.ps1
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
git diff --check
```

Results:

- Updated the docs back to the intended cadence: `v2.0.5` is the quick feedback patch for easy validated changes, `v2.1.0` is the larger feature wave, `v1.9.0` is backported from `v2.1.0`, `v2.1.5` can backport to `v1.9.5`, and `v1.9.9` is reserved as the final planned Factorio `2.0` port from the latest tested `2.x.x` snapshot at the Factorio `2.1` stable cutoff target.
- Rebuilt the `2.0.5` release archive after README, roadmap, TODO, compatibility, API proof, manual-test, post-2.0 planning, changelog, and test-results updates.
- Static validation passed with package/source/docs parity.
- `git diff --check` passed.
- Runtime validation was not rerun for this correction because the changes were documentation, changelog, and rebuilt-package parity only.

## 2026-07-01 Release Cadence and Branch-Aware Validation

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

- Rebuilt the `2.0.5` release archive after README/docs updates for the release cadence: `v2.0.5` quick feedback patch, `v2.1.0` larger feature wave, `v2.1.0 -> v1.9.0` first legacy port, later `v2.1.5 -> v1.9.5`, and final `v1.9.9` legacy port from the latest tested `2.x.x` snapshot.
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

## 2026-07-01 v2.0.5 Candidate Scripted-Tech Slice

Environment:

- Factorio `2.1.8` build `86744`, Windows Steam, Space Age install.
- Mod version metadata `2.0.5`; scripted runtime work is a default-off `v2.0.5` ship candidate and requires manual save validation before default enablement or stronger behavior claims.
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
- Manual gameplay validation is still required before final `v2.0.5` runtime feature claims: spoilage deadline behavior, research reversal/configuration changes in a live save, multiple-force behavior, existing spoilable stacks, and agricultural tower planting on a large Gleba farm.

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
- At the time, Science-pack productivity used `tech:research-productivity` when the Space Age technology was present and fell back to the automation science pack item icon when it was absent. This fallback was later replaced with the base-game `space-science-pack` technology art in the 2026-07-02 Base-Game Research Productivity And Icon Source Pass above.

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
