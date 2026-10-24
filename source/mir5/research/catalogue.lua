-- Authored MIR identities for the Library and runtime cap admission. This
-- declaration list never discovers a technology: each row names one emitted
-- technology or one exact admitted native owner.
local modern_catalogue = require("compatibility.modern_catalogue")
local target = require("platform.target")

local M = {}
local GEAR_ID = "recipe-prod-research_gears-1"
local AGRICULTURE_ID = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE_ID = "recipe-prod-research_spoilage_preservation-1"

function M.gear_id() return GEAR_ID end

local active_mods = script and script.active_mods or mods or {}
local space_age_active = type(active_mods) == "table" and active_mods["space-age"] ~= nil
local ordinary_profile = type(active_mods) == "table" and active_mods.Krastorio2 == nil
  and active_mods["Krastorio2-spaced-out"] == nil and active_mods.Krastorio2Assets == nil
  and active_mods["k2so-assets"] == nil
local k2_base_profile = modern_catalogue.is_k2_base(active_mods)
local k2so_profile = modern_catalogue.is_k2so(active_mods)
local bob_tech_profile = require("compatibility.bob_tech_profile")
local bob_tech_active = bob_tech_profile.applies(active_mods)
local bob_core_profile = require("compatibility.bob_core_profile")
local bob_core_active = bob_core_profile.applies(active_mods)

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR catalogue declaration contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function stream_settings(family)
  return {"ips-enable-" .. family, "ips-cost-base-" .. family, "ips-cost-linear-increment-" .. family,
    "ips-cost-growth-" .. family, "ips-max-level-" .. family, "ips-research-time-" .. family,
    "ips-effect-per-level-" .. family}
end
local function continuation_settings(key)
  return {"mir-enable-" .. key, "mir-cost-base-" .. key, "mir-cost-linear-increment-" .. key,
    "mir-cost-growth-" .. key, "mir-max-level-" .. key, "mir-research-time-" .. key,
    "mir-effect-per-level-" .. key}
end
local function locale_key(value)
  if type(value) == "string" then return value end
  return type(value) == "table" and value[1] or nil
end
local function first_recipe(definition)
  local effect = definition.effects and definition.effects[1]
  return effect and effect.recipe or nil
end
local function named_productivity_recipes(routes)
  local out, seen = {}, {}
  if type(routes) ~= "table" then error("MIR catalogue material routes are invalid", 3) end
  for index, route in ipairs(routes) do
    local recipe = type(route) == "table" and route.recipe or nil
    if type(recipe) ~= "string" or recipe == "" or seen[recipe] then
      error("MIR catalogue material routes must name unique recipes", 3)
    end
    seen[recipe], out[index] = true, recipe
  end
  if #out == 0 then error("MIR catalogue material routes are empty", 3) end
  return out
end
-- The F200 4.7 controller recorded its cap ownership before the newer
-- transported finalizer existed.  Keep that predecessor identity on exactly
-- the named generated stream/base-continuation rows selected for F200; no
-- runtime scan or generic legacy-policy fallback gets this authority.
local function historical_binding(source, operation)
  if target.id == "f200" and (source == "generated-stream" or source == "base-continuation") then
    return {source=source, operation="runtime-settings-transport", target="f200",
      policy_transport="settings-derived-v3", ownership_kind="settings-derived-v3"}
  end
  return {source=source, operation=operation}
end

local function generated_row(id, family, order, locale, recipe)
  return {id=id, family=family, progression=1, native_order=order, setting="ips-enable-" .. family,
    cap_setting="ips-max-level-" .. family, settings=stream_settings(family), recipe=recipe, locale_key=locale,
    ownership_kind="authored_generated", legacy_binding=historical_binding("generated-stream", "emit")}
end

local function imersite_rows()
  local contract = require("research.k2_imersite")
  local settings = stream_settings(contract.stream)
  return {
    {id=contract.early.id, family=contract.early.family, progression=contract.early.first_level,
      native_order=contract.early.order, setting="ips-enable-" .. contract.stream,
      cap_setting="ips-max-level-" .. contract.stream, settings=settings,
      recipe=contract.effect.recipe, locale_key="description.productivity-bonus", ownership_kind="authored_generated",
      legacy_binding=historical_binding("generated-stream", "emit")},
    {id=contract.continuation.id, family=contract.continuation.family, progression=contract.continuation.first_level,
      native_order=contract.continuation.order, setting="ips-enable-" .. contract.stream,
      cap_setting="ips-max-level-" .. contract.stream, settings=settings,
      recipe=contract.effect.recipe, locale_key="description.productivity-bonus", ownership_kind="authored_generated",
      legacy_binding=historical_binding("generated-stream", "emit")},
  }
end

local function bob_tech_rows()
  if not bob_tech_active then return {} end
  local rows = {}
  for _, definition in ipairs(require("research.bob_tech_materials")) do
    for _, stage in ipairs({definition.early, definition.continuation}) do
      if stage then
        local row = generated_row(stage.id, definition.key, stage.order,
          "description.productivity-bonus", definition.routes[1].recipe)
        row.progression = stage.first_level or 1
        row.productivity_ceiling = definition.productivity_ceiling
        -- Runtime cap admission receives the finite authored routes that this
        -- profile bound in data-final.  Tin has no unproven level-four row.
        row.productivity_recipes = named_productivity_recipes(definition.routes)
        rows[#rows + 1] = row
      end
    end
  end
  return rows
end

local function bob_core_rows()
  if not bob_core_active then return {} end
  local rows = {}
  for _, definition in ipairs(require("research.bob_core_materials")) do
    for _, stage in ipairs({definition.early, definition.continuation}) do
      local row = generated_row(stage.id, definition.key, stage.order,
        "description.productivity-bonus", definition.routes[1].recipe)
      row.progression = stage.first_level or 1
      row.productivity_ceiling = definition.productivity_ceiling
      row.productivity_recipes = named_productivity_recipes(definition.routes)
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function py_material_rows()
  local rows = {}
  for _, definition in ipairs(require("research.py_materials")) do
    for _, stage in ipairs({definition.early, definition.continuation}) do
      local row = generated_row(stage.id, definition.key, stage.order,
        "description.productivity-bonus", definition.routes[1].recipe)
      row.progression = stage.first_level or 1
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function static_rows()
  local rows = {generated_row(GEAR_ID, "research_gears", "p[research_gears]",
    "technology-name.more-infinite-research.research_gears", "iron-gear-wheel")}
  for _, row in ipairs(bob_tech_rows()) do rows[#rows + 1] = row end
  for _, row in ipairs(bob_core_rows()) do rows[#rows + 1] = row end
  local selected
  if ordinary_profile or k2_base_profile or k2so_profile then selected = modern_catalogue.select(active_mods) end
  if not selected then
    if space_age_active then
      rows[#rows + 1] = generated_row(AGRICULTURE_ID, "research_agricultural_growth_speed",
        "p[research_agricultural_growth_speed]", "technology-name.more-infinite-research.research_agricultural_growth_speed")
      rows[#rows + 1] = generated_row(SPOILAGE_ID, "research_spoilage_preservation",
        "p[research_spoilage_preservation]", "technology-name.more-infinite-research.research_spoilage_preservation")
    end
    return rows
  end
  for index = 1, #selected.definitions do
    local definition = selected.definitions[index]
    rows[#rows + 1] = generated_row("recipe-prod-" .. definition.key .. "-1", definition.family,
      definition.order, locale_key(definition.localised_name), first_recipe(definition))
  end
  if active_mods["atan-air-scrubbing"] or active_mods["atan-ash"] then
    if require("compatibility.atan_profile").select(active_mods, require("platform.target")) then
      for _, definition in ipairs(require("research.atan_productivity").runtime_rows) do
        rows[#rows + 1] = generated_row("recipe-prod-" .. definition.family .. "-1", definition.family,
          "p[" .. definition.family .. "]", nil, definition.recipe)
      end
    end
  end
  if space_age_active then
    rows[#rows + 1] = generated_row(AGRICULTURE_ID, "research_agricultural_growth_speed",
      "p[research_agricultural_growth_speed]", "technology-name.more-infinite-research.research_agricultural_growth_speed")
    rows[#rows + 1] = generated_row(SPOILAGE_ID, "research_spoilage_preservation",
      "p[research_spoilage_preservation]", "technology-name.more-infinite-research.research_spoilage_preservation")
  end
  for _, continuation in ipairs(selected.continuations) do
    rows[#rows + 1] = {id=continuation.id, family=continuation.family, progression=continuation.level,
      native_order=continuation.order or "", setting="mir-enable-" .. continuation.setting_key,
      cap_setting="mir-max-level-" .. continuation.setting_key, settings=continuation_settings(continuation.setting_key),
      locale_key=locale_key(continuation.localised_name), ownership_kind="authored_generated",
      legacy_binding=historical_binding(continuation.source, continuation.operation)}
  end
  if selected.k2_imersite then
    for _, row in ipairs(imersite_rows()) do rows[#rows +1] = row end
    for _, definition in ipairs(require("research.k2_materials")) do
      rows[#rows + 1] = generated_row(definition.name, definition.key, definition.order,
        "description.productivity-bonus", definition.routes[1].recipe)
    end
  end
  if selected.bob_angel then
    for _, definition in ipairs(require("research.bob_angel_materials")) do
      for _, stage in ipairs({definition.early, definition.continuation}) do
        local row = generated_row(stage.id, definition.key, stage.order,
          "description.productivity-bonus", definition.routes[1].recipe)
        row.progression = stage.first_level or 1
        row.productivity_ceiling = definition.productivity_ceiling
        -- Runtime caps read only this finite declared route list. It names
        -- neither a foreign family nor a classifier: data-final already
        -- selected and bound these exact recipes before Factorio exposes their
        -- effective LuaRecipePrototype productivity caps.
        row.productivity_recipes = named_productivity_recipes(definition.routes)
        rows[#rows + 1] = row
      end
    end
  end
  if selected.py_coal then
    for _, row in ipairs(py_material_rows()) do rows[#rows + 1] = row end
  end
  if space_age_active then
    for _, owner in ipairs(modern_catalogue.native_owners(active_mods)) do
      rows[#rows + 1] = {id=owner.id, family=owner.family, progression=1, native_order="", setting="ips-enable-" .. owner.family,
        cap_setting=owner.setting, settings=stream_settings(owner.family), ownership_kind="nativeowner",
        native_owner_identity=owner.id, native_admission=copy(owner.admission),
        legacy_binding={source="native-owner", operation="preserve_native_owner"}}
    end
  end
  return rows
end

function M.declared()
  local rows = static_rows()
  local out = {}
  for index = 1, #rows do out[index] = copy(rows[index]) end
  return out
end

return M
