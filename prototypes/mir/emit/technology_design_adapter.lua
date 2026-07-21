local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}

function M.emit(design, registration)
  technology_design.validate(design)
  local kind = design.materialization.kind
  if kind ~= "create" and kind ~= "continuation" then
    error("TechnologyDesign emitter cannot materialize kind " .. tostring(kind) .. ".", 2)
  end
  local technology = technology_design.prototype_projection(design, {validated = true})
  technology.type = "technology"
  if data_raw.technology(technology.name) then
    error("TechnologyDesign output identity already exists: " .. tostring(technology.name), 2)
  end
  data_raw.extend({deepcopy(technology)})
  registration = registration or {}
  generated_registry.register(technology.name, {
    kind = registration.kind or (kind == "continuation" and "base_extension" or "stream"),
    key = registration.key or design.design.identity.value.stream_key
  })
  return technology
end

return M
