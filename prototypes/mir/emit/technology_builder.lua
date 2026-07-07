local M = {}
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local function require_field(spec, field)
  if spec[field] == nil then
    error("StreamSpec missing required emitter field: " .. field, 3)
  end
end

local function validate(spec)
  if type(spec) ~= "table" then error("StreamSpec must be a table", 3) end
  if spec.schema ~= 1 then error("StreamSpec schema must be 1", 3) end

  require_field(spec, "manifest_id")
  require_field(spec, "stream_key")
  require_field(spec, "technology_name")
  require_field(spec, "effects")
  require_field(spec, "science")
  require_field(spec, "prerequisites")
  require_field(spec, "migration_policy")
end

function M.prototype(spec)
  validate(spec)

  return {
    type = "technology",
    name = spec.technology_name,
    localised_name = spec.localised_name,
    localised_description = spec.localised_description,
    icons = spec.icons,
    effects = spec.effects,
    prerequisites = spec.prerequisites,
    unit = {
      count_formula = spec.count_formula,
      ingredients = spec.science,
      time = spec.research_time
    },
    upgrade = spec.upgrade ~= false,
    max_level = spec.max_level,
    order = spec.order,
    level = spec.level or 1
  }
end

function M.emit(spec)
  local technology = M.prototype(spec)
  data_raw.extend({ technology })
  return technology
end

return M
