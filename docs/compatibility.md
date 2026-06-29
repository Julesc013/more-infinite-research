# Compatibility and Validation

More Infinite Research v2.0.0 targets Factorio 2.1 and uses a compatibility-first data-stage model.

The release goal is graceful compatibility without mod-page dependency clutter: compatible mods should work when their prototypes are visible, absent mods should be skipped cleanly, and no compatibility mod should be required for this mod to load.

## Compatibility Model

- Generated technologies are created in `data-final-fixes.lua` so the mod can see most recipes, items, labs, science packs, and technologies created by other mods.
- Science packs are discovered from `data.raw.lab[*].inputs` and resolved through generic item prototype lookup.
- Science-pack productivity starts with the vanilla and Space Age target list, then appends active lab inputs so custom science packs can receive productivity effects when their recipes are visible.
- A generated technology must have at least one lab that accepts its complete science-pack set. If no lab accepts the full set, `mir-lab-incompatibility-policy` controls whether the mod tries the largest deterministic lab-compatible subset (`reduce`, default) or skips the technology (`skip`). If no subset exists, the stream is skipped and logged.
- Recipe matching supports both `recipe.category` and Factorio 2.1 `recipe.categories`.
- Hidden recipes and recycling recipes are skipped by default. Streams can opt in with `include_hidden` or `include_recycling`.
- Optional DLC-shaped streams declare concrete required prototypes instead of requiring a specific official mod by name.
- Cargo bay unloading distance research uses Factorio 2.1.8's `max-cargo-bay-unloading-distance` technology modifier and is skipped without the `landing-pad-unloading-bay` prototypes.
- Cargo landing pad count research uses `cargo-landing-pad-count`, is disabled by default, and is skipped without the `cargo-landing-pad` prototype.
- Mod-specific stream changes should live in `prototypes/compat/profiles.lua` instead of the base stream definitions.
- Compatibility cleanup that removes known competing technologies also removes dangling prerequisite references from remaining technologies.
- Generic competing recipe-productivity cleanup removes only known infinite technologies whose recipe-productivity effects are all covered by generated MIR effects. Finite upgrade chains from other mods are left alone unless a future integration models them explicitly.
- Release metadata declares optional ordering for official DLC mods and intentionally avoids third-party compatibility-mod dependencies. Third-party compatibility is opportunistic and based on the prototypes visible when this mod reaches `data-final-fixes.lua`.
- `mir-debug-generation-report` can be enabled to capture why each stream or base extension generated or skipped.
- `mir-debug-recipe-matches` can be enabled to capture matched recipe names per stream and duplicate recipe matches across streams.

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
- Existing prototype IDs were kept stable for v2.0.0. No migration is currently required.

## Required Manual Test Matrix

Run each case from a clean Factorio user data directory or with a controlled mod set:

1. Base game only.
2. Elevated Rails only.
3. Recycler only.
4. Quality enabled with its dependencies.
5. Space Age 2.1.8+ enabled, verifying cargo bay unloading distance research appears after the landing pad unloading bay unlock and cargo landing pad count remains disabled by default.
6. Space Age 2.1.8+ with `research_cargo_landing_pad_count` forced enabled, verifying the generated technology uses `cargo-landing-pad-count` and remains researchable.
7. Better Robots Extended enabled.
8. A fixture mod that adds a science pack as an ordinary `item` and adds it to a lab.
9. A fixture mod that adds a custom lab with a different science-pack input set.
10. A fixture mod that adds recipes in `data-final-fixes.lua`.
11. An existing save upgraded from the latest 1.x release.

For each case, verify:

- Factorio reaches the main menu without prototype errors.
- Generated technologies have non-empty science-pack ingredients.
- At least one lab accepts each generated technology's full science-pack set.
- Base-only runs do not load direct DLC asset paths.
- Logs show skipped or reduced streams clearly and do not show stack traces.
- Vanilla weapon shooting speed effects follow the configured startup setting.

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

The runtime fixture run enables the generation diagnostics report in the copied mod and covers both lab incompatibility policies. The default `reduce` scenario asserts that science-pack productivity generated with the custom item-based fixture science pack included. The `skip` scenario forces the copied setting default to `skip` and asserts that the intentionally incompatible science-pack productivity stream is skipped instead of reduced. The expected Factorio log file is part of the validation evidence; if it is missing, runtime validation fails.

Static validation requires the committed release zip at `dist/more-infinite-research_2.0.0.zip`. The package must use the `more-infinite-research_2.0.0/` root, contain matching `info.json` metadata, include locale, documentation, top-level data-stage files, and core prototype modules, match the repository contents for key source, documentation, and locale files, and avoid build, fixture, script, Git, and temporary/editor artifacts.

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

- Run `.\scripts\Build-MIRPackage.ps1` to refresh `dist/more-infinite-research_2.0.0.zip`.
- Run `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes` and confirm no old science-pack authority remains.
- Run `rg "icon_mipmaps" prototypes` and confirm generated icons do not add it.
- Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- Confirm `changelog.txt` uses Factorio's strict changelog format with 99-dash section separators.
- Confirm `info.json` declares `base >= 2.1.8` plus optional official DLC ordering dependencies only.
- Confirm package validation reports the expected root, matching metadata, included locale/docs, and no forbidden artifacts.
- Confirm package validation reports source, documentation, and locale parity with the repository.
- Confirm runtime fixture validation covers both the default `reduce` lab policy and forced `skip` lab policy.
- Load Factorio with the manual matrix above.
- Confirm `changelog.txt` has the release version and date.
