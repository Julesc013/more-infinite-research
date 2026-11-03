-- Exact finite Muria weapon7/8 route. No suffix search or foreign mutation.
local M = {}

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function finite_stage(technologies, name, predecessor, level)
  local technology = technologies[name]
  if type(technology) ~= "table" or technology.type ~= "technology" or technology.name ~= name
      or (technology.max_level ~= nil and technology.max_level ~= level)
      or (technology.level ~= nil and technology.level ~= level) or type(technology.unit) ~= "table" then
    error("MIR Muria weapon continuation requires the finite " .. name, 3)
  end
  local anchored = false
  for _, id in ipairs(technology.prerequisites or {}) do if id == predecessor then anchored = true end end
  local unit = technology.unit
  if not anchored or not positive(unit.count) or unit.count ~= math.floor(unit.count)
      or unit.count_formula ~= nil or not positive(unit.time) then
    error("MIR Muria weapon continuation has unsupported progression at " .. name, 3)
  end
  return technology
end

function M.weapon_continuation(row, raw)
  row.id, row.level, row.predecessor = "weapon-shooting-speed-9", 9, "weapon-shooting-speed-8"
  row.prerequisites, row.exact_prerequisites = {"weapon-shooting-speed-8"}, true
  -- Parse-time Library/cap metadata needs only this explicit identity. Actual
  -- emission always supplies data.raw and validates both named finite inputs.
  if raw == nil then return end
  local technologies = type(raw) == "table" and raw.technology
  if type(technologies) ~= "table" then error("MIR Muria weapon continuation requires native technologies", 2) end
  local previous = finite_stage(technologies, "weapon-shooting-speed-7", "weapon-shooting-speed-6", 7)
  local last = finite_stage(technologies, "weapon-shooting-speed-8", "weapon-shooting-speed-7", 8)
  row.inheritance = {last_count=last.unit.count, previous_count=previous.unit.count, research_time=last.unit.time}
  if type(last.unit.ingredients) ~= "table" or #last.unit.ingredients == 0 or #last.unit.ingredients > 32 then
    error("MIR Muria weapon continuation requires a bounded native science vector", 2)
  end
  row.ingredients = {}
  for index, ingredient in ipairs(last.unit.ingredients) do
    if type(ingredient) ~= "table" or type(ingredient[1]) ~= "string" or ingredient[1] == ""
        or not positive(ingredient[2]) or ingredient[2] ~= math.floor(ingredient[2]) then
      error("MIR Muria weapon continuation has invalid science", 2)
    end
    row.ingredients[index] = {ingredient[1], ingredient[2]}
  end
  -- Published4.7.3 preserves a modded finite tail's effects at the default
  -- control value, scaling an intentional setting relative to that value.
  -- Retain that independent rule on this exact weapon route, not on foreign7/8.
  if type(last.effects) ~= "table" or #last.effects == 0 or #last.effects > 32 then
    error("MIR Muria weapon continuation requires bounded gun-speed effects", 2)
  end
  local effects, categories = {}, {}
  for _, effect in ipairs(last.effects) do
    if type(effect) ~= "table" or effect.type ~= "gun-speed" or type(effect.ammo_category) ~= "string"
        or effect.ammo_category == "" or categories[effect.ammo_category] or not positive(effect.modifier) then
      error("MIR Muria weapon continuation has unsupported gun-speed effects", 2)
    end
    categories[effect.ammo_category] = true
    effects[#effects + 1] = {type="gun-speed", ammo_category=effect.ammo_category, scale=effect.modifier / .4}
  end
  if not categories.bullet or not categories["shotgun-shell"] then
    error("MIR Muria weapon continuation lacks native bullet/shotgun effects", 2)
  end
  -- Keep the already admitted named Ironclad/category additions if the finite
  -- Muria tail does not carry them; never duplicate an existing category.
  for _, effect in ipairs(row.effects) do
    if effect.ammo_category and not categories[effect.ammo_category] then
      effects[#effects + 1], categories[effect.ammo_category] = effect, true
    end
  end
  row.effects = effects
end

return M
