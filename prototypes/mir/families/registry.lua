local deepcopy = require("prototypes.mir.core.deepcopy")
local raw = require("prototypes.mir.families.rules")

local M = {}
local canonical = nil

local FORBIDDEN_KEYS = {
  data = true,
  data_raw = true,
  mod = true,
  mods = true,
  version = true,
  versions = true
}

local function assert_data_only(value, path)
  if type(value) == "function" then error("FamilyRule must be data-only: " .. path, 3) end
  if type(value) ~= "table" then return end
  for key, child in pairs(value) do
    if FORBIDDEN_KEYS[key] then error("FamilyRule contains forbidden field: " .. path .. "." .. key, 3) end
    assert_data_only(child, path .. "." .. tostring(key))
  end
end

local function build()
  if canonical then return canonical end
  if raw.schema ~= 1 then error("FamilyRule registry schema must be 1", 2) end
  assert_data_only(raw, "family_rules")

  local rules, ids = {}, {}
  for _, rule in ipairs(raw.rules or {}) do
    if type(rule.id) ~= "string" or rule.id == "" then error("FamilyRule id is required", 2) end
    if ids[rule.id] then error("Duplicate FamilyRule id: " .. rule.id, 2) end
    if rule.capability ~= "recipe-productivity" then
      error("Unsupported FamilyRule capability: " .. tostring(rule.capability), 2)
    end
    if rule.mode ~= "attach-existing" and rule.mode ~= "proposal-only" then
      error("Unsupported FamilyRule mode: " .. tostring(rule.mode), 2)
    end
    if rule.mode == "attach-existing" and not rule.target_stream then
      error("Attach-existing FamilyRule requires target_stream: " .. rule.id, 2)
    end
    ids[rule.id] = true
    table.insert(rules, deepcopy(rule))
  end
  table.sort(rules, function(a, b) return a.id < b.id end)
  canonical = {schema = 1, rules = rules}
  return canonical
end

function M.snapshot()
  return deepcopy(build())
end

return M

