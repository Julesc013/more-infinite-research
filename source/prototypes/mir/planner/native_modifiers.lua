local D = require("prototypes.mir.report.diagnostics_sink")
local table_utils = require("prototypes.mir.core.table")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

local ignored_fields = {
  change = true,
  effect_description = true,
  icon = true,
  icons = true,
  modifier = true,
  type = true
}

function M.identity(effect)
  if not effect or not effect.type then return nil end
  if effect.type == "nothing" or effect.type == "change-recipe-productivity" then return nil end

  local fields = {}
  for _, field in ipairs(table_utils.sorted_keys(effect)) do
    if not ignored_fields[field] then
      local value = effect[field]
      local value_type = type(value)
      if value_type == "string" or value_type == "number" or value_type == "boolean" then
        table.insert(fields, field .. "=" .. tostring(value))
      end
    end
  end

  local target = "global"
  if #fields > 0 then target = table.concat(fields, ",") end
  return effect.type .. "|" .. target, target
end

function M.existing_infinite_techs(identity)
  local owners = {}
  if not identity then return owners end

  for tech_name, tech in pairs(data_raw.prototypes("technology")) do
    if tech.max_level == "infinite" and not string.find(tech_name, "^recipe%-prod%-") then
      for _, effect in ipairs(tech.effects or {}) do
        local existing_identity = M.identity(effect)
        if existing_identity == identity then
          table.insert(owners, tech_name)
          break
        end
      end
    end
  end

  table.sort(owners)
  return owners
end

function M.record_overlaps(key, effects)
  local seen = {}

  for _, effect in ipairs(effects or {}) do
    local identity, target = M.identity(effect)
    if identity and not seen[identity] then
      seen[identity] = true
      local owners = M.existing_infinite_techs(identity)
      if #owners > 0 then
        D.native_modifier_overlap({
          key = key,
          status = "diagnostic",
          reason = "existing_infinite_native_modifier",
          effect = effect.type,
          target = target,
          owners = table.concat(owners, ",")
        })
      end
    end
  end
end

return M
