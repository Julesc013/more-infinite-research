-- Private diagnostic addition only: compose as data.lua beside the existing
-- early controlled-stop fixture. Never add to a normal acceptance/player ZIP.
local name = "mir-fixture-sif-technology-reload-sentinel"
if data.raw.technology[name] ~= nil then
  error("MIR fixture technology-reload: identity already exists")
end

-- An inert technology changes the native technology world without changing
-- any existing prototype, force, research, saved witness or migration file.
data:extend({{
  type = "technology",
  name = name,
  icon = "__base__/graphics/technology/automation-1.png",
  icon_size = 256,
  enabled = false,
  hidden = true,
  upgrade = false,
  prerequisites = {},
  effects = {},
  unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}},
}})
