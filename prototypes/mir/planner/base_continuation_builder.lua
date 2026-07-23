local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

local PRESENTATION_FIELDS = {
  "icon",
  "icon_size",
  "icons",
  "order"
}

function M.continuation(base_technology, fields)
  if type(base_technology) ~= "table" then error("Base extension builder requires a technology prototype.", 2) end
  fields = fields or {}
  local technology = {
    type = "technology",
    name = assert(fields.name, "Base extension builder requires name."),
    localised_name = fields.localised_name,
    localised_description = fields.localised_description,
    prerequisites = deepcopy(fields.prerequisites or {}),
    effects = deepcopy(fields.effects or {}),
    unit = deepcopy(fields.unit or {}),
    max_level = fields.max_level,
    upgrade = fields.upgrade ~= false,
    level = fields.level
  }
  for _, field in ipairs(PRESENTATION_FIELDS) do
    if base_technology[field] ~= nil then technology[field] = deepcopy(base_technology[field]) end
  end
  if fields.order ~= nil then technology.order = fields.order end
  return technology
end

return M
