-- Draft MIR API v1 data-stage surface. Calls publish immediately in the
-- caller's current data stage; no contributions are retained for a finalizer.
local generator = require("__more-infinite-research__/research/generator")

local M = {}
local MAX_FAMILY = 64
local MAX_DEPTH = 16
local MAX_ENTRIES = 512
local MAX_STRING_BYTES = 4096

local function fail(code, message)
  error("MIR_API:" .. code .. ": " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function bounded_string(value, label)
  if type(value) ~= "string" or value == "" or #value > MAX_STRING_BYTES then
    fail("invalid_definition", label .. " must be a bounded nonempty string")
  end
end

local function dense_array(value, label, maximum)
  if type(value) ~= "table" or getmetatable(value) ~= nil then
    fail("invalid_definition", label .. " must be a plain dense array")
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      fail("invalid_definition", label .. " must be a plain dense array")
    end
    count = count + 1
    if count > maximum then fail("invalid_definition", label .. " exceeds its input limit") end
  end
  for index = 1, count do
    if value[index] == nil then fail("invalid_definition", label .. " has a missing entry") end
  end
  return count
end

local function copy_value(value, state, depth, label)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then return value end
  if kind == "number" then
    if not finite(value) then fail("invalid_definition", label .. " contains a nonfinite number") end
    return value
  end
  if kind == "string" then
    if #value > MAX_STRING_BYTES then fail("invalid_definition", label .. " contains an oversized string") end
    return value
  end
  if kind ~= "table" then fail("invalid_definition", label .. " contains an executable or unsupported value") end
  if getmetatable(value) ~= nil then fail("invalid_definition", label .. " contains a metatable") end
  if depth > MAX_DEPTH then fail("invalid_definition", label .. " exceeds its nesting limit") end
  if state.active[value] then fail("invalid_definition", label .. " contains a cycle") end
  state.active[value] = true
  local copy = {}
  for key, child in pairs(value) do
    state.entries = state.entries + 1
    if state.entries > MAX_ENTRIES then fail("invalid_definition", label .. " exceeds its input limit") end
    local key_kind = type(key)
    if key_kind == "number" then
      if not finite(key) then fail("invalid_definition", label .. " has a nonfinite key") end
    elseif key_kind == "string" then
      if #key > MAX_STRING_BYTES then fail("invalid_definition", label .. " has an oversized key") end
    else
      fail("invalid_definition", label .. " has an unsupported key")
    end
    copy[key] = copy_value(child, state, depth + 1, label)
  end
  state.active[value] = nil
  return copy
end

local function copy_family(prototypes)
  local count = dense_array(prototypes, "technologies", MAX_FAMILY)
  if count == 0 then fail("invalid_definition", "technologies must not be empty") end
  local state, copied = {entries = 0, active = {}}, {}
  for index = 1, count do
    copied[index] = copy_value(prototypes[index], state, 1, "technologies[" .. index .. "]")
  end
  return copied
end

local function error_code(message)
  if message:find("duplicate technology", 1, true) then return "duplicate_identity" end
  if message:find("missing", 1, true) then return "missing_target" end
  return "invalid_definition"
end

local function publish(prototypes)
  local stage = rawget(_G, "data")
  if type(stage) ~= "table" or type(stage.raw) ~= "table" or type(stage.extend) ~= "function" then
    fail("unsupported_capability", "data-stage publication is unavailable")
  end
  local ok, result = pcall(generator.install, prototypes, stage)
  if not ok then fail(error_code(tostring(result)), tostring(result)) end
  local names = {}
  for index, prototype in ipairs(prototypes) do names[index] = prototype.name end
  return names
end

function M.get_version()
  return {major = 1, minor = 0, product = "5.0.21000"}
end

function M.get_capabilities()
  return {
    technology_creation = true,
    technology_family = true,
    recipe_productivity = true,
    research_query = false
  }
end

function M.add_technologies(prototypes)
  return publish(copy_family(prototypes))
end

function M.add_technology(prototype)
  return M.add_technologies({prototype})[1]
end

function M.add_productivity(prototype, recipe_names, change)
  if not finite(change) then fail("invalid_definition", "change must be finite") end
  local recipe_count = dense_array(recipe_names, "recipe names", MAX_FAMILY)
  if recipe_count == 0 then fail("invalid_definition", "recipe names must not be empty") end

  local seen_recipes = {}
  for index = 1, recipe_count do
    local recipe = recipe_names[index]
    bounded_string(recipe, "recipe names[" .. index .. "]")
    if seen_recipes[recipe] then fail("duplicate_identity", "recipe names contain " .. recipe) end
    seen_recipes[recipe] = true
  end

  local owned = copy_family({prototype})[1]
  if owned.effects == nil then owned.effects = {} end
  local effect_count = dense_array(owned.effects, "effects", MAX_ENTRIES)
  for index = 1, effect_count do
    if type(owned.effects[index]) ~= "table" then
      fail("invalid_definition", "effects[" .. index .. "] must be a table")
    end
  end
  for _, recipe in ipairs(recipe_names) do
    for _, effect in ipairs(owned.effects) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
        fail("duplicate_identity", "recipe productivity already targets " .. recipe)
      end
    end
    owned.effects[#owned.effects + 1] = {
      type = "change-recipe-productivity", recipe = recipe, change = change
    }
  end
  return publish({owned})[1]
end

return M
