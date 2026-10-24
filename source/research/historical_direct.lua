-- Detached TechnologyPrototype construction for the delivered reduced target
-- surface. The target adapter supplies a small explicit contract; this module
-- validates only its named technology, science, and icon references before
-- returning any owned output.
local cost = require("research.cost")
local direct = require("research.native_direct_definitions")
local contracts = require("compatibility.historical_direct")

local M = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR historical direct output contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function historical_formula(stream)
  local base, increment, growth = stream.base_cost, stream.linear_increment, stream.growth_factor
  assert(finite(base) and base >= 1 and finite(increment) and increment >= 0 and finite(growth) and growth >= 1,
    "MIR invalid historical direct formula values")
  -- F015+ retained the `1*(...)` wrapper around the shared cost ABI.
  return "1*(" .. cost.cost(base, increment, growth) .. ")"
end

local function max_level(stream)
  assert(finite(stream.max_level) and stream.max_level >= 0 and stream.max_level == math.floor(stream.max_level),
    "MIR invalid historical direct maximum level")
  if stream.max_level == 0 then return "infinite" end
  return stream.max_level
end

local function stream_values(values, key)
  local definition = direct.definition(key)
  if values == nil then return definition.defaults end
  local stream = values.streams and values.streams[key]
  if type(stream) ~= "table" then error("MIR historical direct has no resolved stream values for " .. key, 3) end
  for _, field in ipairs({"enabled", "base_cost", "linear_increment", "growth_factor", "max_level", "research_time", "effect_percent"}) do
    if stream[field] == nil then error("MIR historical direct stream is missing " .. field .. " for " .. key, 3) end
  end
  return stream
end

local function raw_technology(raw, name)
  local technology = raw and raw.technology and raw.technology[name]
  if type(technology) ~= "table" then error("MIR historical direct requires technology " .. name, 3) end
  return technology
end

local function raw_science(raw, name)
  local tool = raw and raw.tool and raw.tool[name]
  if type(tool) ~= "table" then error("MIR historical direct requires science tool " .. name, 3) end
  return tool
end

local function raw_item(raw, name)
  -- These are only the delivered historical item prototype kinds. This is a
  -- named lookup for one authored icon candidate, never a prototype scan.
  local kinds = {"tool", "item", "mining-tool", "ammo", "repair-tool", "armor"}
  for _, kind in ipairs(kinds) do
    local prototype = raw and raw[kind] and raw[kind][name]
    if type(prototype) == "table" then return prototype end
  end
  return nil
end

local function icon_layers(prototype)
  if type(prototype.icons) == "table" and #prototype.icons > 0 then return copy(prototype.icons) end
  assert(type(prototype.icon) == "string" and prototype.icon ~= "", "MIR historical direct icon candidate has no icon")
  return {{icon=prototype.icon, icon_size=prototype.icon_size or 64}}
end

local function chosen_icon(definition, raw)
  for _, candidate in ipairs(definition.icon_candidates) do
    -- Historical target lines never admit a Space Age-only candidate merely
    -- because another mod happens to reuse that prototype name.
    if candidate.required_mod == nil then
      local prototype
      if candidate.technology then prototype = raw and raw.technology and raw.technology[candidate.technology]
      elseif candidate.item then prototype = raw_item(raw, candidate.item) end
      if type(prototype) == "table" and (type(prototype.icon) == "string" or type(prototype.icons) == "table") then
        return icon_layers(prototype)
      end
    end
  end
  error("MIR historical direct has no applicable icon candidate for " .. definition.key, 3)
end

local function effects(definition, stream)
  assert(finite(stream.effect_percent) and stream.effect_percent >= 0.01, "MIR invalid historical direct effect")
  local out = {}
  for index, authored in ipairs(definition.effects) do
    local modifier = stream.effect_percent * authored.scale
    if not authored.raw then modifier = modifier / 100 end
    local effect = {type=authored.type, modifier=modifier}
    if authored.ammo_category then effect.ammo_category = authored.ammo_category end
    out[index] = effect
  end
  return out
end

local function ingredients(names)
  local out = {}
  for index, name in ipairs(names) do out[index] = {name, 1} end
  return out
end

local function sorted_names(names)
  local out = copy(names)
  table.sort(out)
  return out
end

local function preflight(contract, raw)
  local names = {}
  for _, row in ipairs(contract.emitted) do
    local definition = direct.definition(row.key)
    local id = "recipe-prod-" .. definition.key .. "-1"
    if names[id] then error("MIR duplicate historical direct identity " .. id, 3) end
    names[id] = true
    for _, prerequisite in ipairs(row.prerequisites) do raw_technology(raw, prerequisite) end
    for _, science in ipairs(row.science) do raw_science(raw, science) end
    chosen_icon(definition, raw)
  end
end

local function technology(contract, row, values, raw)
  local definition, stream = direct.definition(row.key), stream_values(values, row.key)
  assert(finite(stream.research_time) and stream.research_time >= 0, "MIR invalid historical direct research time")
  local output = {
    type="technology", name="recipe-prod-" .. definition.key .. "-1", order=definition.order,
    -- The released planner canonicalised prerequisite identity order before
    -- projection.  Keep that exact deterministic output order while retaining
    -- the target adapter's compact, readable source contracts.
    prerequisites=sorted_names(row.prerequisites), effects=effects(definition, stream),
    localised_name=copy(definition.modern.localised_name), localised_description=copy(definition.modern.localised_description),
    unit={time=stream.research_time, ingredients=ingredients(row.science)},
  }
  local icons = chosen_icon(definition, raw)
  if contract.scalar_icon then
    output.icon, output.icon_size = icons[1].icon, icons[1].icon_size
  else
    output.icons = icons
    if contract.constant_overlay then
      output.icons[#output.icons + 1] = {icon=direct.legacy_overlay(definition.key), icon_size=128,
        shift={100, 100}, floating=true}
    end
  end
  -- The archived source's TechnologyPrototype projection sets these fields
  -- on every direct stream, including F013/F014 numeric-cost technologies.
  output.level, output.upgrade, output.max_level = 1, true, max_level(stream)
  if contract.numeric_cost then
    output.unit.count = stream.base_cost
  else
    output.unit.count_formula = historical_formula(stream)
    if contract.visible_when_disabled ~= nil then output.visible_when_disabled = contract.visible_when_disabled end
  end
  if stream.enabled == false then output.enabled = false end
  return output
end

function M.technologies(target, values, raw)
  local contract = contracts.for_target(target)
  preflight(contract, raw)
  local out = {}
  for index, row in ipairs(contract.emitted) do out[index] = technology(contract, row, values, raw) end
  return out
end

function M.contract(target)
  return contracts.for_target(target)
end

return M
