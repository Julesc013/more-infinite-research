-- Secretas authors the finite robot-storage4..8 route. Keep those prototypes
-- intact and continue at the independently preserved ninth-level identity.
local M = {}

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function M.worker_continuation(row, raw)
  row.id, row.level, row.predecessor = "worker-robots-storage-9", 9, "worker-robots-storage-8"
  row.prerequisites, row.exact_prerequisites = {"worker-robots-storage-8"}, true
  -- Runtime/setting declarations need only the fixed identity. Emission
  -- supplies data.raw and validates the five actual finite inputs.
  if raw == nil then return end
  local technologies = type(raw) == "table" and raw.technology
  if type(technologies) ~= "table" then error("MIR Secretas continuation requires native technologies", 2) end
  for level = 4, 8 do
    local name = "worker-robots-storage-" .. level
    local technology = technologies[name]
    if type(technology) ~= "table" or technology.type ~= "technology" or technology.name ~= name
        or (technology.max_level ~= nil and technology.max_level ~= level)
        or (technology.level ~= nil and technology.level ~= level) then
      error("MIR Secretas continuation requires the finite " .. name, 2)
    end
    local anchored = false
    for _, id in ipairs(technology.prerequisites or {}) do
      if id == "worker-robots-storage-" .. (level - 1) then anchored = true end
    end
    local unit = technology.unit
    if not anchored or type(unit) ~= "table" or not positive(unit.count)
        or unit.count ~= math.floor(unit.count) or unit.count_formula ~= nil or not positive(unit.time) then
      error("MIR Secretas continuation has unsupported progression at " .. name, 2)
    end
  end
  local previous, last = technologies["worker-robots-storage-7"], technologies["worker-robots-storage-8"]
  row.inheritance = {last_count=last.unit.count, previous_count=previous.unit.count, research_time=last.unit.time}
  if type(last.unit.ingredients) ~= "table" or #last.unit.ingredients == 0 or #last.unit.ingredients > 32 then
    error("MIR Secretas continuation requires a bounded native science vector", 2)
  end
  row.ingredients = {}
  for index, ingredient in ipairs(last.unit.ingredients) do
    if type(ingredient) ~= "table" or type(ingredient[1]) ~= "string" or ingredient[1] == ""
        or not positive(ingredient[2]) or ingredient[2] ~= math.floor(ingredient[2]) then
      error("MIR Secretas continuation has invalid science", 2)
    end
    row.ingredients[index] = {ingredient[1], ingredient[2]}
  end
  if type(last.effects) ~= "table" or #last.effects ~= 1 or type(last.effects[1]) ~= "table"
      or last.effects[1].type ~= "worker-robot-storage" or not positive(last.effects[1].modifier) then
    error("MIR Secretas continuation requires the native worker-storage effect", 2)
  end
  -- Worker storage is an absolute-unit setting with default1. Preserve the
  -- finite tail's actual effect at default; explicit values scale that effect.
  row.effects = {{type="worker-robot-storage", scale=last.effects[1].modifier}}
end

return M
