local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local competing_base_extensions = require("prototypes.mir.policy.competing_base_extensions")

local M = {}

local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

local function effect_value_to_string(value)
  local kind = type(value)
  if kind == "string" then return value end
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "table" then
    local parts = {}
    for k, v in pairs(value) do
      table.insert(parts, tostring(k) .. "=" .. effect_value_to_string(v))
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(value)
end

local function effects_signature(effects)
  local rows = {}
  for _, effect in ipairs(effects or {}) do
    local cols = {}
    for k, v in pairs(effect) do
      table.insert(cols, tostring(k) .. "=" .. effect_value_to_string(v))
    end
    table.sort(cols)
    table.insert(rows, table.concat(cols, ";"))
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

local function has_prereq(tech, prereq_name)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prereq_name then return true end
  end
  return false
end

function M.chain(chain_key)
  local pattern = "^" .. escape_pattern(chain_key) .. "%-(%d+)$"
  local levels, by_level = {}, {}
  local has_infinite = false
  for name, tech in pairs(data_raw.prototypes("technology")) do
    local level = tonumber(string.match(name, pattern))
    if level then
      if tech.max_level == "infinite" then has_infinite = true end
      table.insert(levels, level)
      by_level[level] = tech
    end
  end
  table.sort(levels)
  return levels, by_level, has_infinite
end

function M.technology(name)
  return data_raw.technology(name)
end

function M.find_equivalent_infinite_extension(previous_name, expected_effects)
  local expected_signature = effects_signature(expected_effects)
  for tech_name, tech in pairs(data_raw.prototypes("technology")) do
    if tech.max_level == "infinite" and tech_name ~= previous_name
      and not competing_base_extensions.ignores_existing_owner(tech_name) then
      if has_prereq(tech, previous_name) and effects_signature(tech.effects) == expected_signature then
        return tech_name
      end
    end
  end
  return nil
end

function M.find_any_infinite_extension(previous_name, new_name)
  for tech_name, tech in pairs(data_raw.prototypes("technology")) do
    if tech.max_level == "infinite" and tech_name ~= new_name then
      if has_prereq(tech, previous_name) then return tech_name end
    end
  end
  return nil
end

function M.previous_unit(base_level, by_level)
  if base_level <= 1 then return nil end
  local prev_level = base_level - 1
  while prev_level >= 1 do
    local prev = by_level[prev_level]
    if prev and prev.unit then return prev.unit end
    prev_level = prev_level - 1
  end
  return nil
end

function M.compute_growth_from_prev(last_unit, prev_unit)
  if not last_unit or not prev_unit then return nil end
  if not last_unit.count or not prev_unit.count then return nil end
  if prev_unit.count <= 0 then return nil end
  local ratio = last_unit.count / prev_unit.count
  if ratio < 1 then return nil end
  return ratio
end

function M.compute_growth_fallback(levels, by_level, base_level, last_count, prev_unit)
  if prev_unit and prev_unit.count and prev_unit.count > 0 and last_count and last_count > 0 then
    return last_count / prev_unit.count
  end
  if prev_unit == nil then
    local ratios = {}
    local prev = nil
    for _, level in ipairs(levels) do
      if level < base_level then
        local tech = by_level[level]
        if tech and tech.unit and tech.unit.count then
          if prev and prev.count and prev.count > 0 then
            table.insert(ratios, tech.unit.count / prev.count)
          end
          prev = tech.unit
        end
      end
    end
    if #ratios > 0 then
      local first = ratios[1]
      local consistent = true
      for index = 2, #ratios do
        if math.abs(ratios[index] - first) > 1e-6 then
          consistent = false
          break
        end
      end
      if consistent then return first end
    end
  end
  return nil
end

return M
