# Architecture

More Infinite Research is organized around a compatibility-first data-stage pipeline.

## Data Stage Flow

`data.lua` loads only stable shared configuration and utility facades.

`data-updates.lua` is intentionally reserved for compatibility hooks that must run before final recipe and lab scanning.

`data-final-fixes.lua` runs the actual generation pipeline:

1. Better Robots competing-tech cleanup.
2. Generated stream technology creation.
3. Base technology infinite extensions.
4. Vanilla weapon speed adjustment.
5. Max-level enforcement.
6. Optional diagnostics report flush.

This order gives the mod the best practical view of recipes, labs, science packs, and technologies created by other mods while still keeping this mod's final cleanup deterministic.

## Utility Modules

`prototypes/util.lua` is a facade kept for compatibility with existing call sites. Domain logic lives in focused modules:

- `prototypes/lib/prototype-lookup.lua`: item-like prototype lookup, technology existence, ammo-category existence, Space Age detection.
- `prototypes/lib/science-packs.lua`: lab-input discovery, science-pack existence, lab-compatible ingredient validation, science-pack unlock prerequisites, ordered pack lists.
- `prototypes/lib/recipe-matching.lua`: item-output matching, item-pattern expansion, recipe category matching, hidden/recycling filtering.
- `prototypes/lib/technology-icons.lua`: borrowed icon copying, technology/item icon fallback, Wube-style constant overlays.
- `prototypes/lib/deepcopy.lua`: shared fallback for data-stage deep copies.

Keep new domain behavior in these modules rather than growing `util.lua`.

## Stream Configuration

`prototypes/config.lua` exposes:

- `M.shared`
- `M.streams`

The stream table is assembled by `prototypes/streams/init.lua` from:

- `prototypes/streams/productivity.lua`
- `prototypes/streams/direct-effects.lua`

Future expansion should add more stream domain modules rather than returning to one large config file.

## Compatibility Profiles

`prototypes/compat/profiles.lua` is the dedicated home for mod-specific stream patches.

Use profiles when a compatibility rule is tied to a known mod being active. Use general stream config only for behavior that should apply to every mod set.

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

The fixture mods under `fixtures/` test item-based science packs, custom labs, and late recipe creation.
