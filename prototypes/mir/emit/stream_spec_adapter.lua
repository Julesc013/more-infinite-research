local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local stream_spec = require("prototypes.mir.domain.streams.stream_spec")
local technology_builder = require("prototypes.mir.emit.technology_builder")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}

function M.emit(design)
  technology_design.validate(design)
  local identity = design.design.identity.value
  local effects = design.design.effects.value
  local progression = design.design.progression.value
  local cost = design.design.cost.value
  local presentation = design.design.presentation.value
  local ownership = design.design.ownership.value
  local runtime_contracts = design.design.runtime_contracts.value
  local key = identity.stream_key
  local stream = stream_spec.from_stream_record({
    manifest_id = identity.manifest_id,
    stream_key = key,
    technology_name = identity.technology_name,
    localised_name = presentation.localised_name,
    localised_description = presentation.localised_description,
    icons = presentation.icons,
    effects = effects,
    science = progression.science,
    prerequisites = progression.prerequisites,
    count_formula = cost.count_formula,
    research_time = cost.research_time,
    upgrade = runtime_contracts.upgrade,
    max_level = cost.max_level,
    order = presentation.order,
    level = presentation.level,
    enabled = presentation.enabled,
    hidden = presentation.hidden,
    migration_policy = ownership.migration_policy
  })

  local technology = technology_builder.emit(stream)
  generated_registry.register(technology.name, { kind = "stream", key = key })
  return technology
end

return M
