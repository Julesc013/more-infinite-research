local owner = 'recipe-prod-research_electric_energy-1'
local names = {'solar-matrix', 'accumulator-v2'}
local reload_pending = false
local function near(actual, expected) return math.abs(actual - expected) < 0.000001 end
local function report(stage)
  local state = assert(storage.mir_community_power)
  local facts = {}
  for _, row in ipairs(state.cases) do
    assert(row.output == row.expected, 'Incorrect actual output: ' .. row.force .. '/' .. row.recipe)
    assert(near(game.forces[row.force].recipes[row.recipe].productivity_bonus, row.bonus), 'Saved bonus changed')
    facts[#facts+1] = {force=row.force, recipe=row.recipe, output=row.output, expected=row.expected,
      bonus=row.bonus, remaining=row.remaining, crafts=20}
  end
  helpers.write_file('community-power-' .. stage .. '.json', helpers.table_to_json{
    status='passed', stage=stage, cases=facts, mods=script.active_mods,
    production='20 unmodified recipe crafts; no modules or beacons; fixture supplies ingredients and machine energy; game speed 64',
    boundary='Exact F200 paired base/default manufacturing; no SE, AAI, Paracelsin, DLC or package-upgrade claim'
  }, false)
  log('[mir-community-power] ' .. stage .. ' PASS actual-output=21 researched / 20 unresearched per recipe')
end
script.on_init(function()
  game.speed = 64
  assert(script.active_mods.base == '2.0.77' and script.active_mods['more-infinite-research'] == '4.2.20001')
  assert(script.active_mods.SolarMatrix == '1.0.8' and script.active_mods['Accumulator-V2'] == '1.0.7')
  local researched = game.forces.player
  local control = game.create_force('mir-community-unresearched')
  local technology = assert(researched.technologies[owner])
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for _, name in ipairs(names) do assert(near(researched.recipes[name].productivity_bonus, 0)) end
  assert(technology.level == 1 and researched.add_research(technology), 'Research action unavailable')
  researched.research_queue = nil
  technology.level = 2
  assert(technology.level == 2, 'First research reward was not applied')
  if researched.current_research then researched.cancel_current_research() end
  local state = {cases={}, done=false}
  storage.mir_community_power = state
  local surface = game.surfaces[1]
  for index, force in ipairs({researched, control}) do
    force.technologies['solar-matrix'].research_recursive()
    for recipe_index, name in ipairs(names) do
      local bonus = index == 1 and 0.05 or 0
      local recipe = assert(force.recipes[name])
      assert(recipe.enabled and near(recipe.productivity_bonus, bonus), 'Native research bonus differs: ' .. name)
      local position = {x=(index-1)*12, y=(recipe_index-1)*12}
      local tiles = {}
      for x=position.x-2,position.x+2 do for y=position.y-2,position.y+2 do
        tiles[#tiles+1]={name='grass-1',position={x,y}}
      end end
      surface.set_tiles(tiles)
      local entity = assert(surface.create_entity{name='assembling-machine-3',position=position,force=force})
      entity.set_recipe(name)
      assert(entity.get_recipe().name == name)
      local remaining = {}
      for _, ingredient in pairs(recipe.ingredients) do
        assert(ingredient.type == 'item', 'Unexpected fluid input')
        remaining[ingredient.name] = ingredient.amount * 20
      end
      state.cases[#state.cases+1] = {force=force.name, recipe=name, entity=entity,
        remaining=remaining, output=0, expected=index == 1 and 21 or 20, bonus=bonus}
    end
  end
  log('[mir-community-power] CREATE PASS earned-bonus=0.05 comparison=0')
end)
script.on_load(function() reload_pending = true end)
script.on_event(defines.events.on_tick, function()
  local state = assert(storage.mir_community_power)
  if state.done then
    if reload_pending then reload_pending=false; report('reload') end
    return
  end
  local all_done = true
  for _, row in ipairs(state.cases) do
    local entity = assert(row.entity.valid and row.entity)
    entity.energy = 1000000000
    local input = assert(entity.get_inventory(defines.inventory.crafter_input))
    local output = assert(entity.get_inventory(defines.inventory.crafter_output))
    local left = 0
    for name, count in pairs(row.remaining) do
      local inserted = count > 0 and input.insert{name=name,count=count} or 0
      row.remaining[name] = count - inserted
      left = left + row.remaining[name] + input.get_item_count(name)
    end
    local count = output.get_item_count(row.recipe)
    if count > 0 then
      assert(output.remove{name=row.recipe,count=count} == count)
      row.output = row.output + count
    end
    assert(row.output <= row.expected, 'Excess manufacturing output')
    if left ~= 0 or entity.crafting_progress ~= 0 then all_done = false end
  end
  if all_done then
    state.done=true
    -- Keep serializable facts in the report; the entities stay in the save.
    report('production')
    game.auto_save('mir-community-power')
    reload_pending=false
  end
end)
