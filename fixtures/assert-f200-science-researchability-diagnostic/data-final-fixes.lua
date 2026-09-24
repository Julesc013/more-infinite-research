-- Exact-scenario diagnostic only. This fixture reads the packaged F200 graph
-- after MIR and its Bob/Angel roots have run; it neither writes prototypes nor
-- enters the player-facing MIR API surface.
local science = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.science_packs")
local reachability = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.pack_production_reachability")
local compiler_context = require(
  "__more-infinite-research__.prototypes.mir.pipeline.compiler_context")
local recipe_unlocks = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local technology_researchability = require(
  "__more-infinite-research__.prototypes.mir.capabilities.science_integration.technology_researchability")

local function fail(message)
  error("MIR F200 science researchability diagnostic assertion failed: " .. message)
end

local subjects = {
  {
    stream = "research_cannon_shooting_speed",
    generated_technology = "recipe-prod-research_cannon_shooting_speed-1",
    prerequisite = "weapon-shooting-speed-5"
  },
  {
    stream = "research_electric_shooting_speed",
    generated_technology = "recipe-prod-research_electric_shooting_speed-1",
    prerequisite = "discharge-defense-equipment"
  },
  {
    stream = "research_flamethrower_shooting_speed",
    generated_technology = "recipe-prod-research_flamethrower_shooting_speed-1",
    prerequisite = "flamethrower"
  },
  {
    stream = "research_rocket_shooting_speed",
    generated_technology = "recipe-prod-research_rocket_shooting_speed-1",
    prerequisite = "rocketry"
  }
}

local no_lab_omissions = {
  "research_character_crafting_speed",
  "research_character_mining_speed",
  "research_character_reach",
  "research_character_walking_speed",
  "research_inventory_capacity"
}

-- Capture the whole ordinary-material batch during the same exact Bob/Angel
-- load used for science diagnosis. These observations select later assertions;
-- a present declaration alone is not a qualified player outcome.
local material_keys = {
  "aluminium", "gold", "lead", "nickel", "platinum", "silver", "tin", "titanium",
  "copper_tungsten", "zinc", "bronze", "brass", "gunmetal", "invar",
  "cobalt_steel", "nitinol"
}

local function observe_material(key)
  local technology_name = "recipe-prod-research_material_" .. key .. "-1"
  local technology = data.raw.technology[technology_name]
  if not technology then
    log("[mir-fixture-assert-f200-science-researchability-diagnostic] material=" .. key
      .. " technology=absent effects=- science=-")
    return
  end
  local effects, packs = {}, {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe then
      effects[#effects + 1] = effect.recipe .. ":" .. tostring(effect.change)
    end
  end
  for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
    local name = type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
    if name then packs[#packs + 1] = name end
  end
  table.sort(effects)
  table.sort(packs)
  log("[mir-fixture-assert-f200-science-researchability-diagnostic] material=" .. key
    .. " technology=present effects=" .. (#effects > 0 and table.concat(effects, ",") or "-")
    .. " science=" .. (#packs > 0 and table.concat(packs, ",") or "-"))
end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
end

local function ingredient_type(ingredient)
  return type(ingredient) == "table" and (ingredient.type or "item") or nil
end

local function recipe_ingredient_names(recipe_name)
  local recipe = data.raw.recipe[recipe_name]
  if not recipe then fail("missing finalized recipe " .. recipe_name) end
  local names = {}
  for _, ingredient in ipairs(recipe.ingredients or {}) do
    table.insert(names, ingredient_name(ingredient))
  end
  table.sort(names)
  return names
end

local function assert_names(actual, expected, label)
  local actual_text = table.concat(actual or {}, ",")
  local sorted_expected = {}
  for _, value in ipairs(expected or {}) do table.insert(sorted_expected, value) end
  table.sort(sorted_expected)
  local expected_text = table.concat(sorted_expected, ",")
  if actual_text ~= expected_text then
    fail(label .. " expected=" .. expected_text .. " actual=" .. actual_text)
  end
end

local function technology_uses_pack(technology_name, pack_name)
  local technology = data.raw.technology[technology_name]
  if not technology then return false end
  for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
    if ingredient_name(ingredient) == pack_name then return true end
  end
  return false
end

local function assert_unlocker(recipe_name, technology_name)
  if not contains(recipe_unlocks.unlockers_for_recipe(recipe_name), technology_name) then
    fail(recipe_name .. " is not unlocked by finalized technology " .. technology_name)
  end
  local rejection = technology_researchability.reason_with_context(technology_name, {
    visiting_packs = {},
    visiting_technologies = {},
    unlock_recipe_name = recipe_name
  })
  if rejection ~= nil then
    fail(technology_name .. " is not researchable for " .. recipe_name .. ": " .. tostring(rejection))
  end
end

-- Return the real technology in this prerequisite closure which consumes the
-- queried pack. The fixture derives this only from Factorio's final prototype
-- graph; no MIR planner result is used to justify the assertion.
local function prerequisite_chain_logistic_consumer(root_name)
  local visiting = {}
  local function visit(technology_name)
    if visiting[technology_name] then return nil end
    visiting[technology_name] = true
    local technology = data.raw.technology[technology_name]
    if not technology then return nil end
    for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
      if ingredient_name(ingredient) == "logistic-science-pack" then return technology_name end
    end
    for _, prerequisite in ipairs(technology.prerequisites or {}) do
      local consumer = visit(prerequisite)
      if consumer then return consumer end
    end
    return nil
  end
  return visit(root_name)
end

compiler_context.with_active(compiler_context.new({execution_mode = "SAFE"}), function()
  -- Register only the private traversal services on the fixture's short-lived
  -- parent context. pack_production_rejection_projection itself creates a
  -- second fresh context for every observation, so no cache or telemetry can
  -- escape into the normal packaged compilation context.
  science.ensure_services()
  -- The bounded observation may borrow only an already-materialized immutable
  -- recipe snapshot from this short-lived parent. Build that canonical parent
  -- snapshot here, before any projection, rather than allowing the child
  -- observation to construct recipe facts without an observer.
  local canonical_recipe_facts = require(
    "__more-infinite-research__.prototypes.mir.index.recipe_facts")
  local parent_recipe_index = canonical_recipe_facts.index_view()
  if type(parent_recipe_index) ~= "table" then
    fail("canonical parent recipe index did not initialize")
  end
  assert_names(recipe_ingredient_names("logistic-science-pack"), {
    "electronic-circuit", "inserter", "transport-belt"
  }, "finalized logistic science ingredients")
  assert_names(recipe_ingredient_names("electronic-circuit"), {
    "bob-basic-electronic-components", "bob-solder", "bob-wooden-board"
  }, "finalized electronic circuit ingredients")
  assert_names(recipe_ingredient_names("bob-basic-electronic-components"), {
    "angels-solid-carbon", "bob-tinned-copper-cable"
  }, "finalized basic electronic component ingredients")
  local solder_recipe = data.raw.recipe["angels-solder"]
  if not solder_recipe or #(solder_recipe.ingredients or {}) ~= 1
    or ingredient_name(solder_recipe.ingredients[1]) ~= "angels-liquid-molten-solder"
    or ingredient_type(solder_recipe.ingredients[1]) ~= "fluid" then
    fail("finalized Angel solder route is not the typed molten-solder route")
  end
  local logistic_unlock = data.raw.technology["logistic-science-pack"]
  if not logistic_unlock or not technology_uses_pack("logistic-science-pack", "automation-science-pack") then
    fail("logistic-science-pack is not the finalized automation-science consumer")
  end
  local boiler = data.raw.boiler and data.raw.boiler["boiler"]
  if not boiler or not boiler.fluid_box or boiler.fluid_box.filter ~= "water"
    or not boiler.output_fluid_box or boiler.output_fluid_box.filter ~= "steam" then
    fail("base boiler does not provide the finalized water-to-steam conversion")
  end
  if not technology_uses_pack("bob-electronics", "automation-science-pack") then
    fail("bob-electronics is not the finalized automation-science consumer")
  end
  assert_unlocker("logistic-science-pack", "logistic-science-pack")
  assert_unlocker("electronic-circuit", "bob-electronics")
  assert_unlocker("bob-basic-electronic-components", "bob-electronics")
  assert_unlocker("angels-solder", "angels-solder-smelting-1")

  local status, prerequisite = reachability.pack_production_status("logistic-science-pack", {})
  local route = reachability.production_route_for_pack("logistic-science-pack")
  if status ~= "research" or prerequisite ~= "logistic-science-pack"
    or not route or route.recipe ~= "logistic-science-pack"
    or route.unlocker ~= "logistic-science-pack" then
    fail("finalized logistic-science acquisition route was not selected")
  end
  local logistic_rejection = reachability.pack_production_rejection_projection("logistic-science-pack", {
    limits = {candidates = 16, nodes = 1024, depth = 32, bytes = 32768}
  })
  if logistic_rejection ~= nil then
    local failure = logistic_rejection.first_failure or {}
    local truncation = logistic_rejection.truncation or {}
    local usage = truncation.usage or {}
    local bounded = logistic_rejection.status == "indeterminate"
      and failure.reason == "diagnostic-work-budget-exhausted"
      and usage.visits == 1024
      and contains(truncation.truncated, "nodes")
    if not bounded then
      fail("reachable finalized logistic-science route retained a rejection projection"
        .. " status=" .. tostring(logistic_rejection.status)
        .. " reason=" .. tostring(failure.reason)
        .. " visits=" .. tostring(usage.visits)
        .. " truncated=" .. table.concat(truncation.truncated or {}, ","))
    end
    log("[mir-fixture-assert-f200-science-researchability-diagnostic] projection=bounded-indeterminate"
      .. " pack=logistic-science-pack visits=" .. tostring(usage.visits)
      .. " reason=" .. tostring(failure.reason))
  end
  log("[mir-fixture-assert-f200-science-researchability-diagnostic] final-route"
    .. " pack=logistic-science-pack status=" .. status
    .. " prerequisite=" .. prerequisite
    .. " recipe=" .. route.recipe .. " unlocker=" .. route.unlocker
    .. " steam_witness=boiler-conversion")

  local chemical_status, chemical_prerequisite = reachability.pack_production_status("chemical-science-pack", {})
  local chemical_route = reachability.production_route_for_pack("chemical-science-pack")
  log("[mir-fixture-assert-f200-science-researchability-diagnostic] chemical-route"
    .. " status=" .. tostring(chemical_status)
    .. " prerequisite=" .. tostring(chemical_prerequisite)
    .. " recipe=" .. tostring(chemical_route and chemical_route.recipe)
    .. " unlocker=" .. tostring(chemical_route and chemical_route.unlocker)
    .. " ingredients=" .. table.concat(recipe_ingredient_names("chemical-science-pack"), ","))

  for _, key in ipairs(material_keys) do observe_material(key) end
  if chemical_status ~= "research" or chemical_prerequisite ~= "chemical-science-pack"
    or not chemical_route or chemical_route.recipe ~= "chemical-science-pack" then
    fail("finalized chemical-science acquisition route was not selected")
  end

  for index, subject in ipairs(subjects) do
    local generated = data.raw.technology[subject.generated_technology]
    if not generated then
      fail(subject.stream .. " is missing MIR generated technology " .. subject.generated_technology)
    end
    if not contains(generated.prerequisites, subject.prerequisite) then
      fail(subject.stream .. " generated technology is not bound to " .. subject.prerequisite)
    end
    if not data.raw.technology[subject.prerequisite] then
      fail(subject.stream .. " is missing expected prerequisite technology " .. subject.prerequisite)
    end
    local logistic_consumer = prerequisite_chain_logistic_consumer(subject.prerequisite)
    if not logistic_consumer then
      fail(subject.stream .. " prerequisite chain does not consume logistic-science-pack")
    end
    log("[mir-fixture-assert-f200-science-researchability-diagnostic] emission=" .. index
      .. " stream=" .. subject.stream
      .. " generated=" .. subject.generated_technology
      .. " prerequisite=" .. subject.prerequisite
      .. " logistic_consumer=" .. logistic_consumer
      .. " pack=logistic-science-pack status=generated")
  end

  for index, stream in ipairs(no_lab_omissions) do
    local technology_name = "recipe-prod-" .. stream .. "-1"
    if data.raw.technology[technology_name] then
      fail(stream .. " unexpectedly generated without lab-compatible science")
    end
    log("[mir-fixture-assert-f200-science-researchability-diagnostic] omission=" .. index
      .. " stream=" .. stream .. " generated=" .. technology_name .. " status=absent")
  end

end)

log("[mir-fixture-assert-f200-science-researchability-diagnostic] PASS"
  .. " final_route=reachable emissions=4 no_lab_omissions=5"
  .. " material_observations=16 player-mutation=false prototype-write=false")
