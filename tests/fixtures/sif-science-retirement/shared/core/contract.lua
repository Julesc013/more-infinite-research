-- Independently declared SIF-01 continuation expectations. Published source
-- facts and the corrected MIR5 candidate contract are kept in distinct staged
-- records. This fixture never imports MIR implementation.
local function rows(source)
  local out = {}
  for index, row in ipairs(source) do out[index] = {row[1], row[2]} end
  return out
end

local function names(source)
  local out = {}
  for index, name in ipairs(source) do out[index] = name end
  return out
end

local function append(left, right)
  local out = rows(left)
  for _, row in ipairs(right or {}) do out[#out + 1] = {row[1], row[2]} end
  return out
end

local function append_names(left, right)
  local out = names(left)
  for _, name in ipairs(right or {}) do out[#out + 1] = name end
  return out
end

local RESEARCH_SCIENCE = {
  {"automation-science-pack",1},{"logistic-science-pack",1},{"chemical-science-pack",1},
  {"production-science-pack",1},{"utility-science-pack",1},{"military-science-pack",1},
  {"agricultural-science-pack",1},{"metallurgic-science-pack",1},{"electromagnetic-science-pack",1},
  {"cryogenic-science-pack",1},{"promethium-science-pack",1}
}

local WEAPON_SCIENCE = {
  {"automation-science-pack",1},{"logistic-science-pack",1},{"chemical-science-pack",1},
  {"military-science-pack",1},{"utility-science-pack",1}
}

local PRODUCTION = {{"production-science-pack",1}}
local PLANETS = {
  {"agricultural-science-pack",1},{"metallurgic-science-pack",1},{"electromagnetic-science-pack",1},
  {"cryogenic-science-pack",1},{"promethium-science-pack",1}
}
local PROMETHIUM = {{"promethium-science-pack",1}}

local RESEARCH_PREREQUISITES = {
  "research-speed-5","utility-science-pack","research-speed-6","automation-science-pack",
  "logistic-science-pack","chemical-science-pack","production-science-pack","military-science-pack",
  "agricultural-science-pack","metallurgic-science-pack","electromagnetic-science-pack",
  "cryogenic-science-pack","promethium-science-pack"
}

local WEAPON_PREREQUISITES = {
  "weapon-shooting-speed-5","utility-science-pack","weapon-shooting-speed-6",
  "automation-science-pack","logistic-science-pack","chemical-science-pack","military-science-pack"
}
local PRODUCTION_NAME, PLANET_NAMES, PROMETHIUM_NAME = {"production-science-pack"}, {
  "agricultural-science-pack","metallurgic-science-pack","electromagnetic-science-pack",
  "cryogenic-science-pack","promethium-science-pack"
}, {"promethium-science-pack"}

local function uniform(science, prerequisites)
  return {
    science = {
      configured=rows(science), space=rows(science), ["space-and-promethium"]=rows(science),
      ["space-age-progression"]=rows(science), ["official-progression"]=rows(science),
      ["mod-progression"]=rows(science), ["all-official"]=rows(science), all=rows(science)
    },
    prerequisites = {
      configured=names(prerequisites), space=names(prerequisites), ["space-and-promethium"]=names(prerequisites),
      ["space-age-progression"]=names(prerequisites), ["official-progression"]=names(prerequisites),
      ["mod-progression"]=names(prerequisites), ["all-official"]=names(prerequisites), all=names(prerequisites)
    }
  }
end

local research = uniform(RESEARCH_SCIENCE, RESEARCH_PREREQUISITES)
local weapon = {
  science = {
    configured=rows(WEAPON_SCIENCE), space=rows(WEAPON_SCIENCE),
    ["space-and-promethium"]=append(WEAPON_SCIENCE, PROMETHIUM),
    ["space-age-progression"]=rows(WEAPON_SCIENCE),
    ["official-progression"]=append(WEAPON_SCIENCE, PRODUCTION),
    ["mod-progression"]=rows(WEAPON_SCIENCE),
    ["all-official"]=append(append(WEAPON_SCIENCE, PRODUCTION), PLANETS),
    all=append(append(WEAPON_SCIENCE, PRODUCTION), PLANETS)
  },
  prerequisites = {
    configured=names(WEAPON_PREREQUISITES), space=names(WEAPON_PREREQUISITES),
    ["space-and-promethium"]=append_names(WEAPON_PREREQUISITES, PROMETHIUM_NAME),
    ["space-age-progression"]=names(WEAPON_PREREQUISITES),
    ["official-progression"]=append_names(WEAPON_PREREQUISITES, PRODUCTION_NAME),
    ["mod-progression"]=names(WEAPON_PREREQUISITES),
    ["all-official"]=append_names(append_names(WEAPON_PREREQUISITES, PRODUCTION_NAME), PLANET_NAMES),
    all=append_names(append_names(WEAPON_PREREQUISITES, PRODUCTION_NAME), PLANET_NAMES)
  }
}

return {
  policies = {
    "configured", "space", "space-and-promethium", "space-age-progression",
    "official-progression", "mod-progression", "all-official", "all"
  },
  rows = {
    ["research-speed-7"] = {
      formula = "683.4375*1.5^(L-7)", time = 120,
      effects = {{type="laboratory-speed", modifier=0.6}},
      -- This finite predecessor remains a published-4.7.2 source fact. Its
      -- values happen to equal the repaired successor's SIF result; neither
      -- stage is derived from the other in this fixture.
      published = {science=rows(RESEARCH_SCIENCE), prerequisites=names(RESEARCH_PREREQUISITES)},
      science = research.science, prerequisites = research.prerequisites
    },
    ["weapon-shooting-speed-7"] = {
      formula = "683.4375*1.5^(L-7)", time = 120,
      effects = {{type="gun-speed", ammo_category="bullet", modifier=0.4},{type="gun-speed", ammo_category="shotgun-shell", modifier=0.4}},
      published = {science=rows(WEAPON_SCIENCE), prerequisites=names(WEAPON_PREREQUISITES)},
      science = weapon.science, prerequisites = weapon.prerequisites
    }
  }
}
