# M.I.R. Roadmap

Updated: 2026-06-29

This document is the v2.0.0 release checklist and follow-on roadmap. The baseline below reflects the current implementation state.

This document captures the Factorio 2.1 experimental compatibility review and turns it into an execution plan for the mod's v2.0.0 release and follow-on expansion work.

The critical interpretation is that "2.0" means the mod's v2.0.0 release, not a return to Factorio 2.0. The current target remains Factorio 2.1.

## Current Repository Baseline

- `info.json` declares mod version `2.0.0`, `factorio_version = "2.1"`, base `>= 2.1.8`, and optional Space Age `>= 2.1.8`; known compatibility mods are handled opportunistically without release metadata dependencies.
- `data.lua` loads only stable shared configuration and utility facades.
- `data-updates.lua` is reserved for pre-final compatibility hooks.
- `data-final-fixes.lua` runs compatibility cleanup, generated technology creation, base technology extensions, weapon speed adjustments, max-level enforcement, and diagnostics flushing.
- Science-pack handling is based on item prototype lookup plus active lab inputs, not `data.raw.tool`.
- Science-pack productivity dynamically adds active lab inputs to the target item list, so custom science packs can receive productivity effects when their recipes are visible.
- Generated technology ingredients are validated against complete lab input sets and reduced or skipped instead of creating unresearchable technologies.
- Recipe matching supports Factorio 2.1 `recipe.categories`, legacy `recipe.category`, stream match filters, and default hidden/recycling skips.
- Space Age-only direct-effect streams are gated by Space Age presence and explicit required prototypes where needed.
- Generated technology icons use deep-copied layered icons with Wube-style constant overlays.
- Vanilla weapon shooting speed mutation is controlled by the `mir-adjust-vanilla-weapon-speed-techs` startup setting.
- In-game locale warns that infinite recipe productivity remains subject to Factorio's recipe productivity cap.
- The repo has `changelog.txt`, compatibility/architecture docs, local fixture mods under `fixtures/`, and static/runtime validation scripts.

## Release Goal

Ship v2.0.0 as a compatibility-first Factorio 2.1 release that:

- Works with the 2.1.7+ science-pack change where science packs are ordinary items and lab/technology ingredients can use any item type.
- Generates technologies after other mods have had a chance to add recipes, items, labs, and science packs.
- Avoids unresearchable generated technologies caused by impossible lab ingredient combinations.
- Makes Space Age and Quality assumptions explicit and guarded.
- Uses reliable, layered technology icons without pre-rendered assets.
- Keeps invasive vanilla technology mutations behind settings.
- Creates a stable base for later balance, expansion, optimization, and mod compatibility work.

## Source Notes

This plan is based on the attached review notes and a current repo pass. The external Factorio assumptions to re-check before release are:

- Factorio 2.1.7 changed technology and lab ingredients to accept any item type and changed science packs to ordinary items: <https://forums.factorio.com/viewtopic.php?t=134095>
- Prototype data loading still runs in `data.lua`, then `data-updates.lua`, then `data-final-fixes.lua`: <https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html>
- Technology prototypes still support `icons`, with `icon` used only when `icons` is absent: <https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html>
- `IconData` supports layered icon properties including `floating`: <https://lua-api.factorio.com/latest/types/IconData.html>
- `ChangeRecipeProductivityModifier` has separate effect-row icon fields and `use_icon_overlay_constant`: <https://lua-api.factorio.com/latest/types/ChangeRecipeProductivityModifier.html>
- Recipe prototypes expose category/productivity fields relevant to matching and cap behavior: <https://lua-api.factorio.com/latest/prototypes/RecipePrototype.html>
- Wube's own technology constant helpers use 128px constant overlays with scale `0.5`, shift `{50, 50}`, and `floating = true`: <https://raw.githubusercontent.com/wube/factorio-data/master/core/lualib/util.lua>

## Non-Negotiable Release Blockers

### 1. Replace tool-based science-pack detection

Factorio 2.1.7 changed science packs from tool prototypes to ordinary items and broadened technology/lab ingredients to any item type. The mod must stop treating `data.raw.tool` as the science-pack authority.

Implementation requirements:

- Add a generic `U.item_prototype(name)` helper that checks all relevant item prototype buckets.
- Add `U.all_lab_inputs()` that discovers active research ingredients from `data.raw.lab[*].inputs`.
- Add `U.science_pack_exists(name)` that requires both an item prototype and presence in at least one lab input list.
- Replace every local `tool_exists` / `has_tool` science-pack check with the new helper.
- Update science-pack unlock discovery to iterate lab inputs, not `data.raw.tool`.
- Keep vanilla science-pack order as priority order only, not as the complete source of truth.
- Preserve deterministic ordering by appending modded lab inputs alphabetically after known vanilla packs.

### 2. Validate complete research ingredient sets against labs

Discovering a science pack is not enough. A technology can still become unresearchable if no lab accepts the full set of ingredients selected for that technology.

Implementation requirements:

- Add `U.any_lab_accepts_all(packs)`.
- Add `U.valid_research_ingredients(ingredients)`.
- Run validation after `U.pick_science_for_stream`.
- If the chosen set is invalid, degrade to the largest valid ordered subset or skip generation with a clear `log()` message.
- Do not silently create technologies that no lab can research.

### 3. Move generation later

Technology generation should no longer run in `data.lua`.

Preferred v2.0 structure:

```lua
-- data.lua
require("prototypes.config")
require("prototypes.util")
```

```lua
-- data-updates.lua
-- Keep empty unless a known compatibility patch must run before final scanning.
```

```lua
-- data-final-fixes.lua
require("prototypes.compat-better-robots")
require("prototypes.compat.competing-productivity").apply()
require("prototypes.tech-gen")
require("prototypes.base-tech-extensions")
require("prototypes.weapon-speed-adjustments")
require("prototypes.max-level-control")
require("prototypes.diagnostics").flush()
```

Rationale:

- `data-final-fixes.lua` gives this mod the best view of final recipes, items, labs, science packs, and technologies.
- The cost is that other mods have less opportunity to react after generated technologies exist.
- To keep the mod page clean, prefer opportunistic compatibility and safe skipping over compatibility metadata dependencies. Add explicit ordering only if a future integration cannot be made safe without it.

### 4. Implement 2.1 recipe matching

Recipe matching must support both old single-category recipes and 2.1 multi-category recipes.

Implementation requirements:

- Add `recipe_categories(recipe)` that returns `recipe.categories`, `{recipe.category}`, or `{"crafting"}`.
- Add category matching for `stream.match.categories`.
- Add recipe name matching for `stream.match.name_patterns`.
- Wire `matches_stream_recipe_filter(recipe_name, recipe, stream)` into `U.recipes_for_stream`.
- Honor `mode = "by_category_or_match"` or remove the config field. Do not leave it as inert configuration.
- Add a default skip for known bad categories such as `recycling`, with per-stream opt-in if needed.
- Do not treat `allow_productivity = false` as a hard filter by default. That can be a future setting, but it should not be an implicit compatibility change.

### 5. Guard Space Age and Quality assumptions

Space Age is optional, and in Factorio 2.1.7+ Quality can be disabled while Space Age remains enabled.

Implementation requirements:

- Gate `research_character_reach` with `requires_space_age = true` or give it base-game icon/science fallbacks.
- Gate `research_electric_shooting_speed` with `requires_space_age = true` or check that the `electric` ammo category and `tesla-weapons` technology exist.
- Ensure streams that reference Space Age science packs do not generate impossible ingredient sets in base-only runs.
- Test Space Age with Quality disabled.
- Avoid direct `__space-age__/...` icon paths unless the stream is gated or the path is guarded.

## Important But Not Release-Blocking

### Technology icon overlays

The right mechanism for the main technology tree icon remains `TechnologyPrototype.icons`.

Implementation requirements:

- Resolve the base icon from the actual source prototype.
- Deep-copy existing `icons` arrays before appending layers.
- Let `icon_tech` fall back to item/tool lookup so science pack icons resolve.
- Append a Wube-style constant overlay layer:

```lua
{
  icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
  icon_size = 128,
  scale = 0.5,
  shift = {50, 50},
  floating = true
}
```

- Drop `icon_mipmaps`; current icon docs do not require it for these generated layers.
- Keep technology tile overlays separate from effect-row icon overlays.
- Leave `effects[].icons` alone unless manually building effect icons. If a constant is already included in a custom effect icon, set `use_icon_overlay_constant = false` to avoid a double overlay.

Recommended overlay map:

- `change-recipe-productivity`: `constant-recipe-productivity.png`
- crafting speed: `constant-speed.png`
- gun/weapon shooting speed: `constant-speed.png`
- character movement speed: `constant-movement-speed.png`
- mining speed: `constant-mining.png`
- inventory/trash/capacity-like bonuses: `constant-capacity.png`
- reach/build distance: `constant-range.png`
- braking force: `constant-braking-force.png`
- damage bonus: `constant-damage.png`

### Vanilla weapon speed mutation setting

The current weapon speed adjustment is broad because it mutates vanilla technology effects unconditionally.

Add a startup setting:

```text
mir-adjust-vanilla-weapon-speed-techs:
  off
  only-when-dedicated-tech-enabled
  always
```

Recommended default: `only-when-dedicated-tech-enabled`.

### Productivity cap visibility

The README mentions the +300% engine cap, but the game UI should also tell players.

Add locale text that explains:

- Recipe productivity researches are infinite by design.
- Factorio's maximum recipe productivity cap still applies.
- Additional levels can eventually have no practical effect for capped recipes.

Do not force an automatic cap by default. A future setting can optionally stop generating or cap recipe-productivity levels at the effective cap.

### Prototype naming and migrations

Current generated names use:

```text
recipe-prod-<stream-key>-1
```

That is acceptable for recipe productivity but awkward for non-recipe effects.

Decision needed before broad public v2.0 adoption:

- Compatibility-first: keep existing prototype names and improve locale, icons, settings, and grouping.
- Breaking cleanup: rename to `mir-*` names and add migrations for existing saves.

Recommendation: keep names stable for v2.0.0 unless current installed usage is low enough to justify migrations immediately.

### Packaging and maintenance

Add:

- `changelog.txt`
- `migrations/` if prototype IDs are renamed or save-state transitions are needed
- `docs/compatibility.md`
- Small test mods or documented fixtures for lab/science-pack/late-recipe compatibility

## Execution Ladder

### Phase 0: Freeze and audit

Purpose: avoid accidental broad rewrites while fixing release blockers.

Tasks:

- Confirm whether prototype IDs will be stable for v2.0.0.
- Confirm whether generation should move to `data-final-fixes.lua` now.
- Snapshot generated technology names before changing behavior.
- Review all `data.raw.tool` references and local helpers.

Acceptance:

- Every affected file is identified.
- No implementation begins with an unresolved prototype-renaming decision.

### Phase 1: Science-pack compatibility core

Purpose: make the mod correct for Factorio 2.1.7+.

Tasks:

- Add item prototype discovery to `prototypes/util.lua`.
- Add lab input discovery.
- Add ordered science-pack discovery using vanilla order plus sorted modded extras.
- Replace `PACKS_ALL` usage where it represents complete truth.
- Replace all `tool_exists` usage in science-pack selection and base tech extension ingredient resolution.
- Rebuild science-pack unlock cache from lab inputs.

Acceptance:

- `rg "data.raw.tool|tool_exists|has_tool" prototypes` shows no science-pack authority use.
- Base-only and Space Age runs can build technology ingredients without empty or stale science-pack assumptions.

### Phase 2: Lab-combination validation

Purpose: prevent unresearchable generated technologies.

Tasks:

- Add helpers to check whether a lab accepts every selected science pack.
- Validate generated technology ingredients after selection.
- Degrade invalid pack sets to valid subsets where deterministic and sensible.
- Skip with explicit logs where no valid subset is possible.

Acceptance:

- A custom lab test can prove that the mod does not combine packs across incompatible labs.
- Log messages identify skipped or degraded streams.

### Phase 3: Stage move and generation ordering

Purpose: see late recipes/items/labs before generating technologies.

Tasks:

- Remove `require("prototypes.tech-gen")` from `data.lua`.
- Create `data-final-fixes.lua`.
- Move generation and final patches into the final-fixes order.
- Keep `data-updates.lua` minimal unless a pre-final compatibility hook is needed.

Acceptance:

- Late-added recipes from a test mod are visible to generation when load order allows.
- Generated techs still receive base extension handling, weapon adjustment handling, and max-level control in the intended order.

### Phase 4: Recipe matching upgrade

Purpose: make config-driven recipe matching real.

Tasks:

- Implement old/new category normalization.
- Implement category and recipe-name matching from `stream.match`.
- Integrate `mode = "by_category_or_match"`.
- Add hidden/recycling skip behavior with stream-level overrides.

Acceptance:

- `research_breeding` can match biochamber/cultivation/culture recipes even when output matching alone is not enough.
- Existing item-output based streams still produce the same or intentionally improved recipe sets.

### Phase 5: Space Age and Quality hardening

Purpose: make optional expansion prototypes and Quality assumptions safe.

Tasks:

- Gate or fallback Space Age icon paths.
- Gate Space Age-only ammo categories, technologies, items, and science packs.
- Audit Quality items/modules when Quality is disabled.
- Ensure missing optional prototypes cause skips, not load failures.

Acceptance:

- Base-only loads without Space Age paths.
- Space Age loads with Quality disabled.
- Electric shooting speed does not generate unless its prerequisites actually exist.

### Phase 6: Icon system cleanup

Purpose: make generated technologies visually consistent without custom PNGs.

Tasks:

- Centralize icon deep-copy logic.
- Resolve base icons from technology first, then item/tool-like prototypes.
- Append technology constant overlays using canonical 128px, scale `0.5`, shift `{50, 50}`, `floating = true`.
- Remove `icon_mipmaps` from generated icon layers.
- Add explicit per-stream `overlay` overrides where inference is wrong.

Acceptance:

- Science pack productivity uses science pack base icons rather than falling back to mining productivity.
- Layered base icons are preserved.
- No borrowed prototype icon tables are mutated.

### Phase 7: Settings and player-facing clarity

Purpose: reduce surprise and make tradeoffs visible.

Tasks:

- Add weapon speed mutation setting.
- Add locale for productivity cap warning.
- Decide whether to add an optional "stop at effective cap" startup setting.
- Refresh README to match v2.0 behavior.

Acceptance:

- Vanilla weapon speed edits can be disabled.
- Players can see the productivity cap warning in-game.

### Phase 8: Packaging and release hygiene

Purpose: make v2.0 releasable and maintainable.

Tasks:

- Add `changelog.txt`.
- Add `docs/compatibility.md`.
- Add migrations only if prototype IDs change.
- Add a manual test matrix and fixtures.
- Package and load-test the mod zip.

Acceptance:

- Changelog has a v2.0.0 entry.
- Compatibility document states supported scenarios and known limits.
- Existing-save upgrade path is tested or explicitly documented.

## Test Matrix

Minimum v2.0 test matrix:

- Base game only.
- Space Age enabled.
- Space Age enabled with Quality disabled.
- Better Robots Extended enabled.
- A test mod adding a science pack as an ordinary `item`.
- A test mod adding a custom lab with a different input set.
- A test mod adding recipes in `data-final-fixes.lua`.
- Existing save upgraded from the latest 1.x release.

For each case, verify:

- The game reaches the main menu.
- Generated technologies have non-empty, valid ingredients.
- At least one lab accepts each generated technology's full ingredient set.
- Optional Space Age paths do not load when Space Age is absent.
- Logs identify skipped streams without stack traces.

## Longer-Term v2.x Expansion Plan

After v2.0.0 is stable, expand in deliberately separated tracks.

### v2.1: Compatibility and discovery

- Add compatibility profiles for major overhaul mods.
- Keep compatibility metadata dependencies out of release metadata unless a specific future integration proves impossible to handle safely without ordering.
- Add diagnostics that can log why each stream did or did not generate.
- Add a debug setting to print recipe matches per stream.
- Add a recipe metadata cache for large overhaul packs if recipe matching becomes a measurable data-stage cost.

### v2.2: Balance and progression

- Revisit cost curves per stream family.
- Separate recipe-productivity, player-bonus, combat-bonus, and logistics-bonus defaults.
- Add presets for conservative, standard, and megabase cost profiles.
- Consider cap-aware optional behavior for recipe productivity.

### v2.3: Expansion content

- Add more direct-effect infinite researches where they fit the mod identity.
- Add additional Space Age and overhaul recipe groups through compatibility profiles.
- Add per-mod stream packs rather than one large global config table.

### v2.4: UX and maintainability

- Improve technology ordering and grouping.
- Polish icons and localized descriptions across all supported languages.
- Add generated documentation of stream keys, default costs, effects, and dependencies.
- Refactor config into smaller files once behavior is stable.

### v2.5: Automated validation

- Build local scripted fixtures for data-stage validation.
- Add a small packaging script.
- Add a release checklist that confirms no stale generated artifacts or accidental local-only changes are included.

## Known Limitations

- No mod can see another mod's later `data-final-fixes.lua` mutations unless a user, modpack, or future targeted integration imposes a later load order.
- Lab validation prevents impossible ingredient sets, but it cannot infer a player's desired progression in every overhaul.
- Recipe productivity remains bounded by Factorio's maximum productivity cap even when the technology is infinite.
- Prototype renames require migrations and should not be mixed casually with compatibility fixes.

## Current v2.0.0 Release Status

Phases 1 through 8 are implemented for v2.0.0:

- Science-pack detection uses item/lab-input discovery.
- Science-pack productivity expands from active lab inputs instead of only the hard-coded vanilla and Space Age pack list.
- Lab ingredient combinations are validated before technology creation.
- Generation runs in `data-final-fixes.lua`.
- Recipe category matching, Space Age guards, icon overlays, player-facing settings, locale warnings, docs, fixtures, and packaging scripts are present.

The remaining release gate is validation, not planned implementation: static checks, locale checks, package validation, package creation, and the Factorio runtime load matrix should be green before publishing the v2.0.0 package.
