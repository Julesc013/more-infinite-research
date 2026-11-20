local prefix = "[mir5-worker-storage-se-cap-ten-observer]"

if type(mods) ~= "table" then
  error(prefix .. " Factorio data-stage mods dictionary is required")
end

local identities = {}
for name, version in pairs(mods) do
  if type(name) ~= "string" or type(version) ~= "string" then
    error(prefix .. " mods must map string names to string versions")
  end
  identities[#identities + 1] = name .. "@" .. version
end
table.sort(identities)
log("[MIR_ACTIVE_MODS] " .. table.concat(identities, "|"))

if type(settings) ~= "table" or type(settings.startup) ~= "table" then
  error(prefix .. " Factorio startup settings dictionary is required")
end

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
  if kind == "boolean" or kind == "number" or kind == "string" then
    return kind .. ":" .. tostring(value)
  end
  return kind
end

local rows = {}
for _, specification in ipairs(requested) do
  local row = settings.startup[specification.name]
  if type(row) ~= "table" then
    error(prefix .. " " .. specification.name .. " missing setting row observed=" .. observed(row))
  end
  local value = row.value
  if type(value) ~= specification.value_type then
    error(prefix .. " " .. specification.name .. " wrong type expected=" .. specification.value_type .. " observed=" .. observed(value))
  end
  if specification.value_type == "number" and (value ~= value or value == math.huge or value == -math.huge) then
    error(prefix .. " " .. specification.name .. " nonfinite observed=" .. observed(value))
  end
  rows[#rows + 1] = specification.name .. "=" .. observed(value)
end

log("[MIR_WORKER_STORAGE_SETTINGS] " .. table.concat(rows, "|"))
