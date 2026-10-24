-- Draft MIR API v1 data-stage surface.  The public declaration subset is
-- deliberately smaller than Factorio's complete TechnologyPrototype schema:
-- callers supply a bounded cost and one supported native effect, while MIR
-- owns the presentation and constructs the only emitted prototype shape.
local generator = require("__more-infinite-research__/research/generator")
local target = require("__more-infinite-research__/platform/target")

local M = {}
local MAX_FAMILY = 64
local MAX_DEPTH = 16
local MAX_ENTRIES = 512
local MAX_STRING_BYTES = 4096
local MAX_UNIT_COUNT = 9007199254740991 -- largest lossless integer in Lua's double representation.
local MAX_INGREDIENT_AMOUNT = 65535
local MAX_EFFECT_VALUE = 1
local MIN_UNIT_TIME = 1 / 60
local MAX_UNIT_TIME = 3600000
local API_ICON = "__more-infinite-research__/thumbnail.png"
local API_ICON_SIZE = 288

-- F200's TechnologyUnit contract accepts ToolPrototypes only.  F210 widened
-- ResearchIngredient to ItemPrototype, so retain its complete explicit
-- concrete prototype-type set instead of treating arbitrary data.raw tables
-- as science inputs.  This is an admission list, not a discovery scan.
local F210_ITEM_TYPES = {
  "ammo", "armor", "blueprint", "blueprint-book", "capsule", "copy-paste-tool",
  "deconstruction-item", "gun", "item", "item-with-entity-data",
  "item-with-inventory", "item-with-label", "item-with-tags", "module",
  "rail-planner", "repair-tool", "selection-tool", "space-platform-starter-pack",
  "spidertron-remote", "tool", "upgrade-item",
}
local TECHNOLOGY_FIELDS = {
  type = true, name = true, prerequisites = true, unit = true, effects = true,
}
local UNIT_FIELDS = {count = true, ingredients = true, time = true}
local CRAFTING_EFFECT_FIELDS = {type = true, modifier = true}

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

local function bounded_identifier(value, label)
  bounded_string(value, label)
  if value:find("[%z\1-\31\127]") then
    fail("invalid_definition", label .. " contains a control byte")
  end
  return value
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

local function only_fields(value, allowed, label)
  for key in pairs(value) do
    if type(key) ~= "string" or not allowed[key] then
      fail("invalid_definition", label .. " contains unsupported field " .. tostring(key))
    end
  end
end

local function positive_integer(value, maximum, label)
  if not finite(value) or value < 1 or value ~= math.floor(value) or value > maximum then
    fail("invalid_definition", label .. " must be a positive integer within the supported range")
  end
  return value
end

local function item_exists(raw, name)
  if target.id == "f200" then
    return raw.tool and raw.tool[name] ~= nil
  end
  for _, item_type in ipairs(F210_ITEM_TYPES) do
    if raw[item_type] and raw[item_type][name] then return true end
  end
  return false
end

local function admitted_prerequisites(value)
  if value == nil then return {} end
  local count = dense_array(value, "prerequisites", MAX_ENTRIES)
  local seen, out = {}, {}
  for index = 1, count do
    local name = value[index]
    bounded_identifier(name, "prerequisites[" .. index .. "]")
    if seen[name] then fail("invalid_definition", "prerequisites contains duplicate " .. name) end
    seen[name] = true
    out[index] = name
  end
  return out
end

local function admitted_ingredients(value, raw)
  local count = dense_array(value, "unit.ingredients", MAX_ENTRIES)
  if count == 0 then fail("invalid_definition", "unit.ingredients must not be empty") end
  local seen, out = {}, {}
  for index = 1, count do
    local ingredient = value[index]
    if dense_array(ingredient, "unit.ingredients[" .. index .. "]", 2) ~= 2 then
      fail("invalid_definition", "unit.ingredients[" .. index .. "] must contain exactly name and amount")
    end
    local name = ingredient[1]
    bounded_identifier(name, "unit.ingredients[" .. index .. "][1]")
    if seen[name] then
      fail("invalid_definition", "unit.ingredients contains duplicate " .. name)
    end
    if not item_exists(raw, name) then
      fail("missing_target", "science ingredient " .. name)
    end
    seen[name] = true
    out[index] = {name, positive_integer(ingredient[2], MAX_INGREDIENT_AMOUNT,
      "unit.ingredients[" .. index .. "][2]")}
  end
  return out
end

local function admitted_unit(value, raw)
  if type(value) ~= "table" or getmetatable(value) ~= nil then
    fail("invalid_definition", "unit must be a plain table")
  end
  only_fields(value, UNIT_FIELDS, "unit")
  if not finite(value.time) or value.time < MIN_UNIT_TIME or value.time > MAX_UNIT_TIME then
    fail("invalid_definition", "unit.time is outside the supported tick-representable range")
  end
  return {
    count = positive_integer(value.count, MAX_UNIT_COUNT, "unit.count"),
    ingredients = admitted_ingredients(value.ingredients, raw),
    time = value.time,
  }
end

local function admitted_effects(value, allow_crafting)
  if value == nil then return {} end
  local count = dense_array(value, "effects", MAX_ENTRIES)
  if not allow_crafting and count ~= 0 then
    fail("invalid_definition", "add_productivity accepts no caller effects")
  end
  local out = {}
  for index = 1, count do
    local effect = value[index]
    if type(effect) ~= "table" or getmetatable(effect) ~= nil then
      fail("invalid_definition", "effects[" .. index .. "] must be a plain table")
    end
    only_fields(effect, CRAFTING_EFFECT_FIELDS, "effects[" .. index .. "]")
    if effect.type ~= "character-crafting-speed" then
      fail("invalid_definition", "effects[" .. index .. "] is not an admitted API effect")
    end
    if not finite(effect.modifier) or effect.modifier <= 0 or effect.modifier > MAX_EFFECT_VALUE then
      fail("invalid_definition", "effects[" .. index .. "].modifier is outside the supported range")
    end
    out[index] = {type = "character-crafting-speed", modifier = effect.modifier}
  end
  return out
end

local function admitted_technology(value, raw, allow_crafting)
  if type(value) ~= "table" or getmetatable(value) ~= nil then
    fail("invalid_definition", "technology must be a plain table")
  end
  only_fields(value, TECHNOLOGY_FIELDS, "technology")
  if value.type ~= "technology" then fail("invalid_definition", "technology.type must be technology") end
  bounded_identifier(value.name, "technology.name")
  return {
    type = "technology",
    name = value.name,
    -- The packaged 288px thumbnail is present in every selected edition. It
    -- keeps caller-controlled asset paths outside the public admission shape.
    icon = API_ICON,
    icon_size = API_ICON_SIZE,
    prerequisites = admitted_prerequisites(value.prerequisites),
    unit = admitted_unit(value.unit, raw),
    effects = admitted_effects(value.effects, allow_crafting),
  }
end

local function external_creation_available()
  return target.id == "f200" or target.id == "f210"
end

local function require_creation_capability()
  if not external_creation_available() then
    fail("unsupported_capability", "public technology creation is implemented only for F200 and F210")
  end
end

local function data_stage()
  local stage = rawget(_G, "data")
  if type(stage) ~= "table" or type(stage.raw) ~= "table" or type(stage.extend) ~= "function" then
    fail("unsupported_capability", "data-stage publication is unavailable")
  end
  return stage
end

local function error_code(message)
  if message:find("duplicate technology", 1, true) then return "duplicate_identity" end
  if message:find("missing", 1, true) then return "missing_target" end
  return "invalid_definition"
end

local function publish(prototypes, stage)
  local ok, result = pcall(generator.install, prototypes, stage)
  if not ok then fail(error_code(tostring(result)), tostring(result)) end
  local names = {}
  for index, prototype in ipairs(prototypes) do names[index] = prototype.name end
  return names
end

local function admit_family(prototypes, raw, allow_crafting)
  local copied = copy_family(prototypes)
  local owned = {}
  for index = 1, #copied do
    owned[index] = admitted_technology(copied[index], raw, allow_crafting)
  end
  return owned
end

local function admitted_recipe_names(value)
  local count = dense_array(value, "recipe names", MAX_FAMILY)
  if count == 0 then fail("invalid_definition", "recipe names must not be empty") end
  local seen, out = {}, {}
  for index = 1, count do
    local recipe = value[index]
    bounded_identifier(recipe, "recipe names[" .. index .. "]")
    if seen[recipe] then fail("duplicate_identity", "recipe names contain " .. recipe) end
    seen[recipe] = true
    out[index] = recipe
  end
  return out
end

function M.get_version()
  return {major = 1, minor = 0, product = target.distribution_version}
end

function M.get_capabilities()
  local creation = external_creation_available()
  return {
    technology_creation = creation,
    technology_family = creation,
    recipe_productivity = creation and target.recipe_productivity == true,
    research_query = false
  }
end

function M.add_technologies(prototypes)
  require_creation_capability()
  local stage = data_stage()
  return publish(admit_family(prototypes, stage.raw, true), stage)
end

function M.add_technology(prototype)
  return M.add_technologies({prototype})[1]
end

function M.add_productivity(prototype, recipe_names, change)
  require_creation_capability()
  if target.recipe_productivity ~= true then fail("unsupported_capability", "recipe productivity is unavailable") end
  if not finite(change) or change <= 0 or change > MAX_EFFECT_VALUE then
    fail("invalid_definition", "change is outside the supported range")
  end
  local stage = data_stage()
  local recipes = admitted_recipe_names(recipe_names)
  local owned = admit_family({prototype}, stage.raw, false)[1]
  for _, recipe in ipairs(recipes) do
    owned.effects[#owned.effects + 1] = {
      type = "change-recipe-productivity", recipe = recipe, change = change
    }
  end
  return publish({owned}, stage)[1]
end

return M
