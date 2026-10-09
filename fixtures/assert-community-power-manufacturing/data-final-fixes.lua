assert(not mods['space-age'] and not mods.Paracelsin, 'Expected the paired base-only power profile')
assert(settings.startup['solar-matrix-power'].value == 128, 'Solar output setting changed')
assert(settings.startup['accumulator-power-capacity'].value == 10, 'Accumulator capacity setting changed')
local owner = 'recipe-prod-research_electric_energy-1'
local technology = assert(data.raw.technology[owner], 'Missing power manufacturing research')
assert(technology.enabled ~= false and not technology.hidden, 'Power manufacturing research unavailable')
assert(technology.unit and #technology.unit.ingredients > 0, 'Missing power research science')
assert(not data.raw.technology['accumulator-v2'], 'Paired upstream unlock ownership differs')
local unlocks = {}
for _, effect in ipairs(data.raw.technology['solar-matrix'].effects) do
  if effect.type == 'unlock-recipe' then unlocks[effect.recipe] = true end
end
for _, recipe in ipairs({'solar-matrix', 'accumulator-v2'}) do
  assert(unlocks[recipe] and data.raw.recipe[recipe], 'Missing paired recipe unlock: ' .. recipe)
  local owners = 0
  for name, row in pairs(data.raw.technology) do
    for _, effect in ipairs(row.effects or {}) do
      if effect.type == 'change-recipe-productivity' and effect.recipe == recipe then
        assert(name == owner and effect.change == 0.05, 'Wrong manufacturing owner or tier: ' .. recipe)
        owners = owners + 1
      end
    end
  end
  assert(owners == 1, 'Expected one manufacturing effect: ' .. recipe)
end
log('[mir-community-power] FINAL-PROTOTYPES-PASS paired-unlock=solar-matrix owner=' .. owner)
