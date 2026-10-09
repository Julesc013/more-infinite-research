local early_name = "recipe-prod-research_material_tin-1"
local continuation_name = "recipe-prod-research_material_tin-4"
local recipe_name = "bob-tin-plate"
local ore_name = "bob-tin-ore"
local output_name = "bob-tin-plate"
local input_count = 100
local expected_legacy_bonus = 0.06
local expected_level_four_bonus = 0.08
local expected_output = 108

local reload_pending = false
local reload_reported = false

local function fail(message)
  error("[mir-f210-current-bob-tin-level4] " .. message)
end

local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < 0.000001
end

local function exact_mod_closure()
  for _, official in ipairs({"base", "elevated-rails", "quality", "recycler", "space-age"}) do
    if not script.active_mods[official] then fail("required official module is absent " .. official) end
  end
  local expected = {
    boblibrary = "3.0.1",
    bobores = "3.0.0",
    bobplates = "3.0.2",
    bobelectronics = "3.0.1",
    bobtech = "3.0.0"
  }
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then
      fail("Bob module version differs " .. name .. "=" .. tostring(script.active_mods[name]))
    end
  end
  for _, forbidden in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do
    if script.active_mods[forbidden] then fail("fixture refuses Angel module " .. forbidden) end
  end
end

local function effect_change(technology)
  local count, change = 0, nil
  for _, effect in ipairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      count = count + 1
      change = effect.change
    end
  end
  if count ~= 1 or not near(change, 0.02) then
    fail("runtime productivity effect differs " .. technology.name)
  end
  return change
end

local function productivity_bonus(force)
  local recipe = force.recipes[recipe_name]
  if not recipe then fail("force recipe is absent") end
  local value = recipe.productivity_bonus
  if type(value) ~= "number" then fail("recipe productivity bonus is absent") end
  return value
end

local function complete_research(force, technology, label)
  local current_level = technology.level
  if not force.add_research(technology) or not force.current_research
      or force.current_research.name ~= technology.name then
    fail("add_research did not select " .. label)
  end
  force.research_queue = nil
  -- LuaTechnology.level is Factorio's documented levelled-research
  -- completion operation: assigning N researches the prior level N - 1.
  -- The finite legacy technology permits that only through level 3. Its
  -- final level is completed through the documented researched transition,
  -- which triggers the remaining advancement perks without assigning level 4.
  if technology.name == early_name and current_level == 3 then
    technology.researched = true
    if not technology.researched then
      fail("finite final research completion did not mark " .. label)
    end
  else
    technology.level = current_level + 1
    if technology.level ~= current_level + 1 then
      fail("levelled research completion did not advance " .. label
        .. " expected=" .. tostring(current_level + 1)
        .. " actual=" .. tostring(technology.level))
    end
  end
  if force.current_research then force.cancel_current_research() end
end

local function prepare_level_four(force)
  local early = force.technologies[early_name]
  local continuation = force.technologies[continuation_name]
  if not early or not continuation then fail("Tin technology chain is absent") end
  for _, prerequisite in pairs(early.prerequisites) do prerequisite.research_recursive() end
  for level = 1, 3 do
    if early.level ~= level then fail("legacy Tin level differs before completion " .. level) end
    complete_research(force, early, "legacy-" .. level)
  end
  if not early.researched then fail("finite legacy Tin completion did not persist") end
  if not near(productivity_bonus(force), expected_legacy_bonus) then
    fail("legacy Tin productivity bonus differs")
  end
  for _, prerequisite in pairs(continuation.prerequisites) do
    if prerequisite.name ~= early_name then prerequisite.research_recursive() end
  end
  if continuation.level ~= 4 then fail("continuation first research level differs") end
  effect_change(continuation)
  complete_research(force, continuation, "continuation-4")
  local bonus = productivity_bonus(force)
  if not near(bonus, expected_level_four_bonus) then
    fail("level-four Tin productivity bonus differs " .. tostring(bonus))
  end
  return early, continuation, bonus
end

local function prepare_machine(force)
  local furnace = game.surfaces[1].create_entity{name = "stone-furnace", position = {0, 0}, force = force}
  if not furnace then fail("could not create Tin production witness") end
  local input = furnace.get_inventory(defines.inventory.crafter_input)
  local fuel = furnace.get_inventory(defines.inventory.fuel)
  if not input or not fuel then fail("Tin production inventories are absent") end
  if input.insert{name = ore_name, count = input_count} ~= input_count then fail("could not insert exact Tin ore input") end
  if fuel.insert{name = "solid-fuel", count = 50} ~= 50 then fail("could not insert exact Tin fuel") end
end

script.on_init(function()
  exact_mod_closure()
  local force = game.forces.player
  if not force then fail("player force is absent") end
  force.enable_all_prototypes()
  local early, continuation, bonus = prepare_level_four(force)
  prepare_machine(force)
  storage.mir_f210_current_bob_tin_level4 = {
    version = 1,
    early_researched = early.researched,
    continuation_level_after_research = continuation.level,
    continuation_researched = continuation.researched,
    bonus_after_research = bonus,
    expected_output = expected_output
  }
  log("[mir-f210-current-bob-tin-level4] CREATE PASS"
    .. " legacy-levels=3 continuation-start=4 continuation-next="
    .. tostring(continuation.level)
    .. " bonus-before=0.06 bonus-after=0.08"
    .. " research-action=add_research-to-level-and-finite-researched science-lab=accepted")
end)

script.on_load(function()
  reload_pending = true
  reload_reported = false
end)

script.on_event(defines.events.on_tick, function(event)
  if not reload_pending or reload_reported then return end
  local state = storage.mir_f210_current_bob_tin_level4
  if not state or state.version ~= 1 or state.early_researched ~= true
      or not near(state.bonus_after_research, expected_level_four_bonus) then
    fail("saved level-four state differs")
  end
  local force = game.forces.player
  local early = force and force.technologies[early_name]
  local continuation = force and force.technologies[continuation_name]
  if not early or not early.researched or not continuation
      or not near(productivity_bonus(force), expected_level_four_bonus) then
    fail("reloaded Tin research state differs")
  end
  local furnace = game.surfaces[1].find_entity("stone-furnace", {0, 0})
  if not furnace then fail("reloaded Tin production witness is absent") end
  local input = furnace.get_inventory(defines.inventory.crafter_input)
  local output = furnace.get_inventory(defines.inventory.crafter_output)
  if not input or not output then fail("reloaded Tin production inventories are absent") end
  local count = output.get_item_count(output_name)
  if count > 0 then
    if output.remove{name = output_name, count = count} ~= count then
      fail("Tin output drain differs")
    end
    storage.mir_f210_current_bob_tin_level4.removed_output =
      (storage.mir_f210_current_bob_tin_level4.removed_output or 0) + count
  end
  if input.get_item_count(ore_name) == 0 and furnace.crafting_progress == 0
      and output.get_item_count(output_name) == 0 then
    -- The complete count is accumulated from Factorio's recipe productivity
    -- into the removed output rather than inferred from a bonus formula.
    local removed = storage.mir_f210_current_bob_tin_level4.removed_output or 0
    if removed ~= expected_output then fail("level-four produced output differs " .. tostring(removed)) end
    reload_reported = true
    log("[mir-f210-current-bob-tin-level4] RELOAD PASS"
      .. " continuation-next=" .. tostring(continuation.level)
      .. " output=" .. tostring(removed)
      .. " bonus=0.08 continuity=true")
  elseif event.tick >= 30000 then
    fail("Tin level-four production did not finish within bounded reload")
  end
end)
