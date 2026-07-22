local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local prereq_tech_for_science_pack = nil

local function mod_progression_cache()
  return compiler_context.current():state_view("mod_progression_cache", function() return {} end)
end

local SPACE_AGE_PLANET_PACKS = {
  "agricultural-science-pack",
  "metallurgic-science-pack",
  "electromagnetic-science-pack",
  "cryogenic-science-pack"
}

local OFFICIAL_PROGRESSION_STEPS = {
  ["automation-science-pack"] = {"automation-science-pack"},
  ["logistic-science-pack"] = {"automation-science-pack", "logistic-science-pack"},
  ["chemical-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
  ["production-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"
  },
  ["military-science-pack"] = {"automation-science-pack", "logistic-science-pack", "military-science-pack"},
  ["utility-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack"
  },
  ["space-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack"
  },
  ["agricultural-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack"
  },
  ["metallurgic-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack", "metallurgic-science-pack"
  },
  ["electromagnetic-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"
  },
  ["cryogenic-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack", "cryogenic-science-pack"
  },
  ["promethium-science-pack"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "military-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack",
    "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack",
    "promethium-science-pack"
  }
}

local EXTENSION_PACKS = {
  ["braking-force"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "space-science-pack"
  },
  ["research-speed"] = "all",
  ["worker-robots-storage"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "electromagnetic-science-pack"
  },
  ["inserter-capacity-bonus"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack"
  },
  ["weapon-shooting-speed"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "space-science-pack"
  },
  ["laser-shooting-speed"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "space-science-pack"
  },
  research_electric_shooting_speed = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "electromagnetic-science-pack"
  },
  research_flamethrower_shooting_speed = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "space-science-pack"
  },
  research_rocket_shooting_speed = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "electromagnetic-science-pack"
  },
  research_cannon_shooting_speed = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "electromagnetic-science-pack"
  }
}

function M.configure(dependencies)
  prereq_tech_for_science_pack = assert(
    dependencies.prereq_tech_for_science_pack,
    "science selection policy requires pack prerequisite lookup"
  )
end

local function selected_pack_cache_key(selected_packs)
  local names = {}
  for _, pack in ipairs(selected_packs or {}) do
    if pack then table.insert(names, pack) end
  end
  table.sort(names)
  return table.concat(names, "\n")
end

function M.space_age_progression_packs_for(selected_packs)
  local selected = {}
  for _, pack in ipairs(selected_packs or {}) do selected[pack] = true end
  local has_space_age_pack = selected["promethium-science-pack"] or false
  for _, pack in ipairs(SPACE_AGE_PLANET_PACKS) do
    if selected[pack] then has_space_age_pack = true end
  end
  local out = {}
  if has_space_age_pack then table.insert(out, "space-science-pack") end
  if selected["promethium-science-pack"] then
    for _, pack in ipairs(SPACE_AGE_PLANET_PACKS) do table.insert(out, pack) end
    table.insert(out, "promethium-science-pack")
  end
  return out
end

function M.official_progression_packs_for(selected_packs)
  local out, seen = {}, {}
  local function add(pack)
    if not seen[pack] then seen[pack] = true; table.insert(out, pack) end
  end
  for _, pack in ipairs(selected_packs or {}) do
    for _, implied in ipairs(OFFICIAL_PROGRESSION_STEPS[pack] or {}) do add(implied) end
  end
  return out
end

function M.mod_progression_packs_for(selected_packs)
  if not prereq_tech_for_science_pack then error("MIR science selection dependencies were not configured.", 2) end
  local key = selected_pack_cache_key(selected_packs)
  local cache = mod_progression_cache()
  if cache[key] then return deepcopy(cache[key]) end
  local inferred, visited_techs = {}, {}

  local function collect_tech_science(tech)
    for _, ingredient in ipairs(((tech and tech.unit) and tech.unit.ingredients) or {}) do
      local name = lab_compatibility.ingredient_name(ingredient)
      if name and pack_registry.science_pack_exists(name) then inferred[name] = true end
    end
  end
  local function walk_tech(tech_name)
    if not tech_name or visited_techs[tech_name] then return end
    visited_techs[tech_name] = true
    local tech = data_raw.technology(tech_name)
    if not tech then return end
    local prerequisites = {}
    for _, prerequisite in ipairs(tech.prerequisites or {}) do table.insert(prerequisites, prerequisite) end
    table.sort(prerequisites)
    for _, prerequisite in ipairs(prerequisites) do walk_tech(prerequisite) end
    collect_tech_science(tech)
  end
  for _, pack in ipairs(selected_packs or {}) do walk_tech(prereq_tech_for_science_pack(pack)) end
  for _, pack in ipairs(M.official_progression_packs_for(selected_packs)) do inferred[pack] = true end
  cache[key] = pack_registry.ordered_pack_list_from_set(inferred)
  return deepcopy(cache[key])
end

function M.end_game_science_pack()
  if lookup.is_space_age() and pack_registry.science_pack_exists("promethium-science-pack") then
    return "promethium-science-pack"
  end
  if pack_registry.science_pack_exists("space-science-pack") then return "space-science-pack" end
  return nil
end

function M.pack_list_for_extension(key, desired)
  if desired == "all" then return pack_registry.pack_list_all() end
  if desired == "all-official" then return pack_registry.pack_list_official() end
  if type(desired) == "table" then return deepcopy(desired) end
  local list = EXTENSION_PACKS[key]
  if not list then return nil end
  if list == "all" then return pack_registry.pack_list_all() end
  return deepcopy(list)
end

return M
