# Compatibility and Validation

More Infinite Research v2.0.0 targets Factorio 2.1 and uses a compatibility-first data-stage model.

## Compatibility Model

- Generated technologies are created in `data-final-fixes.lua` so the mod can see most recipes, items, labs, science packs, and technologies created by other mods.
- Science packs are discovered from `data.raw.lab[*].inputs` and resolved through generic item prototype lookup.
- A generated technology must have at least one lab that accepts its complete science-pack set. If no lab accepts the full set, the mod tries the largest deterministic lab-compatible subset. If no subset exists, the stream is skipped and logged.
- Recipe matching supports both `recipe.category` and Factorio 2.1 `recipe.categories`.
- Hidden recipes and recycling recipes are skipped by default. Streams can opt in with `include_hidden` or `include_recycling`.
- Optional Space Age streams must either set `requires_space_age = true` or declare concrete required prototypes.
- Space Age cargo bay unloading distance research uses Factorio 2.1.8's `max-cargo-bay-unloading-distance` technology modifier and is skipped without Space Age or the `landing-pad-unloading-bay` prototypes.
- Space Age cargo landing pad count research uses `cargo-landing-pad-count`, is disabled by default, and is skipped without Space Age or the `cargo-landing-pad` prototype.
- Mod-specific stream changes should live in `prototypes/compat/profiles.lua` instead of the base stream definitions.
- Release metadata intentionally avoids compatibility-mod dependencies beyond optional Space Age. Compatibility is opportunistic and based on the prototypes visible when this mod reaches `data-final-fixes.lua`.
- `mir-debug-generation-report` can be enabled to capture why each stream or base extension generated or skipped.

## Opportunistic Integrations

These integrations do not add mod-page dependencies. More Infinite Research handles them when their prototypes are already visible, and skips safely when they are absent:

- Advanced Solar HR (`Advanced-Electric-Revamped-v16`): advanced, elite, and ultimate solar panel/accumulator recipes are covered by the electric energy productivity tiers.
- Better Robots Extended (`Better_Robots_Extended`): competing infinite worker robot storage research is removed when `mir-prefer-this-mod-for-competing-techs` is enabled.
- OCs Ammo and Armor (`OCs_ammo_casting`): foundry, biochamber, and electromagnetic plant recipes that output covered ammunition, explosive, or armor component items are picked up by the existing output-based streams.
- OCs Stone Casting (`OCs_stone_casting`): foundry recipes that output covered stone, landfill, brick, wall, concrete, refined concrete, foundation, rail, gate, or furnace items are picked up by the existing output-based streams.
- Fluid Quality Imprinting (`fluid-quality-imprinting`): quality-imprinting recipes that output covered plate and intermediate items are picked up by the existing output-based streams.
- Plates n Circuit Productivity (`plates-n-circuit-productivity`): competing plate and circuit productivity technologies are removed when `mir-prefer-this-mod-for-competing-techs` is enabled.

Large mod packs and utility mods such as Alien Biomes, Informatron, Jetpack, AAI, and Helmod usually do not need explicit recipe productivity support unless they add recipes for items covered by one of this mod's streams. When they do, output-based matching should pick up visible recipes automatically.

## Known Limits

- No mod can observe another mod's later `data-final-fixes.lua` mutations unless a user, modpack, or future targeted integration imposes a later load order.
- Lab validation prevents impossible research ingredients, but it cannot infer every overhaul mod's intended progression.
- Recipe productivity technologies remain bounded by Factorio's recipe productivity cap even when research levels are infinite.
- Existing prototype IDs were kept stable for v2.0.0. No migration is currently required.

## Required Manual Test Matrix

Run each case from a clean Factorio user data directory or with a controlled mod set:

1. Base game only.
2. Space Age enabled.
3. Space Age 2.1.8+ enabled, verifying cargo bay unloading distance research appears after the landing pad unloading bay unlock and cargo landing pad count remains disabled by default.
4. Space Age 2.1.8+ with `research_cargo_landing_pad_count` forced enabled, verifying the generated technology uses `cargo-landing-pad-count` and remains researchable.
5. Space Age enabled with Quality disabled.
6. Better Robots Extended enabled.
7. A fixture mod that adds a science pack as an ordinary `item` and adds it to a lab.
8. A fixture mod that adds a custom lab with a different science-pack input set.
9. A fixture mod that adds recipes in `data-final-fixes.lua`.
10. An existing save upgraded from the latest 1.x release.

For each case, verify:

- Factorio reaches the main menu without prototype errors.
- Generated technologies have non-empty science-pack ingredients.
- At least one lab accepts each generated technology's full science-pack set.
- Base-only runs do not load direct `__space-age__/...` paths.
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

The runtime check copies this repo and the fixture mods into a temporary user-data mod directory, adds test-only dependencies from the copied mod to the fixture mods for deterministic load order, writes a fixture `mod-list.json`, and asks Factorio to create a save. It is intentionally a load/prototype validation harness, not a gameplay test.

## Fixture Designs

### Item Science Pack Fixture

Create a local test mod that:

- Adds `mir-test-science-pack` as an `item`.
- Adds a recipe that produces `mir-test-science-pack`.
- Adds `mir-test-science-pack` to the vanilla lab input list.
- Unlocks that recipe from a technology.

Expected result: `mir-test-science-pack` can be discovered as a science pack, ordered after known vanilla packs, and mapped to its unlock prerequisite when used.

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

## Release Checklist

- Run `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes` and confirm no old science-pack authority remains.
- Run `rg "icon_mipmaps" prototypes` and confirm generated icons do not add it.
- Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- Confirm `info.json` declares only `base >= 2.1.8` and optional `space-age >= 2.1.8` dependencies.
- Load Factorio with the manual matrix above.
- Confirm `changelog.txt` has the release version and date.
