# Compatibility and Validation

More Infinite Research v2.0.0 targets Factorio 2.1 and uses a compatibility-first data-stage model.

## Compatibility Model

- Generated technologies are created in `data-final-fixes.lua` so the mod can see most recipes, items, labs, science packs, and technologies created by other mods.
- Science packs are discovered from `data.raw.lab[*].inputs` and resolved through generic item prototype lookup.
- A generated technology must have at least one lab that accepts its complete science-pack set. If no lab accepts the full set, the mod tries the largest deterministic lab-compatible subset. If no subset exists, the stream is skipped and logged.
- Recipe matching supports both `recipe.category` and Factorio 2.1 `recipe.categories`.
- Hidden recipes and recycling recipes are skipped by default. Streams can opt in with `include_hidden` or `include_recycling`.
- Optional Space Age streams must either set `requires_space_age = true` or declare concrete required prototypes.
- Mod-specific stream changes should live in `prototypes/compat/profiles.lua` instead of the base stream definitions.
- `mir-debug-generation-report` can be enabled to capture why each stream or base extension generated or skipped.

## Known Limits

- No mod can observe another mod's later `data-final-fixes.lua` mutations unless dependency order puts it after that mod.
- Lab validation prevents impossible research ingredients, but it cannot infer every overhaul mod's intended progression.
- Recipe productivity technologies remain bounded by Factorio's recipe productivity cap even when research levels are infinite.
- Prototype IDs were kept stable for v2.0.0. No migration is currently required.

## Required Manual Test Matrix

Run each case from a clean Factorio user data directory or with a controlled mod set:

1. Base game only.
2. Space Age enabled.
3. Space Age enabled with Quality disabled.
4. Better Robots Extended enabled.
5. A fixture mod that adds a science pack as an ordinary `item` and adds it to a lab.
6. A fixture mod that adds a custom lab with a different science-pack input set.
7. A fixture mod that adds recipes in `data-final-fixes.lua`.
8. An existing save upgraded from the latest 1.x release.

For each case, verify:

- Factorio reaches the main menu without prototype errors.
- Generated technologies have non-empty science-pack ingredients.
- At least one lab accepts each generated technology's full science-pack set.
- Base-only runs do not load direct `__space-age__/...` paths.
- Logs show skipped or reduced streams clearly and do not show stack traces.
- Vanilla weapon shooting speed effects follow the configured startup setting.

## Local Validation Harness

The repository includes local fixture mods under `dev-fixtures/` and a runner at `scripts/Invoke-MIRValidation.ps1`.

Static checks only:

```powershell
.\scripts\Invoke-MIRValidation.ps1 -StaticOnly
```

Runtime load check:

```powershell
$env:FACTORIO_BIN = "C:\path\to\factorio.exe"
.\scripts\Invoke-MIRValidation.ps1
```

The runtime check copies this repo and the fixture mods into a temporary user-data mod directory, writes a fixture `mod-list.json`, and asks Factorio to create a save. It is intentionally a load/prototype validation harness, not a gameplay test.

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
- Run `git diff --check`.
- Parse `info.json` as JSON.
- Load Factorio with the manual matrix above.
- Confirm `changelog.txt` has the release version and date.
