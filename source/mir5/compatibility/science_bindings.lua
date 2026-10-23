-- Explicit target names and progression boundaries for MIR research science.
-- This is a compatibility binding, never a proof that an arbitrary mod pack
-- can make or research a listed science item.
local M = {}

local MODERN_BASE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack"
}

local SPACE_AGE = {
  "agricultural-science-pack", "metallurgic-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack",
  "promethium-science-pack"
}

local KNOWN_TARGETS = {
  f013 = true, f014 = true, f015 = true, f016 = true, f017 = true,
  f100 = true, f110 = true, f200 = true, f210 = true
}

-- The delivered K2SO normalization was an exact science-phase contract.  It
-- is intentionally not inferred from a Krastorio marker: another revision
-- keeps its authored vector unless it receives a separately reviewed row.
local K2SO_PHASE_V8 = {
  -- This phase rule is narrower than ordinary catalogue K2SO admission.  Its
  -- published vector was observed with every marker below, so a partial tuple
  -- or a later archive with the same names keeps its authored ingredients.
  profile = {
    base = "2.1.23",
    ["space-age"] = "2.1.23",
    Krastorio2 = "2.1.4",
    ["Krastorio2-spaced-out"] = "2.0.19",
    Krastorio2Assets = "2.1.0",
    ["k2so-assets"] = "1.0.7"
  },
  basic = "kr-basic-tech-card",
  early = {
    "kr-basic-tech-card", "automation-science-pack", "logistic-science-pack",
    "military-science-pack", "chemical-science-pack"
  },
  phase_one = {"production-science-pack", "utility-science-pack"},
  phase_two = {
    "kr-advanced-tech-card", "space-science-pack", "kr-matter-tech-card",
    "kr-singularity-tech-card"
  }
}

local function copy_list(source)
  local out = {}
  for index, value in ipairs(source or {}) do out[index] = value end
  return out
end

local function exact_profile(mods, expected)
  if type(mods) ~= "table" then return false end
  for name, version in pairs(expected) do
    if mods[name] ~= version then return false end
  end
  return true
end

local function add_unique(out, seen, value)
  if not seen[value] then seen[value] = true; out[#out + 1] = value end
end

local function native_aliases(id)
  if id == "f013" or id == "f014" then
    return {
      ["automation-science-pack"] = "science-pack-1",
      ["logistic-science-pack"] = "science-pack-2",
      ["chemical-science-pack"] = "science-pack-3",
      ["production-science-pack"] = "alien-science-pack",
      ["military-science-pack"] = "alien-science-pack",
      ["utility-science-pack"] = "alien-science-pack",
      ["space-science-pack"] = "alien-science-pack"
    }
  end
  if id == "f015" or id == "f016" then
    return {
      ["automation-science-pack"] = "science-pack-1",
      ["logistic-science-pack"] = "science-pack-2",
      ["chemical-science-pack"] = "science-pack-3",
      ["utility-science-pack"] = "high-tech-science-pack"
    }
  end
  return {}
end

local function name_for(aliases, role)
  return aliases[role] or role
end

local function names_for(aliases, roles)
  local out, seen = {}, {}
  for _, role in ipairs(roles) do add_unique(out, seen, name_for(aliases, role)) end
  return out
end

local function progression(aliases, target, has_space_age)
  local rows = {}
  local function set(role, roles)
    rows[name_for(aliases, role)] = names_for(aliases, roles)
  end

  if target.id == "f013" or target.id == "f014" then
    rows["science-pack-1"] = {"science-pack-1"}
    rows["science-pack-2"] = {"science-pack-1", "science-pack-2"}
    rows["science-pack-3"] = {"science-pack-1", "science-pack-2", "science-pack-3"}
    rows["alien-science-pack"] = {
      "science-pack-1", "science-pack-2", "science-pack-3", "alien-science-pack"
    }
    return rows
  end

  set("automation-science-pack", {"automation-science-pack"})
  set("logistic-science-pack", {"automation-science-pack", "logistic-science-pack"})
  set("chemical-science-pack", {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"})
  set("production-science-pack", {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"
  })
  set("military-science-pack", {
    "automation-science-pack", "logistic-science-pack", "military-science-pack"
  })
  set("utility-science-pack", {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack"
  })

  set("space-science-pack", {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack"
  })

  if has_space_age then
    for _, role in ipairs({"agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack"}) do
      set(role, {
        "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
        "production-science-pack", "utility-science-pack", "space-science-pack", role
      })
    end
    set("promethium-science-pack", {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "military-science-pack", "utility-science-pack",
      "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
      "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"
    })
  end
  return rows
end

local function add_same_name_prerequisites(out, names)
  for _, name in ipairs(names) do out[name] = {name} end
end

-- These rows retain the named, published pack-to-technology relationships
-- that the historical prerequisite planner attached to ingredients it added.
-- They are deliberately not a recipe or unlock search. Initial packs have no
-- row; external inputs likewise stay outside this compatibility binding.
local function pack_prerequisites(target, has_space_age)
  local out = {}
  if target.id == "f013" or target.id == "f014" then
    out["alien-science-pack"] = {"alien-technology"}
    return out
  end
  if target.id == "f015" or target.id == "f016" then
    out["production-science-pack"] = {
      "advanced-material-processing-2", "electric-engine", "engine"
    }
    out["military-science-pack"] = {"military-2", "turrets"}
    out["high-tech-science-pack"] = {
      "advanced-electronics-2", "automation-2", "battery", "speed-module"
    }
    out["space-science-pack"] = {"rocket-silo"}
    if target.id == "f016" then
      out["science-pack-3"] = {"advanced-electronics", "engine"}
    end
    return out
  end

  if target.id == "f017" then
    add_same_name_prerequisites(out, {
      "logistic-science-pack", "chemical-science-pack", "military-science-pack",
      "production-science-pack", "utility-science-pack", "space-science-pack"
    })
  elseif target.id == "f100" then
    add_same_name_prerequisites(out, {
      "chemical-science-pack", "military-science-pack", "production-science-pack",
      "utility-science-pack", "space-science-pack"
    })
  else
    add_same_name_prerequisites(out, MODERN_BASE)
  end
  if has_space_age then add_same_name_prerequisites(out, SPACE_AGE) end
  return out
end

-- These are the historical policy's hard science requirements. They are not
-- inferred from recipes or arbitrary technology names.
local FAMILY_CONDITIONS = {
  research_ice = {required_science = {"cryogenic-science-pack"}},
  research_platform = {required_science = {"cryogenic-science-pack"}},
  research_science_pack_productivity = {phase_all_selected = true}
}

function M.conditions_for(family)
  local source = FAMILY_CONDITIONS[family]
  if not source then return {} end
  local out = {}
  for key, value in pairs(source) do
    out[key] = type(value) == "table" and copy_list(value) or value
  end
  return out
end

-- Select only target identities known to the package target record. `mods`
-- determines whether the delivered Space Age role set exists; it never turns
-- an unfamiliar foreign lab input into an official science role.
function M.select(target, mods)
  target = target or {}
  if not KNOWN_TARGETS[target.id] then
    return {aliases = {}, official = {}, official_roles = {}, progression = {}, space = nil, end_game = nil}
  end
  local aliases = native_aliases(target.id)
  local has_space_age = target.id ~= "f013" and target.id ~= "f014"
    and target.id ~= "f015" and target.id ~= "f016" and type(mods) == "table"
    and mods["space-age"] ~= nil
  local official_roles
  if target.id == "f013" or target.id == "f014" then
    official_roles = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "alien-science-pack"}
    local official = {"science-pack-1", "science-pack-2", "science-pack-3", "alien-science-pack"}
    return {
      aliases = aliases, official = official, official_roles = official_roles,
      progression = progression(aliases, target, false),
      pack_prerequisites = pack_prerequisites(target, false),
      space = "alien-science-pack",
      end_game = {pack = "alien-science-pack", prerequisites = {"alien-technology"}}
    }
  end

  official_roles = copy_list(MODERN_BASE)
  if target.id == "f015" or target.id == "f016" then
    official_roles = {
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "military-science-pack", "utility-science-pack",
      "space-science-pack"
    }
  elseif has_space_age then
    for _, role in ipairs(SPACE_AGE) do official_roles[#official_roles + 1] = role end
  end

  local selected = {
    aliases = aliases,
    official = names_for(aliases, official_roles),
    official_roles = official_roles,
    progression = progression(aliases, target, has_space_age),
    pack_prerequisites = pack_prerequisites(target, has_space_age),
    space = name_for(aliases, "space-science-pack"),
    end_game = nil
  }
  if target.id == "f210" and exact_profile(mods, K2SO_PHASE_V8.profile) then
    selected.k2_phase = {
      basic = K2SO_PHASE_V8.basic,
      early = copy_list(K2SO_PHASE_V8.early),
      phase_one = copy_list(K2SO_PHASE_V8.phase_one),
      phase_two = copy_list(K2SO_PHASE_V8.phase_two)
    }
  end
  if has_space_age then
    selected.end_game = {pack = "promethium-science-pack", prerequisites = {"promethium-science-pack"}}
  elseif target.id == "f015" or target.id == "f016" then
    selected.end_game = {pack = selected.space, prerequisites = {"rocket-silo"}}
  else
    -- F017+ exposes the same-name space science trigger technology. Earlier
    -- F015/F016 obtain the white pack from the satellite launch path above.
    selected.end_game = {pack = selected.space, prerequisites = {selected.space}}
  end
  return selected
end

return M
