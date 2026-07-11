local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local effective_settings = require("prototypes.mir.settings.effective")

local S = {}

local VANILLA_PACK_ORDER = {
  "automation-science-pack",
  "logistic-science-pack",
  "chemical-science-pack",
  "production-science-pack",
  "military-science-pack",
  "utility-science-pack",
  "space-science-pack",
  "agricultural-science-pack",
  "metallurgic-science-pack",
  "electromagnetic-science-pack",
  "cryogenic-science-pack",
  "promethium-science-pack"
}

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
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack"
  },
  ["military-science-pack"] = {"automation-science-pack", "logistic-science-pack", "military-science-pack"},
  ["utility-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack"
  },
  ["space-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack"
  },
  ["agricultural-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack",
    "agricultural-science-pack"
  },
  ["metallurgic-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack",
    "metallurgic-science-pack"
  },
  ["electromagnetic-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack",
    "electromagnetic-science-pack"
  },
  ["cryogenic-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack",
    "cryogenic-science-pack"
  },
  ["promethium-science-pack"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "utility-science-pack",
    "space-science-pack",
    "agricultural-science-pack",
    "metallurgic-science-pack",
    "electromagnetic-science-pack",
    "cryogenic-science-pack",
    "promethium-science-pack"
  }
}

local EXTENSION_PACKS = {
  ["braking-force"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "space-science-pack"
  },
  ["research-speed"] = "all",
  ["worker-robots-storage"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "electromagnetic-science-pack"
  },
  ["inserter-capacity-bonus"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "agricultural-science-pack"
  },
  ["weapon-shooting-speed"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "space-science-pack"
  },
  ["laser-shooting-speed"] = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "space-science-pack"
  },
  research_electric_shooting_speed = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "electromagnetic-science-pack"
  },
  research_flamethrower_shooting_speed = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "space-science-pack"
  },
  research_rocket_shooting_speed = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "electromagnetic-science-pack"
  },
  research_cannon_shooting_speed = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "military-science-pack",
    "electromagnetic-science-pack"
  }
}

local lab_inputs_cache = nil
local science_pack_resolution_cache = {}
local science_pack_recipe_status_cache = nil
local technology_reachability_cache = {}
local mod_progression_cache = {}

local function ingredient_name(ingredient)
  if not ingredient then return nil end
  if type(ingredient) == "string" then return ingredient end
  return ingredient.name or ingredient[1]
end

local function ingredient_amount(ingredient)
  if not ingredient or type(ingredient) == "string" then return 1 end
  return ingredient.amount or ingredient[2] or 1
end

local function startup_setting(name)
  return effective_settings.get(name)
end

local function lab_incompatibility_policy()
  local value = startup_setting("mir-lab-incompatibility-policy")
  if value == "engine-default" then return "engine-default" end
  if value == "skip" then return "skip" end
  return "reduce"
end

local function science_packs_require_tool_prototypes()
  local automation_pack = lookup.item_prototype("automation-science-pack")
  return automation_pack and automation_pack.type == "tool"
end

local function research_pack_prototype(name)
  local prototype = lookup.item_prototype(name)
  if not prototype then return nil end
  if science_packs_require_tool_prototypes() and prototype.type ~= "tool" then return nil end
  return prototype
end

function S.all_lab_inputs()
  if lab_inputs_cache then return deepcopy(lab_inputs_cache) end
  -- Labs are the source of truth, but older target lines still require science
  -- packs to be tool prototypes in technology research units.
  local out, seen = {}, {}
  for _, lab in pairs(data_raw.prototypes("lab")) do
    for _, input in ipairs(lab.inputs or {}) do
      if not seen[input] and research_pack_prototype(input) then
        seen[input] = true
        table.insert(out, input)
      end
    end
  end
  table.sort(out)
  lab_inputs_cache = out
  return deepcopy(out)
end

function S.science_pack_exists(name)
  if not research_pack_prototype(name) then return false end
  for _, input in ipairs(S.all_lab_inputs()) do
    if input == name then return true end
  end
  return false
end

local function lab_accepts_all(lab, packs)
  local accepted = {}
  for _, input in ipairs((lab and lab.inputs) or {}) do
    accepted[input] = true
  end
  for _, pack in ipairs(packs or {}) do
    if not accepted[pack] then return false end
  end
  return true
end

function S.any_lab_accepts_all(packs)
  if not packs or #packs == 0 then return false end
  for _, lab in pairs(data_raw.prototypes("lab")) do
    if lab_accepts_all(lab, packs) then return true end
  end
  return false
end

function S.valid_research_ingredients(ingredients)
  local packs = {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = ingredient_name(ingredient)
    if name then table.insert(packs, name) end
  end
  return S.any_lab_accepts_all(packs)
end

function S.best_lab_compatible_ingredients(ingredients, context)
  if lab_incompatibility_policy() == "engine-default" then
    -- Explicit neutral/bypass option. Never rewrite the selected ingredients.
    -- Preserve a Factorio-safe set unchanged, or omit the generated technology
    -- rather than emitting a prototype the final graph guard must reject.
    local unchanged = deepcopy(ingredients or {})
    local reachable = #unchanged > 0
    for _, ingredient in ipairs(unchanged) do
      local pack_name = ingredient_name(ingredient)
      if not pack_name or S.pack_production_status(pack_name) == "unreachable" then
        reachable = false
        break
      end
    end
    if reachable and S.valid_research_ingredients(unchanged) then
      return unchanged, "unchanged"
    end
    log(
      "[more-infinite-research] Skipping " ..
        tostring(context or "unknown technology") ..
        " because engine-default lab policy forbids ingredient rewriting and the selected set is not safely researchable."
    )
    return nil, "invalid"
  end

  local source = {}
  for _, ingredient in ipairs(deepcopy(ingredients or {})) do
    local pack_name = ingredient_name(ingredient)
    local production_status = pack_name and S.pack_production_status(pack_name) or "unreachable"
    if production_status ~= "unreachable" then
      table.insert(source, ingredient)
    else
      log(
        "[more-infinite-research] Excluding science pack " ..
          tostring(pack_name) ..
          " from " ..
          tostring(context or "unknown technology") ..
          " because it has no initially available recipe or enabled reachable unlock technology."
      )
    end
  end
  if #source == 0 then return nil, "empty" end
  if S.valid_research_ingredients(source) then return source, "full" end
  if lab_incompatibility_policy() == "skip" then
    log(
      "[more-infinite-research] Skipping " ..
        tostring(context or "unknown technology") ..
        " because no lab accepts the full selected science-pack set and the lab incompatibility policy is skip."
    )
    return nil, "invalid"
  end

  -- Some mods add separate labs with disjoint inputs. Prefer a deterministic
  -- subset over creating a technology no available lab can research.
  local labs = {}
  for name, lab in pairs(data_raw.prototypes("lab")) do
    table.insert(labs, {name = name, lab = lab})
  end
  table.sort(labs, function(a, b) return a.name < b.name end)

  local best = nil
  local best_lab = nil
  for _, entry in ipairs(labs) do
    local candidate = {}
    local accepted = {}
    for _, input in ipairs(entry.lab.inputs or {}) do accepted[input] = true end
    for _, ingredient in ipairs(source) do
      local name = ingredient_name(ingredient)
      if name and accepted[name] then
        table.insert(candidate, {name, ingredient_amount(ingredient)})
      end
    end
    if #candidate > 0 and S.valid_research_ingredients(candidate) then
      if not best or #candidate > #best then
        best = candidate
        best_lab = entry.name
      end
    end
  end

  if best then
    log(
      "[more-infinite-research] Reduced science packs for " ..
        tostring(context or "unknown technology") ..
        " to a lab-compatible subset accepted by " ..
        best_lab ..
        "."
    )
    return best, "reduced"
  end

  log(
    "[more-infinite-research] No lab can research the selected science packs for " ..
      tostring(context or "unknown technology") ..
      "."
  )
  return nil, "invalid"
end

function S.pack_list_all()
  local available = {}
  for _, pack in ipairs(S.all_lab_inputs()) do
    available[pack] = true
  end

  local out = {}
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if available[pack] then
      table.insert(out, pack)
      available[pack] = nil
    end
  end

  local extra = {}
  for pack, _ in pairs(available) do table.insert(extra, pack) end
  table.sort(extra)
  for _, pack in ipairs(extra) do table.insert(out, pack) end
  return out
end

function S.pack_list_official()
  local available = {}
  for _, pack in ipairs(S.all_lab_inputs()) do
    available[pack] = true
  end

  local out = {}
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if available[pack] then table.insert(out, pack) end
  end
  return out
end

function S.is_official_science_pack(name)
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if pack == name then return true end
  end
  return false
end

local function ordered_pack_list_from_set(set)
  local remaining = {}
  for pack, enabled in pairs(set or {}) do
    if enabled then remaining[pack] = true end
  end

  local out = {}
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if remaining[pack] then
      table.insert(out, pack)
      remaining[pack] = nil
    end
  end

  local extra = {}
  for pack, _ in pairs(remaining) do table.insert(extra, pack) end
  table.sort(extra)
  for _, pack in ipairs(extra) do table.insert(out, pack) end
  return out
end

local function selected_pack_cache_key(selected_packs)
  local names = {}
  for _, pack in ipairs(selected_packs or {}) do
    if pack then table.insert(names, pack) end
  end
  table.sort(names)
  return table.concat(names, "\n")
end

function S.space_age_progression_packs_for(selected_packs)
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

function S.official_progression_packs_for(selected_packs)
  local out, seen = {}, {}
  local function add(pack)
    if not seen[pack] then
      seen[pack] = true
      table.insert(out, pack)
    end
  end

  for _, pack in ipairs(selected_packs or {}) do
    local step = OFFICIAL_PROGRESSION_STEPS[pack]
    if step then
      for _, implied in ipairs(step) do add(implied) end
    end
  end

  return out
end

function S.mod_progression_packs_for(selected_packs)
  local key = selected_pack_cache_key(selected_packs)
  if mod_progression_cache[key] then return deepcopy(mod_progression_cache[key]) end

  local inferred = {}
  local visited_techs = {}

  local function collect_tech_science(tech)
    for _, ingredient in ipairs(((tech and tech.unit) and tech.unit.ingredients) or {}) do
      local name = ingredient_name(ingredient)
      if name and S.science_pack_exists(name) then inferred[name] = true end
    end
  end

  local function walk_tech(tech_name)
    if not tech_name or visited_techs[tech_name] then return end
    visited_techs[tech_name] = true

    local tech = data_raw.technology(tech_name)
    if not tech then return end

    local prereqs = {}
    for _, prereq in ipairs(tech.prerequisites or {}) do table.insert(prereqs, prereq) end
    table.sort(prereqs)
    for _, prereq in ipairs(prereqs) do walk_tech(prereq) end
    collect_tech_science(tech)
  end

  for _, pack in ipairs(selected_packs or {}) do
    walk_tech(S.prereq_tech_for_science_pack(pack))
  end

  for _, pack in ipairs(S.official_progression_packs_for(selected_packs)) do
    inferred[pack] = true
  end

  mod_progression_cache[key] = ordered_pack_list_from_set(inferred)
  return deepcopy(mod_progression_cache[key])
end

function S.end_game_science_pack()
  if lookup.is_space_age() and S.science_pack_exists("promethium-science-pack") then
    return "promethium-science-pack"
  end
  if S.science_pack_exists("space-science-pack") then
    return "space-science-pack"
  end
  return nil
end

function S.pack_list_for_extension(key, desired)
  if desired == "all" then return S.pack_list_all() end
  if desired == "all-official" then return S.pack_list_official() end
  if type(desired) == "table" then return deepcopy(desired) end

  local list = EXTENSION_PACKS[key]
  if not list then return nil end
  if list == "all" then return S.pack_list_all() end
  return deepcopy(list)
end

local function recipe_outputs_item(recipe, item_name)
  local function matches(result)
    if not result then return false end
    local name = type(result) == "string" and result or result.name or result[1]
    return name == item_name
  end
  local function scan(def)
    if not def then return false end
    if def.results then
      for _, result in pairs(def.results) do
        if matches(result) then return true end
      end
    elseif def.result then
      return matches(def.result)
    end
    return false
  end
  if recipe.normal or recipe.expensive then
    return scan(recipe.normal) or scan(recipe.expensive)
  end
  return scan(recipe)
end

local function recipe_enabled_without_research(recipe)
  if not recipe or recipe.hidden == true or recipe.enabled == false then return false end

  local variants = {}
  if recipe.normal then table.insert(variants, recipe.normal) end
  if recipe.expensive then table.insert(variants, recipe.expensive) end
  for _, variant in ipairs(variants) do
    if variant.enabled == false then return false end
  end

  return true
end

local function technology_is_enabled_and_reachable(tech_name, visiting)
  if technology_reachability_cache[tech_name] ~= nil then
    return technology_reachability_cache[tech_name]
  end

  local tech = data_raw.technology(tech_name)
  if not tech or tech.enabled == false then
    technology_reachability_cache[tech_name] = false
    return false
  end

  visiting = visiting or {}
  if visiting[tech_name] then
    technology_reachability_cache[tech_name] = false
    return false
  end

  visiting[tech_name] = true
  local prerequisites = {}
  for _, prerequisite in ipairs(tech.prerequisites or {}) do
    table.insert(prerequisites, prerequisite)
  end
  table.sort(prerequisites)

  for _, prerequisite in ipairs(prerequisites) do
    if not technology_is_enabled_and_reachable(prerequisite, visiting) then
      visiting[tech_name] = nil
      technology_reachability_cache[tech_name] = false
      return false
    end
  end

  visiting[tech_name] = nil
  technology_reachability_cache[tech_name] = true
  return true
end

local resolve_pack_production
local technology_researchability_reason

local function build_science_pack_recipe_status_cache()
  if science_pack_recipe_status_cache then return science_pack_recipe_status_cache end

  science_pack_recipe_status_cache = {}
  local lab_inputs = S.all_lab_inputs()
  for _, pack_name in ipairs(lab_inputs) do
    science_pack_recipe_status_cache[pack_name] = {
      has_recipe = false,
      initially_available = false,
      recipes = {}
    }
  end

  for recipe_name, recipe in pairs(data_raw.prototypes("recipe")) do
    for _, pack_name in ipairs(lab_inputs) do
      if recipe_outputs_item(recipe, pack_name) then
        local status = science_pack_recipe_status_cache[pack_name]
        status.has_recipe = true
        table.insert(status.recipes, recipe_name)
        if recipe_enabled_without_research(recipe) then
          status.initially_available = true
        end
      end
    end
  end

  for _, status in pairs(science_pack_recipe_status_cache) do
    table.sort(status.recipes)
  end

  return science_pack_recipe_status_cache
end

technology_researchability_reason = function(tech_name, context)
  context = context or {}
  local technology = data_raw.technology(tech_name)
  if not technology then return "missing" end
  if technology.enabled == false then return "disabled" end
  if not technology_is_enabled_and_reachable(tech_name) then return "unreachable-prerequisite" end

  local visiting_technologies = context.visiting_technologies or {}
  if visiting_technologies[tech_name] then return "technology-cycle" end
  visiting_technologies[tech_name] = true

  local function finish(reason)
    visiting_technologies[tech_name] = nil
    return reason
  end

  local prerequisites = {}
  for _, prerequisite in ipairs(technology.prerequisites or {}) do
    table.insert(prerequisites, prerequisite)
  end
  table.sort(prerequisites)
  for _, prerequisite in ipairs(prerequisites) do
    local reason = technology_researchability_reason(prerequisite, {
      visiting_packs = context.visiting_packs,
      visiting_technologies = visiting_technologies,
      unlock_recipe_name = context.unlock_recipe_name
    })
    if reason then return finish("prerequisite-" .. prerequisite .. "-" .. reason) end
  end

  if technology.research_trigger then return finish(nil) end

  local unit = technology.unit
  local ingredients = unit and unit.ingredients or nil
  if not unit or not ingredients or #ingredients == 0 then
    return finish("missing-research-mechanism")
  end
  if unit.count == nil and unit.count_formula == nil then
    return finish("missing-research-count")
  end
  if not S.valid_research_ingredients(ingredients) then
    return finish("no-accepting-lab")
  end

  local unlock_recipe = context.unlock_recipe_name
    and data_raw.prototype("recipe", context.unlock_recipe_name)
    or nil
  for _, ingredient in ipairs(ingredients) do
    local pack_name = ingredient_name(ingredient)
    if pack_name then
      if not S.science_pack_exists(pack_name) then
        return finish("unrecognized-science-" .. pack_name)
      end
      if unlock_recipe and recipe_outputs_item(unlock_recipe, pack_name) then
        return finish("science-self-lock-" .. pack_name)
      end
      local status = resolve_pack_production(pack_name, context.visiting_packs or {})
      if status == "unreachable" then
        return finish("unreachable-science-" .. pack_name)
      end
    end
  end

  return finish(nil)
end

resolve_pack_production = function(pack_name, visiting_packs)
  local cached = science_pack_resolution_cache[pack_name]
  if cached then return cached.status, cached.prerequisite end
  if not pack_name or not S.science_pack_exists(pack_name) then return "unreachable", nil end

  visiting_packs = visiting_packs or {}
  if visiting_packs[pack_name] then return "unreachable", nil end

  local recipe_status = build_science_pack_recipe_status_cache()[pack_name]
  if recipe_status and recipe_status.initially_available then
    science_pack_resolution_cache[pack_name] = {status = "initial"}
    return "initial", nil
  end

  if recipe_status and recipe_status.has_recipe then
    visiting_packs[pack_name] = true
    local candidates = {}
    for _, recipe_name in ipairs(recipe_status.recipes or {}) do
      for _, technology_name in ipairs(recipe_unlocks.for_recipe(recipe_name)) do
        candidates[technology_name] = candidates[technology_name] or recipe_name
      end
    end

    local technology_names = {}
    for technology_name, _ in pairs(candidates) do table.insert(technology_names, technology_name) end
    table.sort(technology_names)
    for _, technology_name in ipairs(technology_names) do
      local reason = technology_researchability_reason(technology_name, {
        visiting_packs = visiting_packs,
        visiting_technologies = {},
        unlock_recipe_name = candidates[technology_name]
      })
      if not reason then
        visiting_packs[pack_name] = nil
        science_pack_resolution_cache[pack_name] = {
          status = "research",
          prerequisite = technology_name
        }
        return "research", technology_name
      end
    end

    visiting_packs[pack_name] = nil
    science_pack_resolution_cache[pack_name] = {status = "unreachable"}
    return "unreachable", nil
  end

  if technology_researchability_reason(pack_name, {
    visiting_packs = visiting_packs,
    visiting_technologies = {}
  }) == nil then
    science_pack_resolution_cache[pack_name] = {
      status = "non-recipe",
      prerequisite = pack_name
    }
    return "non-recipe", pack_name
  end

  -- Launch products, scripts, and other non-recipe systems cannot be inferred
  -- from prototypes. Presence in an active lab remains the available evidence.
  science_pack_resolution_cache[pack_name] = {status = "non-recipe"}
  return "non-recipe", nil
end

function S.pack_production_status(pack_name)
  return resolve_pack_production(pack_name, {})
end

function S.researchable_unlockers_for_recipe(recipe_name)
  local recipe = data_raw.prototype("recipe", recipe_name)
  if not recipe or recipe_enabled_without_research(recipe) then return {} end

  local out = {}
  for _, technology_name in ipairs(recipe_unlocks.for_recipe(recipe_name)) do
    local reason = technology_researchability_reason(technology_name, {
      visiting_packs = {},
      visiting_technologies = {},
      unlock_recipe_name = recipe_name
    })
    if not reason then table.insert(out, technology_name) end
  end
  return out
end

function S.technology_researchability_reason(tech_name)
  return technology_researchability_reason(tech_name, {
    visiting_packs = {},
    visiting_technologies = {}
  })
end

function S.technology_is_researchable(tech_name)
  return S.technology_researchability_reason(tech_name) == nil
end

function S.technology_is_enabled_and_reachable(tech_name)
  return technology_is_enabled_and_reachable(tech_name)
end

function S.prereq_tech_for_science_pack(pack_name)
  local _, prerequisite = S.pack_production_status(pack_name)
  return prerequisite
end

return S
