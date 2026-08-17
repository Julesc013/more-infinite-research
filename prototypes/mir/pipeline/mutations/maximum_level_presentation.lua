local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local compiler_orchestrator = require("prototypes.mir.pipeline.compiler_orchestrator")

local M = {}

local function finite_maximum(value)
  local maximum = tonumber(value)
  if not maximum or maximum <= 0 then return nil end
  return math.floor(maximum)
end

local function technology_name(technology)
  return technology.localised_name or {"technology-name." .. tostring(technology.name)}
end

local function cap_label(source, technology)
  if source == "base-continuation" then
    return {"mod-setting-name.mir-max-level", technology_name(technology)}
  end
  return {"mod-setting-name.ips-max-level-stream", technology_name(technology)}
end

local function append_cap_description(technology, source, maximum)
  local description = technology.localised_description
  local prefix = description and {"", description, "\n"} or {""}
  table.insert(prefix, cap_label(source, technology))
  table.insert(prefix, ": ")
  table.insert(prefix, tostring(maximum))
  return prefix
end

local function bindings(plan)
  local out = {}
  for _, row in ipairs(plan.stream_plan.rows or {}) do
    if row.action == "emit" then
      table.insert(out, {
        technology = row.technology_name,
        selected = row.planned_max_level,
        source = "generated-stream"
      })
    elseif row.action == "adopt" and row.adoption then
      table.insert(out, {
        technology = row.adoption.owner,
        selected = row.adoption.planned_max_level,
        source = "native-owner"
      })
    end
  end
  for _, operation in ipairs(plan.base_extension_operations or {}) do
    table.insert(out, {
      technology = operation.technology_name,
      selected = operation.planned_max_level,
      source = "base-continuation"
    })
  end
  table.sort(out, function(left, right) return left.technology < right.technology end)
  return out
end

function M.apply(context)
  local plan = compiler_orchestrator.compile(context)
  local applied = {}
  for _, binding in ipairs(bindings(plan)) do
    local maximum = finite_maximum(binding.selected)
    local technology = data_raw.technology(binding.technology)
    if maximum and technology then
      if technology.max_level == "infinite" then
        technology.show_levels_info = false
        technology.visible_when_disabled = true
        technology.localised_description = append_cap_description(
          technology, binding.source, maximum)
        table.insert(applied, binding.technology .. "=" .. tostring(maximum))
      else
        log("[more-infinite-research] Maximum-level presentation refused"
          .. " technology=" .. tostring(binding.technology)
          .. " selected=" .. tostring(maximum)
          .. " final-observed=" .. tostring(technology.max_level)
          .. " reason=late_prototype_maximum_conflict.")
      end
    end
  end
  log("[more-infinite-research] Applied truthful finite-cap presentation"
    .. " count=" .. tostring(#applied)
    .. " technologies=" .. table.concat(applied, ",") .. ".")
end

return M
