local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local material_progression = require("prototypes.mir.families.material_progression")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")
local costs = require("prototypes.mir.planner.costs")
local planner_prerequisites = require("prototypes.mir.planner.prerequisites")
local planner_science = require("prototypes.mir.planner.science")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local diagnostics = require("prototypes.mir.planner.stream_compiler.diagnostics")

local M = {}
local plan_row = diagnostics.plan_row
local skip_row = diagnostics.skip_row
local D = require("prototypes.mir.report.diagnostics_sink")
local function contains_ingredient(ingredients, name)
  for _, ingredient in ipairs(ingredients or {}) do
    if (ingredient.name or ingredient[1]) == name then return true end
  end
  return false
end

local function late_science_for(key, early_ingredients)
  -- First useful continuation should not wait for the final science pack.
  local candidates = {}
  for _, pack in ipairs({"space-science-pack", "utility-science-pack", "production-science-pack"}) do
    table.insert(candidates, pack)
  end
  local ordinary_candidate_count = #candidates
  local end_game = science_packs.end_game_science_pack()
  if end_game then table.insert(candidates, end_game) end
  local inherited_names = {}
  for _, ingredient in ipairs(early_ingredients or {}) do
    inherited_names[#inherited_names + 1] = ingredient.name or ingredient[1]
  end
  local function progression_for(names)
    local out = {}
    local inferred = science_packs.mod_progression_packs_for(names)
    for _, pack in ipairs(inferred) do out[pack] = true end
    -- An unfamiliar pack can imply an ordinary pack through its real unlock
    -- technology. Include that ordinary pack's existing progression too.
    for _, pack in ipairs(science_packs.official_progression_packs_for(inferred)) do out[pack] = true end
    for _, pack in ipairs(names) do out[pack] = true end
    return out
  end
  -- Reuse the existing official and concrete mod prerequisite policy. A
  -- science already implied by the inherited set is not a later frontier.
  -- Keep the established space-first preference for genuinely later packs.
  local inherited_progression = progression_for(inherited_names)
  local function additional_frontier(late)
    if not late or inherited_progression[late] or not science_packs.science_pack_exists(late) then return nil end
    local status = science_packs.pack_production_status(late)
    if status == "initial" or status == "research" or status == "non-recipe" then
      local requested = deepcopy(early_ingredients)
      table.insert(requested, {late, 1})
      local ingredients, lab_status, decision = planner_science.ingredients_for_selected(key, requested)
      if ingredients and contains_ingredient(ingredients, late) then
        return ingredients, lab_status, decision, late
      end
    end
  end
  for index, late in ipairs(candidates) do
    if index <= ordinary_candidate_count then
      local ingredients, lab_status, decision, frontier = additional_frontier(late)
      if ingredients then return ingredients, lab_status, decision, frontier end
    end
  end
  -- A material that already needs the highest reachable pack still has
  -- useful recipe headroom. Prefer that proven tier to imposing a distinct
  -- final pack on the first useful continuation.
  local inherited_frontiers, progression = {}, {}
  for _, pack in ipairs(inherited_names) do
    progression[pack] = progression_for({pack})
    for _, late in ipairs(candidates) do
      if progression[pack][late] then inherited_frontiers[pack] = true; break end
    end
  end
  local fallback_candidates = deepcopy(candidates)
  for _, pack in ipairs(inherited_names) do fallback_candidates[#fallback_candidates + 1] = pack end
  local considered = {}
  for _, late in ipairs(fallback_candidates) do
    local dominated = false
    if inherited_frontiers[late] then
      for other in pairs(inherited_frontiers) do
        if other ~= late and progression[other][late] and not progression[late][other] then
          dominated = true; break
        end
      end
    end
    if late and not considered[late] and inherited_frontiers[late] and not dominated
        and contains_ingredient(early_ingredients, late)
        and science_packs.science_pack_exists(late) then
      considered[late] = true
      local status = science_packs.pack_production_status(late)
      if status == "initial" or status == "research" or status == "non-recipe" then
        local ingredients, lab_status, decision = planner_science.ingredients_for_selected(
          key, deepcopy(early_ingredients))
        if ingredients and contains_ingredient(ingredients, late) then
          return ingredients, lab_status, decision, late
        end
      end
    end
  end
  -- Preserve the existing end-game escape when the profile has neither a
  -- usable ordinary later pack nor an established inherited late frontier.
  return additional_frontier(end_game)
end

function M.plan(legacy_row)
  local spec = legacy_row and legacy_row.spec
  local staged = spec and spec.staged_progression
  if not staged or legacy_row.action ~= "emit" or legacy_row.direct_effects then return nil end
  local key = legacy_row.stream_key
  local valid, reason = material_progression.validate(key, staged)
  if not valid then error("Invalid material continuation " .. key .. ": " .. reason, 2) end
  if legacy_row.technology_name ~= staged.legacy.technology_name then
    error("Material continuation legacy owner changed for " .. key, 2)
  end

  local stage_key = key .. "__continuation"
  local stage_spec = deepcopy(spec)
  stage_spec.manifest_id = staged.continuation.technology_name
  stage_spec.technology_name = staged.continuation.technology_name
  stage_spec.identity_state = "stable-unreleased"
  local maximum, cap_reason = material_progression.highest_useful_level(
    legacy_row.fields.effects,
    function(recipe_name) return data_raw.prototype("recipe", recipe_name) end,
    costs.max_level_for(key, spec)
  )
  if not maximum then
    return skip_row(stage_key, stage_spec, cap_reason)
  end

  local ingredients, lab_status, science_decision, late_pack = late_science_for(
    key, legacy_row.fields.ingredients)
  if not ingredients then
    return skip_row(stage_key, stage_spec, "no_reachable_late_science_frontier")
  end
  local prerequisites, prerequisite_reason = planner_prerequisites.build_for(key, ingredients)
  if prerequisite_reason then
    return skip_row(stage_key, stage_spec, prerequisite_reason, ingredients)
  end
  table.insert(prerequisites, staged.legacy.technology_name)
  table.sort(prerequisites)

  local previous_cost = legacy_row.fields.cost_model
  local ok, continuation_cost = pcall(function()
    return research_cost_model.new({
      anchor_level = staged.continuation.first_level,
      base_cost = research_cost_model.evaluate(previous_cost, staged.continuation.first_level),
      linear_increment = costs.base_cost_for(key, spec),
      growth_factor = 1,
      provenance = {
        base_cost = "legacy-next-level-cost",
        linear_increment = "ips-cost-base-" .. key,
        growth_factor = "bounded-late-material-progression",
        anchor_level = "material-continuation-first-level"
      }
    })
  end)
  if not ok then return skip_row(stage_key, stage_spec, "continuation_cost_out_of_bounds") end

  local fields = deepcopy(legacy_row.fields)
  fields.prerequisites = prerequisites
  fields.ingredients = ingredients
  fields.count_formula = continuation_cost.count_formula
  fields.cost_model = continuation_cost
  fields.max_level = target_line.feature_enabled("scripted_techs")
    and target_line.mod_data_supported() and "infinite" or maximum
  fields.level = staged.continuation.first_level
  return plan_row(stage_key, stage_spec, "emit", "material_continuation",
    D.stream_fields(stage_key, stage_spec, "generated", "recipe_productivity", ingredients,
      prerequisites, fields.effects, lab_status,
      {late_science_pack = late_pack, legacy_technology = staged.legacy.technology_name}), {
      technology_name = staged.continuation.technology_name,
      fields = fields,
      planned_max_level = maximum,
      configured_stream_key = key,
      staged_parent_technology = staged.legacy.technology_name,
      staged_parent_stream_key = key,
      stage_kind = "material-continuation",
      direct_effects = false,
      science_phase_policy = science_decision
    })
end

return M
