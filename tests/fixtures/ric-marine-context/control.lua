-- Full installed context observation; no research grant, recipe/force mutation,
-- native compatibility verdict or substitution for an earned-state scenario.
local RECIPE = "ric-carbonise-marine-biomass"
local TECHNOLOGY = "recipe-prod-research_material_ric_coke-1"
local function fail(message) error("[mir5-ric-context] " .. message) end

local function typed(rows)
  local result = {}
  for _, row in pairs(rows or {}) do
    result[#result + 1] = {
      type=row.type, name=row.name, amount=row.amount,
      amount_min=row.amount_min, amount_max=row.amount_max, probability=row.probability,
    }
  end
  table.sort(result, function(a, b) return a.type .. ":" .. a.name < b.type .. ":" .. b.name end)
  return result
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["real-industrial-chemistry"] ~= "0.35.8" then
    fail("selected engine/upstream version differs")
  end
  if settings.startup["ric-world-mode"].value ~= "marine"
      or settings.startup["ric-progression-mode"].value ~= "nauvis-only" then
    fail("selected world/progression mode differs")
  end
  if script.active_mods["space-age"] then fail("nauvis-only control unexpectedly includes Space Age") end
  local force = game.forces.player
  local prototype = prototypes.recipe[RECIPE]
  local recipe = force and force.recipes[RECIPE]
  if not prototype or not recipe then fail("native Marine recipe absent") end
  local mir_version = script.active_mods["more-infinite-research"]
  local technology = force.technologies[TECHNOLOGY]
  if not mir_version and technology then fail("MIR owner present in the upstream control") end
  local researched
  if technology then researched = technology.researched end
  local effects = {}
  if technology then
    for _, effect in pairs(technology.prototype.effects or {}) do
      if effect.type == "change-recipe-productivity" then
        effects[#effects + 1] = {type=effect.type, recipe=effect.recipe, change=effect.change}
      end
    end
  end
  local active = {}
  for name, version in pairs(script.active_mods) do active[#active + 1] = {name=name, version=version} end
  table.sort(active, function(a, b) return a.name < b.name end)
  log("[MIR5_RIC_CONTEXT] RESULT " .. helpers.table_to_json({
    case="ric-marine-context", stage="init", status="passed",
    qualification="installed-context-and-emission-observation-only",
    base_version=script.active_mods.base, ric_version=script.active_mods["real-industrial-chemistry"],
    world_mode="marine", progression_mode="nauvis-only", active_mods=active,
    mir_version=mir_version, mir_owner_present=technology ~= nil,
    level=technology and technology.level or nil, researched=researched,
    effects=effects, recipe_enabled=recipe.enabled, recipe_productivity_bonus=recipe.productivity_bonus,
    ingredients=typed(prototype.ingredients), products=typed(prototype.products),
  }))
end)
