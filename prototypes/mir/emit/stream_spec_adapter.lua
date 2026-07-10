local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local stream_spec = require("prototypes.mir.domain.streams.stream_spec")
local technology_builder = require("prototypes.mir.emit.technology_builder")

local M = {}

function M.emit(key, spec, fields)
  local stream = stream_spec.from_stream_record({
    manifest_id = spec.manifest_id,
    stream_key = key,
    technology_name = "recipe-prod-" .. key .. "-1",
    localised_name = fields.localised_name,
    localised_description = fields.localised_description,
    icons = fields.icons,
    effects = fields.effects,
    science = fields.ingredients,
    prerequisites = fields.prerequisites,
    count_formula = fields.count_formula,
    research_time = fields.research_time,
    upgrade = true,
    max_level = fields.max_level,
    order = "p[" .. key .. "]",
    level = 1,
    migration_policy = spec.migration_policy
  })

  local technology = technology_builder.emit(stream)
  generated_registry.register(technology.name, { kind = "stream", key = key })
  return technology
end

return M
