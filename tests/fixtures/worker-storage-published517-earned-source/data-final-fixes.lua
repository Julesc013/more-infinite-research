-- Read-only data-stage evidence for the assigned published-5.0.20017 source
-- tuple. This fixture neither patches MIR nor supplies a successor route.
local PREFIX = "[mir5-worker-storage-published517-earned-source]"
local TARGET = "mir-worker-storage-default-4"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "utility-science-pack"
}
local PREREQUISITES = {"worker-robots-storage-2", "utility-science-pack", "worker-robots-storage-3"}
local SETTINGS = {
  {name = "mir-enable-worker-robots-storage", value_type = "boolean", value = true},
  {name = "mir-max-level-worker-robots-storage", value_type = "number", value = 10},
  {name = "mir-cost-base-worker-robots-storage", value_type = "number", value = 200},
  {name = "mir-cost-linear-increment-worker-robots-storage", value_type = "number", value = 0},
  {name = "mir-cost-growth-worker-robots-storage", value_type = "number", value = 1.5},
  {name = "mir-research-time-worker-robots-storage", value_type = "number", value = 60},
  {name = "mir-effect-per-level-worker-robots-storage", value_type = "number", value = 1}
}

local function fail(message) error(PREFIX .. " " .. message) end
local function finite(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end
local function observed(value)
  local kind = type(value)
  if kind == "boolean" or kind == "number" or kind == "string" then return kind .. ":" .. tostring(value) end
  return kind
end
local function exact_rows(rows, expected, label)
  if type(rows) ~= "table" or #rows ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do
    local row = rows[index]
    if type(row) ~= "table" or row[1] ~= name or row[2] ~= 1 then fail(label .. " differs: " .. tostring(index)) end
  end
end
local function exact_names(rows, expected, label)
  if type(rows) ~= "table" or #rows ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do if rows[index] ~= name then fail(label .. " differs: " .. tostring(index)) end end
end

if type(mods) ~= "table" then fail("data-stage mods dictionary is required") end
local identities = {}
for name, version in pairs(mods) do
  if type(name) ~= "string" or type(version) ~= "string" then fail("mods must map strings") end
  identities[#identities + 1] = name .. "@" .. version
end
table.sort(identities)
log("[MIR_ACTIVE_MODS] " .. table.concat(identities, "|"))

if type(settings) ~= "table" or type(settings.startup) ~= "table" then fail("startup settings are required") end
local settings_rows = {}
for _, specification in ipairs(SETTINGS) do
  local row = settings.startup[specification.name]
  if type(row) ~= "table" then fail("missing setting " .. specification.name .. " observed=" .. observed(row)) end
  local value = row.value
  if type(value) ~= specification.value_type or (type(value) == "number" and not finite(value)) then
    fail("invalid setting " .. specification.name .. " observed=" .. observed(value))
  end
  if value ~= specification.value then fail("setting value differs: " .. specification.name) end
  settings_rows[#settings_rows + 1] = specification.name .. "=" .. observed(value)
end
log("[MIR_WORKER_STORAGE_SETTINGS] " .. table.concat(settings_rows, "|"))

local technology = data.raw.technology and data.raw.technology[TARGET]
if type(technology) ~= "table" then fail("published ordinary worker technology is absent") end
if technology.max_level ~= "infinite" or technology.level ~= 4 or technology.enabled == false or technology.hidden == true then
  fail("published ordinary worker role differs")
end
if technology.unit == nil or technology.unit.count_formula ~= "675*1.5^(L-4)" or technology.unit.time ~= 60 then
  fail("published ordinary worker unit differs")
end
exact_rows(technology.unit.ingredients, SCIENCE, "published ordinary worker science")
exact_names(technology.prerequisites, PREREQUISITES, "published ordinary worker prerequisite")
if type(technology.effects) ~= "table" or #technology.effects ~= 1
    or technology.effects[1].type ~= "worker-robot-storage" or technology.effects[1].modifier ~= 1 then
  fail("published ordinary worker effect differs")
end
log("[MIR_PUBLISHED517_EARNED_SOURCE] stage=data target=" .. TARGET
  .. "|formula=" .. technology.unit.count_formula .. "|time=" .. tostring(technology.unit.time)
  .. "|science=" .. table.concat(SCIENCE, ",") .. "|prerequisites=" .. table.concat(PREREQUISITES, ",")
  .. "|effect=worker-robot-storage:1")
