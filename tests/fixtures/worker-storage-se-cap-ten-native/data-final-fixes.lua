-- The full actor replaces the data-only observer in later profiles.  It logs
-- actual selection and loaded File-setting values but deliberately does not
-- fail a candidate's five-pack construction: configuration must observe that
-- real migration-adverse state before any fixture work can begin.
local PREFIX = "[mir5-worker-storage-se-cap-ten-native]"
local TARGET = "worker-robots-storage-4"
local requested = {
  {name = "mir-enable-worker-robots-storage", value_type = "boolean"},
  {name = "mir-max-level-worker-robots-storage", value_type = "number"},
  {name = "mir-cost-base-worker-robots-storage", value_type = "number"},
  {name = "mir-cost-linear-increment-worker-robots-storage", value_type = "number"},
  {name = "mir-cost-growth-worker-robots-storage", value_type = "number"},
  {name = "mir-research-time-worker-robots-storage", value_type = "number"},
  {name = "mir-effect-per-level-worker-robots-storage", value_type = "number"}
}

local function observed(value)
  local kind = type(value)
  if kind == "boolean" or kind == "number" or kind == "string" then return kind .. ":" .. tostring(value) end
  return kind
end

if type(mods) ~= "table" then error(PREFIX .. " data-stage mods dictionary is required") end
local identities = {}
for name, version in pairs(mods) do
  if type(name) ~= "string" or type(version) ~= "string" then error(PREFIX .. " mods must map strings") end
  identities[#identities + 1] = name .. "@" .. version
end
table.sort(identities)
log("[MIR_ACTIVE_MODS] " .. table.concat(identities, "|"))

if type(settings) ~= "table" or type(settings.startup) ~= "table" then error(PREFIX .. " startup settings are required") end
local settings_rows = {}
for _, specification in ipairs(requested) do
  local row = settings.startup[specification.name]
  if type(row) ~= "table" then error(PREFIX .. " missing setting " .. specification.name .. " observed=" .. observed(row)) end
  local value = row.value
  if type(value) ~= specification.value_type then error(PREFIX .. " wrong setting type " .. specification.name .. " observed=" .. observed(value)) end
  if specification.value_type == "number" and (value ~= value or value == math.huge or value == -math.huge) then
    error(PREFIX .. " nonfinite setting " .. specification.name)
  end
  settings_rows[#settings_rows + 1] = specification.name .. "=" .. observed(value)
end
log("[MIR_WORKER_STORAGE_SETTINGS] " .. table.concat(settings_rows, "|"))

local technology = data.raw.technology and data.raw.technology[TARGET]
if type(technology) ~= "table" then error(PREFIX .. " worker technology is absent") end
local ingredients, effects = {}, {}
for _, row in ipairs(technology.unit and technology.unit.ingredients or {}) do
  if type(row) == "table" and type(row[1]) == "string" and type(row[2]) == "number" then ingredients[#ingredients + 1] = row[1] .. ":" .. tostring(row[2]) end
end
for _, row in ipairs(technology.effects or {}) do
  if type(row) == "table" and type(row.type) == "string" then effects[#effects + 1] = row.type .. ":" .. tostring(row.modifier) end
end
table.sort(ingredients); table.sort(effects)
log("[MIR_SE_CARGO_CONSTRUCTION] name=" .. TARGET .. "|prerequisite=" .. tostring(technology.prerequisites and technology.prerequisites[1])
  .. "|formula=" .. tostring(technology.unit and technology.unit.count_formula) .. "|time=" .. tostring(technology.unit and technology.unit.time)
  .. "|ingredients=" .. table.concat(ingredients, ",") .. "|effects=" .. table.concat(effects, ","))
