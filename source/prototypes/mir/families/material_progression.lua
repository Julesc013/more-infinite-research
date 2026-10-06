-- Shared staged declaration contract for named material families.
--
-- A Factorio technology has one science-ingredient set for every level.  The
-- released `-1` material technologies consequently retain their three early
-- levels, while a later technology can be planned separately from level four.
-- This module is declaration and validation authority only; the stream
-- compiler owns deciding whether the observed recipes, owners, laboratories,
-- and productivity caps qualify that continuation for emission.
local M = {}

M.schema = 1
M.kind = "material-recipe-productivity-staged-continuation"
M.legacy_first_level = 1
M.legacy_last_level = 3
M.continuation_first_level = M.legacy_last_level + 1

local MATERIAL_STREAM_KEYS = {
  "research_material_aluminium",
  "research_material_gold",
  "research_material_lead",
  "research_material_nickel",
  "research_material_platinum",
  "research_material_silver",
  "research_material_tin",
  "research_material_titanium",
  "research_material_copper_tungsten",
  "research_material_zinc",
  "research_material_bronze",
  "research_material_brass",
  "research_material_gunmetal",
  "research_material_invar",
  "research_material_cobalt_steel",
  "research_material_nitinol"
}

-- This is deliberately separate from the reviewed Bob/Angel family.  The
-- current K2/K2SO evidence admits only the MIR-owned powder route; its
-- caller must still apply the exact current tuple guard before attaching the
-- declaration to the stream.  In particular, the native crystal owner and
-- the witnessed withheld K2 routes never enter this set.
local K2_213_CONTINUATION_STREAM_KEYS = {
  "research_material_imersite"
}

-- These declarations can extend only an already admitted MIR-owned early
-- stage. They grant no recipe permission, graph exception or native-owner
-- adoption. Imersite retains its separate exact-profile attachment policy.
local K2_MATERIAL_CONTINUATION_STREAM_KEYS = {
  "research_material_rare_metals",
  "research_material_silicon",
  "research_material_glass",
  "research_material_black_paving",
  "research_material_white_paving"
}

local ANGEL_PETROCHEM_STREAM_KEYS = {
  "research_material_nitric_acid",
  "research_material_hydrochloric_acid",
  "research_material_hydrofluoric_acid",
  "research_material_glycerol"
}

local MATERIAL_STREAM_KEY_SET = {}
for _, key in ipairs(MATERIAL_STREAM_KEYS) do MATERIAL_STREAM_KEY_SET[key] = true end

local K2_213_CONTINUATION_STREAM_KEY_SET = {}
for _, key in ipairs(K2_213_CONTINUATION_STREAM_KEYS) do
  K2_213_CONTINUATION_STREAM_KEY_SET[key] = true
end

local K2_MATERIAL_CONTINUATION_STREAM_KEY_SET = {}
for _, key in ipairs(K2_MATERIAL_CONTINUATION_STREAM_KEYS) do
  K2_MATERIAL_CONTINUATION_STREAM_KEY_SET[key] = true
end

local STAGED_MATERIAL_STREAM_KEY_SET = {}
local ANGEL_PETROCHEM_STREAM_KEY_SET = {}
for key in pairs(MATERIAL_STREAM_KEY_SET) do STAGED_MATERIAL_STREAM_KEY_SET[key] = true end
for key in pairs(K2_213_CONTINUATION_STREAM_KEY_SET) do
  STAGED_MATERIAL_STREAM_KEY_SET[key] = true
end
for key in pairs(K2_MATERIAL_CONTINUATION_STREAM_KEY_SET) do
  STAGED_MATERIAL_STREAM_KEY_SET[key] = true
end
for _, key in ipairs(ANGEL_PETROCHEM_STREAM_KEYS) do
  ANGEL_PETROCHEM_STREAM_KEY_SET[key] = true
  STAGED_MATERIAL_STREAM_KEY_SET[key] = true
end

local function only_fields(value, allowed)
  for key in pairs(value or {}) do
    if not allowed[key] then return false end
  end
  return true
end

local function technology_name(key, first_level)
  return "recipe-prod-" .. key .. "-" .. tostring(first_level)
end

function M.material_stream_keys()
  local out = {}
  for index, key in ipairs(MATERIAL_STREAM_KEYS) do out[index] = key end
  return out
end

function M.k2_213_continuation_stream_keys()
  local out = {}
  for index, key in ipairs(K2_213_CONTINUATION_STREAM_KEYS) do out[index] = key end
  return out
end

function M.k2_material_stream_keys()
  local out = {}
  for index, key in ipairs(K2_MATERIAL_CONTINUATION_STREAM_KEYS) do out[index] = key end
  return out
end

function M.angel_petrochem_stream_keys()
  local out = {}
  for index, key in ipairs(ANGEL_PETROCHEM_STREAM_KEYS) do out[index] = key end
  return out
end

function M.legacy_technology_name(key)
  return technology_name(key, M.legacy_first_level)
end

function M.continuation_technology_name(key)
  return technology_name(key, M.continuation_first_level)
end

local legacy_allowed = {
  technology_name = true,
  first_level = true,
  last_level = true,
  preserve_identity = true,
  preserve_completed_levels = true,
  preserve_active_research = true,
  preserve_queue = true,
  preserve_fractional_progress = true
}

local continuation_allowed = {
  technology_name = true,
  first_level = true,
  prerequisite_technology = true,
  effect_domain = true,
  effect_change = true,
  science_policy = true,
  laboratory_policy = true,
  research_cost_policy = true,
  maximum_level_policy = true,
  maximum_level_scope = true,
  maximum_level_setting = true,
  maximum_level_default = true,
  native_owner_policy = true,
  no_headroom_policy = true
}

function M.validate(key, progression)
  if not STAGED_MATERIAL_STREAM_KEY_SET[key] then return false, "unsupported-material-stream" end
  if type(progression) ~= "table" or progression.schema ~= M.schema or progression.kind ~= M.kind
      or not only_fields(progression, {schema = true, kind = true, legacy = true, continuation = true}) then
    return false, "invalid-staged-progression-schema"
  end

  local legacy = progression.legacy
  if type(legacy) ~= "table" or not only_fields(legacy, legacy_allowed)
      or legacy.technology_name ~= M.legacy_technology_name(key)
      or legacy.first_level ~= M.legacy_first_level or legacy.last_level ~= M.legacy_last_level
      or legacy.preserve_identity ~= true or legacy.preserve_completed_levels ~= true
      or legacy.preserve_active_research ~= true or legacy.preserve_queue ~= true
      or legacy.preserve_fractional_progress ~= true then
    return false, "invalid-legacy-stage"
  end

  local continuation = progression.continuation
  if type(continuation) ~= "table" or not only_fields(continuation, continuation_allowed)
      or continuation.technology_name ~= M.continuation_technology_name(key)
      or continuation.first_level ~= M.continuation_first_level
      or continuation.prerequisite_technology ~= legacy.technology_name
      or continuation.effect_domain ~= "same-qualified-recipes"
      or continuation.effect_change ~= "same-qualified-change"
      or continuation.science_policy ~= "derive-qualified-route-late-frontier"
      or continuation.laboratory_policy ~= "require-reachable-late-frontier-lab"
      or continuation.research_cost_policy ~= "anchor-at-continuation-first-level"
      or continuation.maximum_level_policy ~= "finite-highest-useful-recipe-level"
      or continuation.maximum_level_scope ~= "absolute-combined-stage-level"
      or continuation.maximum_level_setting ~= "ips-max-level-" .. key
      or continuation.maximum_level_default ~= 0
      or continuation.native_owner_policy ~= "require-mir-generated-legacy-owner"
      or continuation.no_headroom_policy ~= "withhold-continuation" then
    return false, "invalid-continuation-stage"
  end
  return true
end

function M.legacy_max_level(key, spec, configured)
  if not spec.staged_progression then return configured end
  local valid, reason = M.validate(key, spec.staged_progression)
  if not valid then error("Invalid material continuation " .. key .. ": " .. reason, 2) end
  if type(configured) == "number" then
    return math.min(configured, spec.staged_progression.legacy.last_level)
  end
  return spec.staged_progression.legacy.last_level
end

local function attach(key, spec)
  if type(spec) ~= "table" then
    error("Material staged progression requires a stream declaration table.", 2)
  end
  if spec.staged_progression ~= nil then
    error("Material staged progression already exists for " .. key .. ".", 2)
  end
  if spec.max_level ~= M.legacy_last_level then
    error("Material staged progression requires legacy max_level " .. tostring(M.legacy_last_level)
      .. " for " .. key .. ".", 2)
  end

  spec.staged_progression = {
    schema = M.schema,
    kind = M.kind,
    legacy = {
      technology_name = M.legacy_technology_name(key),
      first_level = M.legacy_first_level,
      last_level = M.legacy_last_level,
      preserve_identity = true,
      preserve_completed_levels = true,
      preserve_active_research = true,
      preserve_queue = true,
      preserve_fractional_progress = true
    },
    continuation = {
      technology_name = M.continuation_technology_name(key),
      first_level = M.continuation_first_level,
      prerequisite_technology = M.legacy_technology_name(key),
      effect_domain = "same-qualified-recipes",
      effect_change = "same-qualified-change",
      science_policy = "derive-qualified-route-late-frontier",
      laboratory_policy = "require-reachable-late-frontier-lab",
      research_cost_policy = "anchor-at-continuation-first-level",
      -- Recipe productivity has a finite per-recipe maximum.  The compiler
      -- may emit later levels only through the highest observed useful level;
      -- this declaration deliberately never claims an unbounded effect.
      maximum_level_policy = "finite-highest-useful-recipe-level",
      maximum_level_scope = "absolute-combined-stage-level",
      maximum_level_setting = "ips-max-level-" .. key,
      -- Zero is the established settings representation of an unbounded
      -- configured cap. The recipe-headroom policy still supplies a finite
      -- effective maximum, while an existing explicit finite setting stays
      -- an absolute cap over both stages.
      maximum_level_default = 0,
      native_owner_policy = "require-mir-generated-legacy-owner",
      no_headroom_policy = "withhold-continuation"
    }
  }
  local valid, reason = M.validate(key, spec.staged_progression)
  if not valid then error("Material staged progression is invalid for " .. key .. ": " .. reason .. ".", 2) end
  return spec
end

function M.attach(key, spec)
  if not MATERIAL_STREAM_KEY_SET[key] then
    error("Material staged progression does not support stream " .. tostring(key) .. ".", 2)
  end
  return attach(key, spec)
end

-- The declaration is intentionally opt-in.  Productivity stream assembly
-- supplies the exact base/K2/K2SO tuple guard; this module only prevents a
-- different K2 stream from inheriting Imersite's reviewed continuation.
function M.attach_k2_213_continuation(key, spec)
  if not K2_213_CONTINUATION_STREAM_KEY_SET[key] then
    error("K2 2.1.3 material continuation does not support stream " .. tostring(key) .. ".", 2)
  end
  return attach(key, spec)
end

function M.attach_k2_material_continuation(key, spec)
  if not K2_MATERIAL_CONTINUATION_STREAM_KEY_SET[key] then
    error("K2 material continuation does not support stream " .. tostring(key) .. ".", 2)
  end
  return attach(key, spec)
end

function M.attach_angel_petrochem_continuation(key, spec)
  if not ANGEL_PETROCHEM_STREAM_KEY_SET[key] then
    error("Angel petrochem continuation does not support stream " .. tostring(key) .. ".", 2)
  end
  return attach(key, spec)
end

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0
    and value ~= math.huge
end

-- The bound is over research productivity, not machine/module productivity.
-- A family remains useful through the last level that still changes at least
-- one qualified recipe. A configured cap is an absolute technology level.
function M.highest_useful_level(effects, recipe_lookup, configured_cap)
  if type(effects) ~= "table" or type(recipe_lookup) ~= "function" then
    return nil, "invalid-material-effect-domain"
  end
  if configured_cap ~= "infinite" and (not finite_nonnegative(configured_cap)
      or configured_cap < 1 or configured_cap ~= math.floor(configured_cap)) then
    return nil, "invalid-material-configured-cap"
  end

  local maximum, count = 0, 0
  for _, effect in ipairs(effects) do
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or type(effect.recipe) ~= "string" or effect.recipe == ""
        or not finite_nonnegative(effect.change) or effect.change <= 0 then
      return nil, "invalid-material-effect"
    end
    local recipe = recipe_lookup(effect.recipe)
    if type(recipe) ~= "table" then return nil, "material-recipe-unavailable" end
    local limit = recipe.maximum_productivity
    if limit == nil then limit = 3.0 end -- Factorio RecipePrototype default.
    if not finite_nonnegative(limit) then return nil, "invalid-material-recipe-cap" end
    local highest = math.ceil(limit / effect.change - 0.000000001)
    -- Only the emitted effective cap needs to fit the level domain. A finite
    -- configured cap can bound recipe headroom beyond that domain without
    -- granting an oversized or unbounded continuation.
    local effective_highest = configured_cap ~= "infinite"
      and math.min(highest, configured_cap) or highest
    if effective_highest > 2147483647 then return nil, "material-level-domain-exceeded" end
    maximum = math.max(maximum, highest)
    count = count + 1
  end
  if count == 0 then return nil, "no-material-effects" end
  if maximum <= M.legacy_last_level then return nil, "no-continuation-headroom" end
  if configured_cap ~= "infinite" and configured_cap <= M.legacy_last_level then
    return nil, "configured-material-cap-before-continuation"
  end
  if configured_cap ~= "infinite" then maximum = math.min(maximum, configured_cap) end
  return maximum
end

return M
