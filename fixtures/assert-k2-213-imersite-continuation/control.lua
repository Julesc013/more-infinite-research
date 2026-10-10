local expected_mods = {
  Krastorio2 = "2.1.3",
  ["Krastorio2-spaced-out"] = "2.0.13"
}
local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local powder_recipe = "kr-imersite-powder"
local crystal_recipe = "kr-imersite-crystal"
local loaded_from_save = false
local ore_name = "kr-imersite"
local sand_name = "kr-sand"

local function fail(message)
  error("MIR K2 2.1.3 Imersite continuation runtime validation failed: " .. message)
end

local function assert_close(name, actual, expected)
  if math.abs(actual - expected) > 0.000001 then
    fail(name .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function assert_profile()
  if script.active_mods["more-infinite-research"] ~= "4.2.21001"
      and script.active_mods["more-infinite-research"] ~= "4.2.21002" then fail("unexpected exact MIR candidate") end
  if script.active_mods.base ~= "2.1.20" and script.active_mods.base ~= "2.1.21" then fail("unexpected exact engine") end
  for name, version in pairs(expected_mods) do
    if script.active_mods[name] ~= version then fail("unexpected exact profile " .. name) end
  end
end

local function assert_state(stage)
  local force = game.forces.player
  local legacy = force.technologies[legacy_name]
  local powder = force.recipes[powder_recipe]
  local crystal = force.recipes[crystal_recipe]
  if not legacy or not stage then fail("required Imersite technology absent") end
  if not legacy.researched or legacy.prototype.max_level ~= 3 then
    fail("legacy stage did not retain its completed finite level-three domain")
  end
  if stage.level ~= 5 or stage.prototype.max_level < 4294967295 then
    fail("continuation did not retain the completed level-four state")
  end
  if not force.current_research or force.current_research.name ~= continuation_name then
    fail("continuation was not the queued next level")
  end
  assert_close("continuation progress", force.research_progress, 0.42)
  assert_close("MIR powder bonus", powder.productivity_bonus, 0.08)
  assert_close("native crystal bonus", crystal.productivity_bonus, 0.1)
end

local function prepare_production(force)
  local control = game.create_force("mir-k2-unresearched")
  control.recipes[powder_recipe].enabled = true
  assert_close("unresearched powder bonus", control.recipes[powder_recipe].productivity_bonus, 0)
  local recipe = force.recipes[powder_recipe]
  if #recipe.ingredients ~= 1 or recipe.ingredients[1].name ~= ore_name
      or recipe.ingredients[1].type ~= "item" or recipe.ingredients[1].amount ~= 3 then
    fail("production witness requires the exact three-ore powder recipe")
  end
  local products = {}
  for _, product in pairs(recipe.products) do
    if product.type ~= "item" or product.amount ~= 3 or (product.probability or 1) ~= 1 then
      fail("production witness requires deterministic three-item products")
    end
    products[product.name] = (products[product.name] or 0) + 1
  end
  if #recipe.products ~= 2 or products[powder_recipe] ~= 1 or products[sand_name] ~= 1 then
    fail("production witness powder/sand products differ")
  end
  local rows = {}
  for index, owner in ipairs({force, control}) do
    local position = {x=(index-1)*16, y=0}
    local surface = game.surfaces[1]
    local tiles = {}
    for x=position.x-4,position.x+4 do for y=-4,4 do
      tiles[#tiles+1] = {name="grass-1", position={x,y}}
    end end
    surface.set_tiles(tiles)
    local entity = surface.create_entity{name="kr-crusher", position=position, force=owner}
    if not entity then fail("could not create native crusher") end
    rows[#rows+1] = {force=owner.name, entity=entity, remaining=300, powder=0, sand=0,
      expected=index == 1 and 324 or 300, bonus=index == 1 and 0.08 or 0}
  end
  return rows
end

script.on_init(function()
  assert_profile()
  local force = game.forces.player
  force.research_all_technologies()
  local legacy = force.technologies[legacy_name]
  local stage = force.technologies[continuation_name]
  if not legacy or not stage then fail("required Imersite staged technology absent") end
  -- Per the runtime API, assigning level five applies all advancement perks
  -- through level four.  It leaves level five as the next research target.
  stage.level = 5
  force.reset_technology_effects()
  force.research_queue = {stage}
  if not force.current_research or force.current_research.name ~= continuation_name then
    fail("could not queue the level-five continuation target")
  end
  force.research_progress = 0.42
  storage.mir42_k2_213_imersite_continuation = {production=prepare_production(force)}
  assert_state(stage)
  log("[MIR42_K2_213_IMERSITE_CONTINUATION] stage=initial;completed_level=4;next_level=5;bonus=0.08;progress=0.42")
end)

script.on_load(function()
  loaded_from_save = true
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir42_k2_213_imersite_continuation
  if not state then return end
  if not loaded_from_save then return end
  if state.production_done then return end
  local stage = game.forces.player.technologies[continuation_name]
  assert_profile()
  assert_state(stage)
  if not state.continuity_checked then
    state.continuity_checked = true
    log("[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42")
  end
  local complete = true
  for _, row in ipairs(state.production) do
    local entity = row.entity
    if not entity.valid then fail("serialized crusher is absent") end
    entity.energy = 1000000000 -- Supply energy; recipe, speed and modules remain native.
    local input = entity.get_inventory(defines.inventory.crafter_input)
    local output = entity.get_inventory(defines.inventory.crafter_output)
    if not input or not output then fail("crusher inventories absent") end
    if row.remaining > 0 then
      row.remaining = row.remaining - input.insert{name=ore_name, count=row.remaining}
    end
    local selected = entity.get_recipe()
    if selected and selected.name ~= powder_recipe then fail("crusher selected another recipe") end
    for _, product in ipairs({{powder_recipe,"powder"},{sand_name,"sand"}}) do
      local count = output.get_item_count(product[1])
      if count > 0 then
        if output.remove{name=product[1], count=count} ~= count then fail("crusher output drain differs") end
        row[product[2]] = row[product[2]] + count
      end
    end
    if not output.is_empty() then fail("crusher produced an unexpected product") end
    assert_close("persisted powder bonus", game.forces[row.force].recipes[powder_recipe].productivity_bonus, row.bonus)
    if row.remaining ~= 0 or input.get_item_count(ore_name) ~= 0 or entity.crafting_progress ~= 0 then
      complete = false
    elseif row.powder ~= row.expected or row.sand ~= row.expected then
      fail("actual crusher output differs for " .. row.force .. ": " .. row.powder .. "/" .. row.sand)
    end
  end
  if complete then
    state.production_done = true
    local facts = {}
    for _, row in ipairs(state.production) do
      facts[#facts+1] = {force=row.force, ore=300, powder=row.powder, sand=row.sand, bonus=row.bonus}
    end
    helpers.write_file("k2-imersite-production.json", helpers.table_to_json{status="passed", cases=facts,
      mods=script.active_mods, completed_level=4, next_level=5, progress=game.forces.player.research_progress,
      boundary="Native unmodified crushers after reload; supplied ingredients/energy, no modules or beacons; not acquisition or package-upgrade proof"}, false)
    log("[MIR42_K2_213_IMERSITE_PRODUCTION] ore=300;powder=324;sand=324;control_powder=300;control_sand=300;after_reload=true")
  elseif event.tick >= 25000 then
    fail("crusher production did not complete within the bounded reload")
  end
end)
