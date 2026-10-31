-- Construction for the exact historical base-continuation subsets. This
-- module follows only the selected target's compact named contract; it never
-- enumerates a prototype family or promotes a foreign continuation.
local contracts = require("compatibility.historical_continuations")
local cost = require("research.cost")

local M = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR historical continuation output contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function integer(value)
  return finite(value) and value == math.floor(value)
end

local function raw_technology(raw, name)
  local technology = raw and raw.technology and raw.technology[name]
  if type(technology) ~= "table" then
    error("MIR historical continuation requires technology " .. name, 3)
  end
  return technology
end

local function raw_science(raw, name)
  local science = raw and raw.tool and raw.tool[name]
  if type(science) ~= "table" then
    error("MIR historical continuation requires science tool " .. name, 3)
  end
end

local function named_unit(technology, id)
  local unit = technology.unit
  if type(unit) ~= "table" or not finite(unit.count) or unit.count <= 0 then
    error("MIR historical continuation has no finite source count for " .. id, 3)
  end
  if not finite(unit.time) or unit.time <= 0 then
    error("MIR historical continuation has no source research time for " .. id, 3)
  end
  return unit
end

local function fixed_boundary(technology, expected, id)
  local maximum = technology.max_level
  -- Base's ordinary finite predecessors omit this field.  Factorio supplies
  -- their fixed native maximum from the technology identity, so an omitted
  -- raw field is an admitted finite boundary.  An explicit field belongs to
  -- a foreign override and must match the named historical boundary exactly.
  if maximum == nil then return end
  if maximum == "infinite" or type(maximum) ~= "number" or maximum ~= expected then
    error("MIR historical continuation has unexpected finite predecessor levels for " .. id, 3)
  end
end

local function preflight_source(row, raw)
  if raw and raw.technology and raw.technology[row.id] ~= nil then
    error("MIR historical continuation identity is already owned: " .. row.id, 3)
  end
  local predecessor, previous = raw_technology(raw, row.predecessor), raw_technology(raw, row.previous)
  if predecessor.max_level == "infinite" then
    error("MIR historical continuation refuses infinite predecessor " .. row.predecessor, 3)
  end
  if previous.max_level == "infinite" then
    error("MIR historical continuation refuses infinite predecessor " .. row.previous, 3)
  end
  -- The full-state snapshots resolve finite levels, but the corresponding
  -- base data-stage records omit max_level.  Admit that native default while
  -- rejecting an explicit foreign or infinite replacement.
  if not row.numeric then
    fixed_boundary(predecessor, row.level - 1, row.id)
    fixed_boundary(previous, row.level - 2, row.id)
  end
  local predecessor_unit, previous_unit = named_unit(predecessor, row.predecessor), named_unit(previous, row.previous)
  if predecessor_unit.count ~= row.expected_predecessor_count
      or previous_unit.count ~= row.expected_previous_count then
    error("MIR historical continuation has unexpected source costs for " .. row.id, 3)
  end
  if predecessor.order ~= row.order then
    error("MIR historical continuation has unexpected source order for " .. row.id, 3)
  end
  local has_icon = type(predecessor.icon) == "string" and predecessor.icon ~= ""
    or type(predecessor.icons) == "table" and #predecessor.icons > 0
  if not has_icon then error("MIR historical continuation has no source icon for " .. row.id, 3) end
  for _, name in ipairs(row.prerequisites) do raw_technology(raw, name) end
  for _, ingredient in ipairs(row.science) do raw_science(raw, ingredient[1]) end
  return predecessor, predecessor_unit, previous_unit
end

local function require_stream(values, row)
  local stream = values and values.base_extensions and values.base_extensions[row.family]
  if type(stream) ~= "table" then
    error("MIR historical continuation has no resolved base settings for " .. row.family, 3)
  end
  for _, field in ipairs({
    "enabled", "base_cost", "linear_increment", "growth_factor", "max_level", "research_time", "effect_percent",
  }) do
    if stream[field] == nil then
      error("MIR historical continuation base settings are missing " .. field .. " for " .. row.family, 3)
    end
  end
  if type(stream.enabled) ~= "boolean" or not integer(stream.base_cost) or stream.base_cost < 0
      or not integer(stream.linear_increment) or stream.linear_increment < 0
      or not finite(stream.growth_factor) or stream.growth_factor < 0
      or not integer(stream.max_level) or stream.max_level < 0
      or not integer(stream.research_time) or stream.research_time < 0
      or not finite(stream.effect_percent) or stream.effect_percent <= 0 then
    error("MIR invalid historical continuation base settings for " .. row.family, 3)
  end
  return stream
end

local function formula(row, stream, predecessor_unit, previous_unit)
  -- Historical target outputs retain the engine-visible unit formula form.
  return "1*(" .. cost.continuation(stream, row.level, predecessor_unit.count, previous_unit.count) .. ")"
end

local function effects(row, stream)
  local out = {}
  for index, authored in ipairs(row.effects) do
    local modifier = stream.effect_percent * authored.scale
    if not authored.absolute then modifier = modifier / 100 end
    local effect = {type=authored.type, modifier=modifier}
    if authored.ammo_category then effect.ammo_category = authored.ammo_category end
    out[index] = effect
  end
  return out
end

local function ingredients(science)
  local out = {}
  for index, ingredient in ipairs(science) do out[index] = {ingredient[1], ingredient[2]} end
  return out
end

local function presentation(output, predecessor)
  if type(predecessor.icons) == "table" and #predecessor.icons > 0 then
    output.icons = copy(predecessor.icons)
  else
    output.icon, output.icon_size = predecessor.icon, predecessor.icon_size
  end
  if predecessor.localised_name ~= nil then output.localised_name = copy(predecessor.localised_name) end
  if predecessor.localised_description ~= nil then output.localised_description = copy(predecessor.localised_description) end
end

local function numeric_technology(row, raw)
  local predecessor = preflight_source(row, raw)
  local output = {
    type="technology", name=row.id, order=row.order, prerequisites=copy(row.prerequisites),
    effects=effects(row, {effect_percent=4}),
    unit={count=row.unit_count, time=row.research_time, ingredients=ingredients(row.science)},
  }
  -- F013/F014 contain no base continuation controls. Keep their observed
  -- numeric finite rows without fabricating level, maximum, or formula fields.
  if row.family == "worker-robots-storage" then output.effects = {{type="worker-robot-storage", modifier=1}} end
  presentation(output, predecessor)
  return output
end

local function configured_maximum(row, stream)
  if stream.max_level == 0 then return "infinite", false end
  if stream.max_level < row.level then
    -- The historical planner omitted this identity. MIR5 retains it disabled
    -- so an upgrade cannot discard earned state; no invalid lower maximum is
    -- projected beneath a technology's fixed first level.
    return "infinite", true
  end
  return stream.max_level, stream.enabled == false
end

local function configured_technology(row, values, raw, contract)
  local predecessor, predecessor_unit, previous_unit = preflight_source(row, raw)
  local stream = require_stream(values, row)
  local maximum, retained_disabled = configured_maximum(row, stream)
  local research_time = stream.research_time == 0 and predecessor_unit.time or stream.research_time
  if not finite(research_time) or research_time <= 0 then
    error("MIR invalid historical continuation research time for " .. row.id, 3)
  end
  local output = {
    type="technology", name=row.id, order=row.order, prerequisites=copy(row.prerequisites),
    effects=effects(row, stream), level=row.level, upgrade=true, max_level=maximum,
    unit={count_formula=formula(row, stream, predecessor_unit, previous_unit),
      time=research_time, ingredients=ingredients(row.science)},
  }
  if contract.hidden ~= nil then output.hidden = contract.hidden end
  if contract.visible_when_disabled ~= nil then output.visible_when_disabled = contract.visible_when_disabled end
  if stream.enabled == false or retained_disabled then output.enabled = false end
  presentation(output, predecessor)
  return output
end

function M.technologies(target, values, raw)
  local contract = contracts.for_target(target)
  local out = {}
  for _, row in ipairs(contract.rows) do
    out[#out + 1] = contract.numeric
      and numeric_technology(row, raw)
      or configured_technology(row, values, raw, contract)
  end
  return out
end

function M.contract(target)
  return contracts.copy_target(target)
end

return M
