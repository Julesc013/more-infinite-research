-- Base/default 0.13-0.16 regression: a handcraftable lab must not disappear from
-- the acquisition graph merely because the actor prototype is named player.
assert(data.raw.player and data.raw.player.player, 'Expected the historical player prototype')
if data.raw.tool['alien-science-pack'] then
  assert(not data.raw.technology['recipe-prod-research_robot_battery-1'], 'Unsupported historical robot-battery modifier was emitted')
end
local accepted = {}
for _, name in ipairs(data.raw.lab.lab.inputs) do accepted[name] = true end
for _, key in ipairs({
  'research_character_crafting_speed', 'research_character_mining_speed',
  'research_character_reach', 'research_character_walking_speed', 'research_inventory_capacity'
}) do
  local name = 'recipe-prod-' .. key .. '-1'
  local technology = assert(data.raw.technology[name], 'Missing handcrafting-dependent research: ' .. name)
  assert(technology.enabled ~= false and not technology.hidden, 'Unavailable research: ' .. name)
  if data.raw.tool['alien-science-pack'] then
    assert(type(technology.icon)=='string' and technology.icons==nil, 'Missing historical singular icon: ' .. name)
  else
    assert(technology.icons and #technology.icons>0, 'Missing layered icon: ' .. name)
  end
  assert(technology.unit and #technology.unit.ingredients > 0, 'Missing research science: ' .. name)
  -- MIR's terminal 0.13/0.14 predecessor uses alien science for these late
  -- character upgrades. The 0.15/0.16 equivalent is high-tech plus military.
  local expected = data.raw.tool['alien-science-pack'] and {['alien-science-pack']=true}
    or {['high-tech-science-pack']=true,['military-science-pack']=true}
  for _, ingredient in ipairs(technology.unit.ingredients) do
    local pack, amount = ingredient.name or ingredient[1], ingredient.amount or ingredient[2]
    assert(accepted[pack] and amount > 0, 'Invalid laboratory ingredient: ' .. name .. '/' .. tostring(pack))
    assert(expected[pack], 'Unexpected default science: ' .. name .. '/' .. tostring(pack))
    expected[pack] = nil
  end
  assert(next(expected)==nil, 'Missing native default science: ' .. name)
  assert(technology.effects and #technology.effects > 0, 'Missing research effects: ' .. name)
  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    assert(data.raw.technology[prerequisite], 'Missing prerequisite: ' .. name .. '/' .. prerequisite)
  end
  log('[mir-fixture] MIR-HISTORICAL-HANDCRAFTING-CATALOGUE ' .. name)
end
