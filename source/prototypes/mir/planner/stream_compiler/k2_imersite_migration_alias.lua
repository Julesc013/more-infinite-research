-- Two hidden state carriers make the released Imersite identities movable
-- before control.lua can reconcile earned stages.  They use the ordinary
-- TechnologyDesign/create path and the same Imersite cost/time authority as
-- the visible stream.  They do not admit recipes or create a research path.
local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local prototype_lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local costs = require("prototypes.mir.planner.costs")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")
local diagnostics = require("prototypes.mir.planner.stream_compiler.diagnostics")
local D = require("prototypes.mir.report.diagnostics_sink")
local state_alias = require("prototypes.mir.domain.research.k2_imersite_staged_state")

local M = {}

M.legacy_technology = state_alias.legacy_technology
M.continuation_technology = state_alias.continuation_technology
M.early_holder_technology = state_alias.early.technology_name
M.continuation_holder_technology = state_alias.continuation.technology_name
M.powder_recipe = state_alias.powder_recipe

local function ingredient_name(ingredient)
  return ingredient and (ingredient.name or ingredient[1])
end

-- Research packs changed concrete prototype kind between Factorio targets.
-- The item abstraction preserves both F200 tool packs and F210 item packs;
-- lab membership still decides which inputs are a valid deterministic fallback.
local function research_ingredients_exist(ingredients)
  if type(ingredients) ~= "table" or #ingredients == 0 then return false end
  for _, ingredient in ipairs(ingredients) do
    if not prototype_lookup.item_prototype(ingredient_name(ingredient)) then return false end
  end
  return true
end

local function emitted_row(rows, technology_name)
  for _, row in ipairs(rows or {}) do
    if row.action == "emit" and row.technology_name == technology_name
        and type(row.fields) == "table" then
      return row
    end
  end
  return nil
end

local function visible_unit(row)
  local fields = row and row.fields
  if not fields or not research_ingredients_exist(fields.ingredients) then return nil end
  if fields.count == nil and fields.count_formula == nil then return nil end
  if type(fields.research_time) ~= "number" or fields.research_time <= 0 then return nil end
  return {
    ingredients = deepcopy(fields.ingredients),
    count = fields.count,
    count_formula = fields.count_formula,
    research_time = fields.research_time,
    cost_model = fields.cost_model,
    origin = "ordinary-emitted-row"
  }
end

local function fallback_ingredients()
  -- Science ingredients do not control the engine's retained fractional
  -- progress in the bounded native r10 mechanism check. This base pack is
  -- used only when the visible K2 row cannot supply an available unit; the
  -- resulting hidden carrier is never a player-admitted research path.
  if prototype_lookup.item_prototype("automation-science-pack") then
    return {{"automation-science-pack", 1}}
  end

  -- Overhauls can replace automation science. Select only an actual lab
  -- input from the already prepared science service; an arbitrary item could
  -- make an invalid research unit or reintroduce acquisition discovery.
  for _, name in ipairs(science_packs.pack_list_all()) do
    if prototype_lookup.item_prototype(name) then return {{name, 1}} end
  end
  return nil
end

local function configured_early_unit(streams, ordinary_rows)
  local ordinary = visible_unit(emitted_row(ordinary_rows, M.legacy_technology))
  if ordinary then return ordinary end
  local spec = streams and streams[state_alias.stream_key]
  local ingredients = fallback_ingredients()
  if type(spec) ~= "table" or not ingredients then return nil end
  local model = costs.model_for(state_alias.stream_key, spec, 1)
  local count_formula, count = model.count_formula, nil
  if target_line.feature_enabled("legacy_numeric_research_cost") then
    count, count_formula = math.ceil(model.base_cost), nil
  end
  return {
    ingredients = ingredients,
    count = count,
    count_formula = count_formula,
    research_time = costs.research_time_for(state_alias.stream_key, spec),
    cost_model = model,
    origin = "configured-hidden-fallback"
  }
end

local function configured_continuation_unit(streams, early, staged_rows)
  local ordinary = visible_unit(emitted_row(staged_rows, M.continuation_technology))
  if ordinary then return ordinary end
  local spec = streams and streams[state_alias.stream_key]
  if type(spec) ~= "table" or type(early) ~= "table" or type(early.cost_model) ~= "table" then
    return nil
  end
  local model = research_cost_model.new({
    anchor_level = 4,
    base_cost = research_cost_model.evaluate(early.cost_model, 4),
    linear_increment = costs.base_cost_for(state_alias.stream_key, spec),
    growth_factor = 1,
    provenance = {
      base_cost = "legacy-next-level-cost",
      linear_increment = "ips-cost-base-" .. state_alias.stream_key,
      growth_factor = "bounded-late-material-progression",
      anchor_level = "migration-state-carrier-continuation"
    }
  })
  local count_formula, count = model.count_formula, nil
  if target_line.feature_enabled("legacy_numeric_research_cost") then
    count, count_formula = math.ceil(model.base_cost), nil
  end
  return {
    ingredients = deepcopy(early.ingredients),
    count = count,
    count_formula = count_formula,
    research_time = early.research_time,
    cost_model = model,
    origin = "configured-continuation-fallback"
  }
end

local function holder_effects()
  -- Do not create invalid productivity effects outside a real K2 powder
  -- profile.  The JSON mapping has independently proven safe when both its
  -- source and target are absent.
  if data_raw.prototype("recipe", M.powder_recipe) then
    return {{type = "change-recipe-productivity", recipe = M.powder_recipe, change = 0.02}}
  end
  return nil
end

local function plan_holder(holder, effects, unit)
  local spec = {
    manifest_id = holder.manifest_id,
    technology_name = holder.technology_name,
    identity_state = "stable-unreleased",
    migration_policy = state_alias.migration_policy,
    icon_tech = "automation"
  }
  local fields = {
    localised_name = {"technology-name.more-infinite-research.recipe_productivity"},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    icons = nil,
    effects = deepcopy(effects),
    prerequisites = {},
    ingredients = deepcopy(unit.ingredients),
    count = unit.count,
    count_formula = unit.count_formula,
    cost_model = unit.cost_model,
    research_time = unit.research_time,
    max_level = "infinite",
    order = "zz[mir-migration-state]",
    level = holder == state_alias.continuation and 4 or 1,
    enabled = true,
    hidden = true,
    upgrade = false
  }
  if not state_alias.matches_planned_unit(unit, fields) then
    error("K2 Imersite migration holder no longer matches the normal configured unit: "
      .. holder.technology_name, 2)
  end
  return diagnostics.plan_row(holder.stream_key, spec, "emit", state_alias.reason,
    D.stream_fields(holder.stream_key, spec, "generated", state_alias.reason,
      fields.ingredients, fields.prerequisites, effects, "not-applicable", {
        compatibility_state = "k2-imersite-staged-v1",
        player_research = "false",
        predecessor_version = state_alias.predecessor_version,
        source_technology = holder.source_technology,
        configured_unit_origin = unit.origin
      }), {
      technology_name = holder.technology_name,
      fields = fields,
      planned_max_level = "infinite",
      stage_kind = state_alias.stage_kind,
      direct_effects = false
    })
end

function M.plan_rows(streams, ordinary_rows, staged_rows)
  -- F210 alone has this JSON lifecycle and reconciliation owner.  A carrier
  -- is materialized only where the K2 powder recipe exists.  In profiles with
  -- neither historical source nor target, Factorio 2.1.22 accepts the absent
  -- JSON map; this avoids making unavailable historical packs a load blocker.
  if target_line.factorio_version ~= "2.1"
      or not target_line.feature_enabled("scripted_techs")
      or not target_line.feature_enabled("productivity_family_adoption")
      or not data_raw.prototype("recipe", M.powder_recipe) then
    return {}
  end
  local effects = holder_effects()
  local early = configured_early_unit(streams, ordinary_rows)
  local continuation = early and configured_continuation_unit(streams, early, staged_rows) or nil
  if not effects or not early or not continuation then return {} end
  return {
    plan_holder(state_alias.early, effects, early),
    plan_holder(state_alias.continuation, effects, continuation)
  }
end

return M
