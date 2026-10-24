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
function M.rows(active_mods, target, force, query)
  local rows = {}
  if not supports_recipe_productivity(target) then return rows end
  if not has_space_age(active_mods) then
    for _, row in ipairs(BASE_WITHOUT_SPACE_AGE) do
      if matches(row, query) then rows[#rows + 1] = copy(row) end
    end
  elseif has_native_lab_productivity(force) and matches(NATIVE_LAB_PRODUCTIVITY, query) then
    rows[#rows + 1] = copy(NATIVE_LAB_PRODUCTIVITY)
  end
  return rows
end

return M
