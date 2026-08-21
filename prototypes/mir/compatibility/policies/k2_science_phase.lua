local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {
  policy_id = "K2SciencePhasePolicyV2"
}

local REQUIRED_SCIENCE_PACKS = {
  "automation-science-pack",
  "chemical-science-pack",
  "kr-advanced-tech-card",
  "kr-basic-tech-card",
  "kr-matter-tech-card",
  "kr-singularity-tech-card",
  "logistic-science-pack",
  "military-science-pack",
  "production-science-pack",
  "space-science-pack",
  "utility-science-pack"
}

local PROFILES = {
  {
    id = "factorio-2.1-k2so",
    target = "f210",
    required_mods = {
      base = {minimum = "2.1.0", maximum_exclusive = "2.2.0"},
      Krastorio2 = {minimum = "2.1.2", maximum_exclusive = "2.1.3"},
      ["Krastorio2-spaced-out"] = {minimum = "2.0.11", maximum_exclusive = "2.0.14"}
    },
    forbidden_mods = {},
    required_science_packs = {
      "automation-science-pack",
      "chemical-science-pack",
      "kr-advanced-tech-card",
      "kr-basic-tech-card",
      "kr-matter-tech-card",
      "kr-singularity-tech-card",
      "logistic-science-pack",
      "military-science-pack",
      "production-science-pack",
      "space-science-pack",
      "utility-science-pack"
    }
  },
  {
    id = "factorio-2.0-k2so-standalone",
    target = "f200",
    required_mods = {
      base = {minimum = "2.0.73", maximum_exclusive = "2.1.0"},
      ["Krastorio2-spaced-out"] = {minimum = "1.6.21", maximum_exclusive = "1.6.22"}
    },
    forbidden_mods = {"Krastorio2"},
    required_science_packs = {
      "automation-science-pack",
      "chemical-science-pack",
      "kr-advanced-tech-card",
      "kr-matter-tech-card",
      "kr-singularity-tech-card",
      "logistic-science-pack",
      "military-science-pack",
      "production-science-pack",
      "space-science-pack",
      "utility-science-pack"
    }
  }
}

local EARLY_PACKS = {
  ["kr-basic-tech-card"] = true,
  ["automation-science-pack"] = true,
  ["logistic-science-pack"] = true,
  ["military-science-pack"] = true,
  ["chemical-science-pack"] = true
}

local BASIC_PACK = "kr-basic-tech-card"

local PHASE_ONE_TRIGGERS = {
  ["production-science-pack"] = true,
  ["utility-science-pack"] = true
}

local PHASE_TWO_TRIGGERS = {
  ["kr-advanced-tech-card"] = true,
  ["space-science-pack"] = true,
  ["kr-matter-tech-card"] = true,
  ["kr-singularity-tech-card"] = true
}

local function ingredient_name(ingredient)
  return type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
end

local function parse_version(version)
  local major, minor, patch = string.match(tostring(version or ""), "^(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return {tonumber(major), tonumber(minor), tonumber(patch)}
end

local function compare_versions(left, right)
  local left_parts, right_parts = parse_version(left), parse_version(right)
  if not left_parts or not right_parts then return nil end
  for index = 1, 3 do
    if left_parts[index] < right_parts[index] then return -1 end
    if left_parts[index] > right_parts[index] then return 1 end
  end
  return 0
end

local function version_in_range(version, range)
  local minimum = compare_versions(version, range.minimum)
  local maximum = compare_versions(version, range.maximum_exclusive)
  return minimum ~= nil and maximum ~= nil and minimum >= 0 and maximum < 0
end

local function profile_mods_match(profile, active_mods)
  for mod_name, range in pairs(profile.required_mods) do
    if not version_in_range(active_mods[mod_name], range) then
      return false, "mod-version-outside-envelope:" .. mod_name
    end
  end
  for _, mod_name in ipairs(profile.forbidden_mods) do
    if active_mods[mod_name] ~= nil then return false, "forbidden-mod-present:" .. mod_name end
  end
  return true
end

local function capability_material(capabilities)
  local available = capabilities and capabilities.science_packs or {}
  local identities = {}
  for _, name in ipairs(REQUIRED_SCIENCE_PACKS) do
    identities[name] = available[name] == true
  end
  return {science_packs = identities}
end

local function profile_capabilities_match(profile, capabilities)
  local material = capability_material(capabilities)
  local missing = {}
  for _, name in ipairs(profile.required_science_packs) do
    if material.science_packs[name] ~= true then missing[#missing + 1] = name end
  end
  return #missing == 0, material, missing
end

local function qualification(active_mods, capabilities)
  active_mods = active_mods or {}
  local rejections = {}
  for _, profile in ipairs(PROFILES) do
    local mods_match, reason = profile_mods_match(profile, active_mods)
    if mods_match then
      local capabilities_match, material, missing = profile_capabilities_match(profile, capabilities)
      if capabilities_match then
        return profile, material, {}, rejections
      end
      rejections[#rejections + 1] = profile.id .. ":missing-science-identities"
      return nil, material, missing, rejections
    end
    rejections[#rejections + 1] = profile.id .. ":" .. reason
  end
  return nil, capability_material(capabilities), {}, rejections
end

function M.required_science_packs()
  return deepcopy(REQUIRED_SCIENCE_PACKS)
end

function M.profiles()
  return deepcopy(PROFILES)
end

function M.applies(active_mods, capabilities)
  return qualification(active_mods, capabilities) ~= nil
end

function M.normalize(ingredients, active_mods, capabilities)
  local original = deepcopy(ingredients or {})
  local profile, capability_facts, missing, rejections = qualification(active_mods, capabilities)
  local decision = {
    policy_id = M.policy_id,
    status = "not-applicable",
    applicable = false,
    changed = false,
    matched_profile = profile and profile.id or nil,
    qualified_target = profile and profile.target or nil,
    capability_fingerprint = fingerprint.of(capability_facts),
    missing_science_identities = deepcopy(missing),
    rejection_reasons = deepcopy(rejections),
    removed_packs = {}
  }
  if not profile then return original, decision end

  decision.applicable = true
  local present, phase_one, phase_two = {}, false, false
  for _, ingredient in ipairs(original) do
    local name = ingredient_name(ingredient)
    if name then
      present[name] = true
      phase_one = phase_one or PHASE_ONE_TRIGGERS[name] == true
      phase_two = phase_two or PHASE_TWO_TRIGGERS[name] == true
    end
  end

  local remove = {}
  if phase_one then remove[BASIC_PACK] = true end
  if phase_two then
    for name in pairs(EARLY_PACKS) do remove[name] = true end
  end

  local normalized, removed_seen = {}, {}
  for _, ingredient in ipairs(original) do
    local name = ingredient_name(ingredient)
    if name and remove[name] then
      if present[name] and not removed_seen[name] then
        removed_seen[name] = true
        decision.removed_packs[#decision.removed_packs + 1] = name
      end
    else
      normalized[#normalized + 1] = deepcopy(ingredient)
    end
  end
  table.sort(decision.removed_packs)

  if #normalized == 0 and #original > 0 then
    decision.status = "blocked-empty-result"
    return original, decision
  end
  decision.changed = #normalized ~= #original
  decision.status = decision.changed and "normalized" or "already-normalized"
  return normalized, decision
end

return M
