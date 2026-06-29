# Architecture

More Infinite Research is organized around a compatibility-first data-stage pipeline.

## Data Stage Flow

`data.lua` loads only stable shared configuration and utility facades.

`data-updates.lua` is intentionally reserved for compatibility hooks that must run before final recipe and lab scanning.

`data-final-fixes.lua` runs the actual generation pipeline:

1. Better Robots competing-tech cleanup.
2. Generated stream technology creation.
3. Known competing recipe-productivity cleanup based on actual generated MIR effects.
4. Base technology infinite extensions.
5. Vanilla weapon speed adjustment.
6. Max-level enforcement.
7. Optional diagnostics report flush.

This order gives the mod the best practical view of recipes, labs, science packs, and technologies created by other mods while still keeping this mod's final cleanup deterministic.

## Utility Modules

`prototypes/util.lua` is a facade kept for compatibility with existing call sites. Domain logic lives in focused modules:

- `prototypes/lib/prototype-lookup.lua`: item-like prototype lookup, technology existence, ammo-category existence, Space Age detection.
- `prototypes/lib/science-packs.lua`: lab-input discovery, science-pack existence, lab-compatible ingredient validation, science-pack unlock prerequisites, ordered pack lists.
- `prototypes/lib/recipe-matching.lua`: item-output matching, item-pattern expansion, recipe category matching, hidden/recycling filtering.
- `prototypes/lib/technology-icons.lua`: borrowed icon copying, technology/item icon fallback, Wube-style constant overlays.
- `prototypes/lib/deepcopy.lua`: shared fallback for data-stage deep copies.
- `prototypes/lib/table-utils.lua`: deterministic table-key ordering helpers.
- `prototypes/lib/technology-cleanup.lua`: technology removal with prerequisite reference cleanup.

Keep new domain behavior in these modules rather than growing `util.lua`.

## Stream Configuration

`prototypes/config.lua` exposes:

- `M.shared`
- `M.streams`

The stream table is assembled by `prototypes/streams/init.lua` from:

- `prototypes/streams/productivity.lua`
- `prototypes/streams/direct-effects.lua`

Future expansion should add more stream domain modules rather than returning to one large config file.

Generated recipe-productivity streams can set `dynamic_items_from_lab_inputs = true` when their target item set should include every active lab input discovered during `data-final-fixes.lua`. The science-pack productivity stream uses this so custom science packs can receive productivity effects without hard-coded mod dependencies. If a future dynamic stream uses top-level `items` without `groups`, those items are copied into the generated group before lab inputs are appended.

## Compatibility Profiles

`prototypes/compat/profiles.lua` is the dedicated home for mod-specific stream patches.

Use profiles when a compatibility rule is tied to a known mod being active. Use general stream config only for behavior that should apply to every mod set.

Profile patches should use append fields such as `append_items`, `append_item_patterns`, `append_recipe_patterns`, `append_exclude_recipe_patterns`, `append_exclude_ingredient_patterns`, and `append_groups` when extending existing stream arrays. Direct field assignment remains available for intentional overrides.

## Diagnostics

`mir-debug-generation-report` enables a structured log report. The report records generated and skipped streams/extensions with:

- key
- status
- reason
- science packs
- prerequisites
- effect count
- lab compatibility status
- icon source hint

Use this setting when triaging user reports. It is off by default to avoid noisy logs.

## Validation

Use `scripts/Invoke-MIRValidation.ps1 -StaticOnly` for static checks.

Use `scripts/Invoke-MIRValidation.ps1 -FactorioBin C:\path\to\factorio.exe` for a runtime fixture load test.

Use `scripts/Build-MIRPackage.ps1` to rebuild the release archive. Static validation checks the committed archive root, metadata, locale files, docs, and forbidden artifact paths.

Static package validation also compares key packaged source files against the repository copy so a stale zip with correct metadata is rejected.

The fixture mods under `fixtures/` test item-based science packs, custom labs, late recipe creation, and the post-MIR science-pack productivity assertion.
