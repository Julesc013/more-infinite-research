# Compatibility and Validation

More Infinite Research's current main line targets Factorio `2.1.x` and uses a compatibility-first data-stage plus narrow control-stage model.

Release-line summary:

| MIR release | Factorio line | Scope |
| --- | --- | --- |
| `2.0.5` | `2.1.x` | stabilization, docs, package parity, validation hardening |
| `2.1.0` | `2.1.x` | settings presets and validated scripted agriculture/spoilage runtime features |
| `1.9.0` | `2.0.x` | compatible subset backported from the tested `2.1.0` snapshot |

The release goal is graceful compatibility without mod-page dependency clutter: compatible mods should work when their prototypes are visible, absent mods should be skipped cleanly, and no compatibility mod should be required for this mod to load.

## Compatibility Model

- Generated technologies are created in `data-final-fixes.lua` so the mod can see most recipes, items, labs, science packs, and technologies created by other mods.
- Science packs are discovered from `data.raw.lab[*].inputs` and resolved through generic item prototype lookup.
- Science-pack productivity starts with the vanilla and Space Age target list, then appends active lab inputs so custom science packs can receive productivity effects when their recipes are visible.
- A generated technology must have at least one lab that accepts its complete science-pack set. If no lab accepts the full set, `mir-lab-incompatibility-policy` controls whether the mod tries the largest deterministic lab-compatible subset (`reduce`, default) or skips the technology (`skip`). If no subset exists, the stream is skipped and logged.
- `ips-require-space-gate` adds an end-game science unlock prerequisite only. `mir-science-pack-ingredient-policy` controls whether generated technologies keep their configured ingredients, add space science, add space and promethium science, add all official base and Space Age science packs, or add every active lab science pack including compatible modded packs.
- Recipe matching supports both `recipe.category` and Factorio 2.1 `recipe.categories`.
- Recipe-productivity generation skips recipe effects already owned by another infinite recipe-productivity technology. In Space Age this prevents parallel MIR technologies for vanilla `processing-unit-productivity`, `low-density-structure-productivity`, `plastic-bar-productivity`, and `rocket-fuel-productivity`.
- Hidden recipes and recycling recipes are skipped by default. Streams can opt in with `include_hidden` or `include_recycling`.
- Optional DLC-shaped streams declare concrete required prototypes instead of requiring a specific official mod by name.
- Cargo bay unloading distance research uses Factorio 2.1.8's `max-cargo-bay-unloading-distance` technology modifier, uses official base and Space Age science packs only, and is skipped unless Space Age is active and the `landing-pad-unloading-bay` prototypes exist.
- Cargo landing pad count research uses `cargo-landing-pad-count`, uses official base and Space Age science packs only, is disabled by default, requires the vanilla `rocket-silo` cargo landing pad unlock, and is skipped unless Space Age is active and the `cargo-landing-pad` prototype exists.
- Spoilage preservation and agricultural growth speed are implemented in `dev` as visible `nothing` technology effects plus bounded runtime behavior through the control-stage scripted technology manager.
- The release plan treats those scripted runtime features as `v2.1.0`-bound until manual save validation proves existing-stack behavior, research reversal, disabling, and multi-force behavior.
- Spoilage preservation changes the global spoil time modifier and recomputes on init, configuration change, research finish/reversal, and technology effects reset.
- Agricultural growth speed adjusts newly planted agricultural tower plants from the tower planting event and does not rescan existing farms in this first implementation slice.
- Mod-specific stream changes should live in `prototypes/compat/profiles.lua` instead of the base stream definitions.
- Compatibility cleanup that removes known competing technologies also removes dangling prerequisite references from remaining technologies.
- Generic competing recipe-productivity cleanup removes only known infinite technologies whose recipe-productivity effects are all covered by generated MIR effects. Finite upgrade chains from other mods are left alone unless a future integration models them explicitly.
- Release metadata declares optional ordering for official DLC mods and intentionally avoids third-party compatibility-mod dependencies. Third-party compatibility is opportunistic and based on the prototypes visible when this mod reaches `data-final-fixes.lua`.
- `mir-debug-generation-report` can be enabled to capture why each stream or base extension generated or skipped.
- `mir-debug-recipe-matches` can be enabled to capture matched recipe names per stream and duplicate recipe matches across streams.

## Future Overlap Policy

Future MIR features should treat overlapping native modifiers as compatibility-sensitive. If another mod already adds an infinite technology that modifies the same force statistic, MIR should prefer one of these behaviors:

- Skip or disable MIR's duplicate by default.
- Keep both only when an explicit setting allows overlapping infinite technologies.
- Report the overlap through diagnostics.

This is especially relevant for cargo landing pad count, cargo bay unloading distance, and any future native modifier or scripted-effect technology that other mods may also provide.

## Legacy Backport Model

The planned Factorio `2.0` legacy release is More Infinite Research `v1.9.0`, backported from the finished More Infinite Research `v2.1.0` Factorio `2.1` codebase.

Legacy should not be rebuilt commit-by-commit from v2.0.0 or v2.0.5. It should be the current MIR generator, diagnostics, recipe matching, science-pack handling, compatibility cleanup, docs structure, locale, and validation infrastructure with Factorio `2.1`-only surface area removed or guarded.

Legacy `info.json` must use Factorio `2.0` metadata:

```json
{
  "version": "1.9.0",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0",
    "? space-age"
  ]
}
```

Do not carry the Factorio `2.1.x` base or optional official DLC dependency floors into legacy unless a later Factorio `2.0` validation run proves a specific ordering requirement.

Known legacy exclusions until Factorio `2.0` validation proves otherwise:

- `research_cargo_bay_unloading_distance`
- `research_cargo_landing_pad_count`
- `max-cargo-bay-unloading-distance`
- `cargo-landing-pad-count`
- any scripted agriculture path that depends on unavailable agricultural tower events or entity fields
- any pump, pipeline, or Space Age logistics prototype field added after the Factorio `2.0` target

Keep these architecture pieces from the v2.1.0 source snapshot unless Factorio `2.0` validation proves a specific incompatibility: `data-final-fixes.lua` generation, lab-input science-pack discovery, lab incompatibility policy, science-pack ingredient policy, recipe matching, diagnostics, base-tech extension safety, opportunistic compatibility cleanup, validation/package parity tooling, docs structure, and locale structure.

Validation is branch-aware from `info.json`: Factorio `2.1` checks require cargo streams and the `2.1.8` dependency floor, while Factorio `2.0` checks reject Factorio `2.1` dependency floors, require those cargo modifier strings to be absent from direct-effect stream definitions, skip Factorio `2.1` cargo runtime fixtures, and expect the package to build as `more-infinite-research_1.9.0.zip`.

## Opportunistic Integrations

These integrations do not add mod-page dependencies. More Infinite Research handles them when their prototypes are already visible, and skips safely when they are absent:

- Advanced Solar HR (`Advanced-Electric-Revamped-v16`): advanced, elite, and ultimate solar panel/accumulator recipes are covered by the electric energy productivity tiers.
- Better Robots Extended (`Better_Robots_Extended`): competing infinite worker robot storage research is removed when `mir-prefer-this-mod-for-competing-techs` is enabled and MIR's `worker-robots-storage` base extension is enabled.
- OCs Ammo and Armor (`OCs_ammo_casting`): foundry, biochamber, and electromagnetic plant recipes that output covered ammunition, explosive, or armor component items are picked up by the existing output-based streams.
- OCs Stone Casting (`OCs_stone_casting`): foundry recipes that output covered stone, landfill, brick, wall, concrete, refined concrete, foundation, rail, gate, or furnace items are picked up by the existing output-based streams.
- Fluid Quality Imprinting (`fluid-quality-imprinting`): quality-imprinting recipes that output covered plate and intermediate items are picked up by the existing output-based streams.
- Plates n Circuit Productivity (`plates-n-circuit-productivity`): competing plate and circuit productivity technologies are removed when `mir-prefer-this-mod-for-competing-techs` is enabled.
- Custom science packs from mods such as Castra or PlanetLib-based planets are picked up opportunistically when they are active lab inputs and have visible recipes that output the pack item.

Large mod packs and utility mods such as Alien Biomes, Informatron, Jetpack, AAI, and Helmod usually do not need explicit recipe productivity support unless they add recipes for items covered by one of this mod's streams. When they do, output-based matching should pick up visible recipes automatically.

## Known Limits

- No mod can observe another mod's later `data-final-fixes.lua` mutations unless a user, modpack, or future targeted integration imposes a later load order.
- Lab validation prevents impossible research ingredients, but it cannot infer every overhaul mod's intended progression.
- Recipe productivity technologies remain bounded by Factorio's recipe productivity cap even when research levels are infinite.
- Vanilla Space Age productivity technologies remain authoritative for processing units, low density structures, plastic, and rocket fuel where they already own all matching recipes.
- Existing prototype IDs are kept stable unless a tested migration is provided. The v2.1.0-bound scripted runtime implementation adds control-stage storage under the More Infinite Research namespace.
- Runtime scripted features avoid per-tick scanning by default. If a future feature needs active scanning, it should be disabled by default, clearly labeled experimental, or split into a companion mod.
- Scripted technologies must document storage keys, recomputation triggers, reversal behavior, disabling behavior, and multi-force behavior before implementation.

## Required Manual Test Matrix

Run each case from a clean Factorio user data directory or with a controlled mod set:

1. Base game only.
2. Elevated Rails only.
3. Recycler only.
4. Quality enabled with its dependencies.
5. Base-only with `research_cargo_landing_pad_count` forced enabled, verifying the generated technology is skipped because Space Age is absent.
6. Space Age 2.1.8+ enabled, verifying cargo bay unloading distance research appears after the landing pad unloading bay unlock and cargo landing pad count remains disabled by default.
7. Space Age 2.1.8+ with `research_cargo_landing_pad_count` forced enabled, verifying the generated technology uses `cargo-landing-pad-count` and remains researchable.
8. Better Robots Extended enabled.
9. A fixture mod that adds a science pack as an ordinary `item` and adds it to a lab.
10. A fixture mod that adds a custom lab with a different science-pack input set.
11. A fixture mod that adds recipes in `data-final-fixes.lua`.
12. Existing save upgraded from the latest 1.x release.

Post-v2.0 scripted feature releases also require these named saves/scenarios:

1. Fresh Space Age save with no other mods.
2. Existing v2.0.0 More Infinite Research save upgraded to the candidate release.
3. Save with spoilable items already on belts, in chests, in labs, in rockets, and on platforms.
4. Save with multiple player forces.
5. Large Gleba farm with thousands of tower-owned plants.
6. Save with a scripted feature enabled, researched, then disabled.
7. Save with Maraxis-like duplicate cargo landing pad technology.
8. Save with custom science packs and custom labs.
9. Save without Space Age.
10. Factorio 2.0 legacy-branch subset save.

For each case, verify:

- Factorio reaches the main menu without prototype errors.
- Generated technologies have non-empty science-pack ingredients.
- At least one lab accepts each generated technology's full science-pack set.
- Base-only runs do not load direct DLC asset paths.
- Logs show skipped or reduced streams clearly and do not show stack traces.
- Vanilla weapon shooting speed effects follow the configured startup setting.

For named manual save scenarios and release-specific manual tests, see `docs/manual-test-plan.md`.

## Local Validation Harness

The repository includes local fixture mods under `fixtures/` and a runner at `scripts/Invoke-MIRValidation.ps1`.

Static checks only:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Runtime load check:

```powershell
$env:FACTORIO_BIN = "C:\path\to\factorio.exe"
.\scripts\Invoke-MIRValidation.ps1
```

Set `$env:FACTORIO_LOG` or pass `-FactorioLog` when the Factorio log is not at the default Windows user-data path.

The runtime check copies this repo and the fixture mods into isolated temporary user-data mod directories, adds test-only dependencies from the copied mod to the fixture mods for deterministic load order, writes fixture `mod-list.json` files, and asks Factorio to create saves. It is intentionally a load/prototype validation harness, not a gameplay test.

The runtime fixture run enables the generation diagnostics report in the copied mod and covers both lab incompatibility policies. The default `reduce` scenario asserts that science-pack productivity generated with the custom item-based fixture science pack included. The `skip` scenario forces the copied setting default to `skip` and asserts that the intentionally incompatible science-pack productivity stream is skipped instead of reduced. Additional runtime scenarios force the science-pack ingredient policies, require the end-game prerequisite gate, force-enable cargo landing pad count without Space Age to prove the stream skips on the Space Age mod gate, assert Space Age cargo logistics effect shape when cargo landing pad count is enabled, and add a fixture finite vanilla-chain level before MIR to prove existing levels are preserved while MIR extends after them. The expected Factorio log file is part of the validation evidence; if it is missing, runtime validation fails.

Static validation requires the committed release zip at `dist/<name>_<version>.zip` based on `info.json`. The package must use the matching `<name>_<version>/` root, contain matching `info.json` metadata, include locale, documentation, top-level data-stage and control-stage files, core prototype modules, match the repository contents for key source, documentation, and locale files, and avoid build, fixture, script, Git, and temporary/editor artifacts.

## Fixture Designs

### Item Science Pack Fixture

Create a local test mod that:

- Adds `mir-fixture-science-pack` as an `item`.
- Adds a recipe that produces `mir-fixture-science-pack`.
- Adds `mir-fixture-science-pack` to the vanilla lab input list.
- Unlocks that recipe from a technology.

Expected result: `mir-fixture-science-pack` can be discovered as a science pack, ordered after known vanilla packs, mapped to its unlock prerequisite when used, and included in science-pack productivity.

### Custom Lab Fixture

Create a local test mod that:

- Copies the vanilla lab prototype to `mir-custom-lab`.
- Sets `mir-custom-lab.inputs` to a deliberately smaller or different pack set.
- Optionally adds a second custom science pack that only this lab accepts.

Expected result: generated technologies are not allowed to combine science packs that no single lab accepts.

### Late Recipe Fixture

Create a local test mod that:

- Adds or mutates recipes in its own `data-final-fixes.lua`.
- Declares dependency ordering so More Infinite Research loads after it when testing positive capture.

Expected result: recipe streams can discover late recipes when load order makes those recipes visible, and the documented load-order limitation is visible when order is reversed.

### Science-Pack Productivity Assertion Fixture

Create a local test mod that:

- Depends on More Infinite Research and the item science-pack fixture.
- Runs after MIR in `data-final-fixes.lua`.
- Reads `recipe-prod-research_science_pack_productivity-1`.
- Fails loading if the fixture science-pack recipe is not present as a `change-recipe-productivity` effect.

Expected result: custom item-based science packs that are active lab inputs and have visible recipes receive science-pack productivity effects.

### Lab Skip Policy Assertion Fixture

Create a local test mod that:

- Depends on More Infinite Research, the custom lab fixture, and the item science-pack fixture.
- Runs after MIR in `data-final-fixes.lua`.
- Expects `mir-lab-incompatibility-policy = skip`.
- Fails loading if `recipe-prod-research_science_pack_productivity-1` still exists after MIR sees the deliberately incompatible full lab-input set.

Expected result: when the skip policy is active, MIR skips the incompatible science-pack productivity stream instead of reducing it.

## Release Checklist

- Run `.\scripts\Build-MIRPackage.ps1` to refresh the versioned zip in `dist/`.
- Run `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes` and confirm no old science-pack authority remains.
- Run `rg "icon_mipmaps" prototypes` and confirm generated icons do not add it.
- Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- Confirm `changelog.txt` uses Factorio's strict changelog format with 99-dash section separators.
- Confirm `info.json` declares `base >= 2.1.8` plus optional official DLC ordering dependencies only.
- Confirm package validation reports the expected root, matching metadata, included locale/docs, and no forbidden artifacts.
- Confirm package validation reports source, documentation, and locale parity with the repository.
- Confirm runtime fixture validation covers both the default `reduce` lab policy and forced `skip` lab policy.
- Confirm runtime fixture validation covers `configured`, `space`, `space-and-promethium`, `all-official`, and `all` science-pack ingredient policies, the end-game prerequisite gate, and the base-only cargo landing pad count skip.
- Confirm runtime fixture validation covers Space Age cargo logistics effect types, modifiers, costs, research times, prerequisites, and official science-pack ingredients.
- Confirm runtime fixture validation covers preserving an existing finite vanilla-chain level before adding MIR's generated infinite continuation.
- Load Factorio with the manual matrix above.
- Confirm `changelog.txt` has the release version and date.
