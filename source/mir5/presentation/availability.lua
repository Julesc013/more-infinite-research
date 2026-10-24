-- Bounded, authored availability explanations for the Research Library.
--
-- These describe only current, player-useful terminal dispositions.  They are
-- not catalogue rows, do not create technologies, and deliberately do not
-- reproduce the historical compiler's broad skip ledger.
local M = {}

local SPACE_AGE = "space-age"
local NATIVE_RESEARCH_PRODUCTIVITY = "research-productivity"
local LABORATORY_PRODUCTIVITY = "laboratory-productivity"
local LABORATORY_PRODUCTIVITY_CHANGE = 0.1
local EFFECT_TOLERANCE = 0.000001

-- These are terminal explanations for the two captured Bob material closures.
-- They are deliberately finite: the Library does not infer another material
-- family from a recipe, item, owner, setting, or installed mod.
local F200_BOB_ANGEL_REQUIRED = {
  "base", "angelsbioprocessing", "angelsbioprocessinggraphics", "angelspetrochem", "angelspetrochemgraphics",
  "angelsrefining", "angelsrefininggraphics", "angelssmelting", "angelssmeltinggraphics",
  "bobelectronics", "boblibrary", "bobores", "bobplates", "bobrevamp",
}

local F210_BOBTECH_ANGEL_REQUIRED = {
  "base", "space-age", "boblibrary", "bobores", "bobplates", "bobelectronics", "bobtech",
  "angelsrefining", "angelsrefininggraphics", "angelspetrochem", "angelspetrochemgraphics",
  "angelssmelting", "angelssmeltinggraphics",
}

local F210_BOB_CORE_REQUIRED = {
  "base", "space-age", "boblibrary", "bobores", "bobplates", "bobelectronics", "bobtech",
}

local F210_BOB_CORE_EXCLUDED = {
  "angelsbioprocessing", "angelsbioprocessinggraphics", "angelsrefining", "angelsrefininggraphics",
  "angelspetrochem", "angelspetrochemgraphics", "angelssmelting", "angelssmeltinggraphics",
  "Krastorio2", "Krastorio2Assets", "Krastorio2-spaced-out", "k2so-assets",
  "pycoalprocessing", "pyalienlife", "pyhightech",
}

local function withheld_material(family, reason)
  return {
    family = family,
    status = "not-added",
    reason = reason,
    emitted_id = "recipe-prod-" .. family .. "-1",
  }
end

local F200_BOB_ANGEL_WITHHELD = {
  withheld_material("research_material_lead", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_nickel", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_platinum", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_silver", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_zinc", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_bronze", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_brass", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_gunmetal", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_invar", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_cobalt_steel", "not-available-in-bob-angel-profile"),
  withheld_material("research_material_nitinol", "not-available-in-bob-angel-profile"),
}

local F210_BOBTECH_ANGEL_WITHHELD = {
  withheld_material("research_material_aluminium", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_brass", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_bronze", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_cobalt_steel", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_copper_tungsten", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_gold", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_lead", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_nickel", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_nitinol", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_silver", "not-available-in-bobtech-angel-profile"),
  withheld_material("research_material_titanium", "not-available-in-bobtech-angel-profile"),
}

local F210_BOB_CORE_WITHHELD = {
  withheld_material("research_material_aluminium", "not-available-in-bob-core-profile"),
  withheld_material("research_material_brass", "not-available-in-bob-core-profile"),
  withheld_material("research_material_cobalt_steel", "not-available-in-bob-core-profile"),
  withheld_material("research_material_gold", "not-available-in-bob-core-profile"),
  withheld_material("research_material_nickel", "not-available-in-bob-core-profile"),
  withheld_material("research_material_platinum", "not-available-in-bob-core-profile"),
  withheld_material("research_material_silver", "not-available-in-bob-core-profile"),
  withheld_material("research_material_titanium", "not-available-in-bob-core-profile"),
  withheld_material("research_material_zinc", "not-available-in-bob-core-profile"),
}

local BASE_WITHOUT_SPACE_AGE = {
  {
    family = "research_agricultural_growth_speed",
    status = "not-added",
    reason = "requires-space-age",
    required_mod = SPACE_AGE,
  },
  {
    family = "research_spoilage_preservation",
    status = "not-added",
    reason = "requires-space-age",
    required_mod = SPACE_AGE,
  },
}

local NATIVE_LAB_PRODUCTIVITY = {
  family = "research_lab_productivity",
  status = "not-added",
  reason = "native-research-productivity",
  native_owner = NATIVE_RESEARCH_PRODUCTIVITY,
}

local function copy(row)
  return {
    family = row.family,
    status = row.status,
    reason = row.reason,
    required_mod = row.required_mod,
    native_owner = row.native_owner,
  }
end

local function has_every(active_mods, names)
  if type(active_mods) ~= "table" then return false end
  for _, name in ipairs(names) do
    if active_mods[name] == nil then return false end
  end
  return true
end

local function is_f200_bob_angel(active_mods, target)
  if type(target) ~= "table" or target.id ~= "f200" or target.factorio_version ~= "2.0"
      or not has_every(active_mods, F200_BOB_ANGEL_REQUIRED) then
    return false
  end
  return active_mods[SPACE_AGE] == nil and active_mods.bobtech == nil
    and active_mods.Krastorio2 == nil and active_mods["Krastorio2-spaced-out"] == nil
end

local function is_f210_bobtech_angel(active_mods, target)
  if type(target) ~= "table" or target.id ~= "f210" or target.factorio_version ~= "2.1"
      or target.minimum_base ~= "2.1.23" or not has_every(active_mods, F210_BOBTECH_ANGEL_REQUIRED) then
    return false
  end
  return active_mods.Krastorio2 == nil and active_mods.Krastorio2Assets == nil
    and active_mods["Krastorio2-spaced-out"] == nil and active_mods["k2so-assets"] == nil
end

local function is_f210_bob_core(active_mods, target)
  if type(target) ~= "table" or target.id ~= "f210" or target.factorio_version ~= "2.1"
      or target.minimum_base ~= "2.1.23" or not has_every(active_mods, F210_BOB_CORE_REQUIRED) then
    return false
  end
  for _, name in ipairs(F210_BOB_CORE_EXCLUDED) do
    if active_mods[name] ~= nil then return false end
  end
  return true
end

-- Only a direct lookup by the exact authored early-stage identity is allowed.
-- A malformed force table is not evidence that an absent row should be shown.
local function emitted_technology_state(force, name)
  if force == nil then return false end
  local ok, technology = pcall(function()
    local technologies = force.technologies
    return technologies and technologies[name] or nil
  end)
  if not ok then return nil end
  if technology == nil then return false end
  local ok_valid, valid = pcall(function() return technology.valid end)
  if not ok_valid then return nil end
  return valid ~= false
end

-- Profile decoding belongs to the parse-time configuration boundary. The
-- optional input is that already-resolved stream map, so opening or searching
-- Availability never parses a profile or reads startup settings itself.
local function is_explicitly_disabled(row, effective_streams)
  local stream = type(effective_streams) == "table" and effective_streams[row.family] or nil
  return type(stream) == "table" and stream.enabled == false
end

local function normalized(value)
  if type(value) ~= "string" then return "" end
  return value:lower():gsub("[-_]", " ")
end

local function matches(row, query)
  local needle = normalized(query)
  if needle == "" then return true end
  local haystack = table.concat({
    normalized(row.family),
    normalized(row.status),
    normalized(row.reason),
    normalized(row.required_mod),
    normalized(row.native_owner),
  }, " ")
  return haystack:find(needle, 1, true) ~= nil
end

local function append_withheld(rows, definitions, force, query, effective_streams)
  for _, row in ipairs(definitions) do
    -- Do not describe an omission when the named technology really exists,
    -- including an intentionally disabled native technology.
    if emitted_technology_state(force, row.emitted_id) == false
        and not is_explicitly_disabled(row, effective_streams) and matches(row, query) then
      rows[#rows + 1] = copy(row)
    end
  end
end

local function has_space_age(active_mods)
  return type(active_mods) == "table" and active_mods[SPACE_AGE] ~= nil
end

local function supports_recipe_productivity(target)
  return type(target) == "table" and target.recipe_productivity == true
end

-- This is one direct named native read, not a catalogue traversal.  The
-- historical skip was justified only by the exact Space Age owner: one
-- laboratory-productivity effect at +10%.
local function has_native_lab_productivity(force)
  local ok, technology = pcall(function()
    local technologies = force and force.technologies
    return technologies and technologies[NATIVE_RESEARCH_PRODUCTIVITY] or nil
  end)
  if not ok or technology == nil then return false end
  local ok_valid, is_valid = pcall(function() return technology.valid end)
  if not ok_valid or is_valid == false then return false end

  local ok_prototype, prototype = pcall(function() return technology.prototype end)
  if not ok_prototype or prototype == nil then return false end
  local ok_effects, effects = pcall(function() return prototype.effects end)
  if not ok_effects or effects == nil then return false end

  local ok_effect, effect = pcall(function() return effects[1] end)
  if not ok_effect or effect == nil then return false end
  local ok_extra, extra = pcall(function() return effects[2] end)
  if not ok_extra or extra ~= nil then return false end
  local ok_fields, matches_contract = pcall(function()
    return effect.type == LABORATORY_PRODUCTIVITY
      and type(effect.modifier) == "number"
      and math.abs(effect.modifier - LABORATORY_PRODUCTIVITY_CHANGE) <= EFFECT_TOLERANCE
  end)
  return ok_fields and matches_contract
end

-- Returns detached descriptors for the Library's third visibility mode.  The
-- fields intentionally have no technology id: these are terminal explanations
-- for non-admitted families, not synthetic research identities.
function M.rows(active_mods, target, force, query, effective_streams)
  local rows = {}
  if not supports_recipe_productivity(target) then return rows end
  if not has_space_age(active_mods) then
    for _, row in ipairs(BASE_WITHOUT_SPACE_AGE) do
      if matches(row, query) then rows[#rows + 1] = copy(row) end
    end
  elseif has_native_lab_productivity(force) and matches(NATIVE_LAB_PRODUCTIVITY, query) then
    rows[#rows + 1] = copy(NATIVE_LAB_PRODUCTIVITY)
  end
  if is_f200_bob_angel(active_mods, target) then
    append_withheld(rows, F200_BOB_ANGEL_WITHHELD, force, query, effective_streams)
  elseif is_f210_bobtech_angel(active_mods, target) then
    append_withheld(rows, F210_BOBTECH_ANGEL_WITHHELD, force, query, effective_streams)
  elseif is_f210_bob_core(active_mods, target) then
    append_withheld(rows, F210_BOB_CORE_WITHHELD, force, query, effective_streams)
  end
  return rows
end

return M
