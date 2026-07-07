local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
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
  ["production-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
  ["military-science-pack"] = {"automation-science-pack", "logistic-science-pack", "military-science-pack"},
  ["utility-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
  ["space-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"},
  ["agricultural-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack"},
  ["metallurgic-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack", "metallurgic-science-pack"},
  ["electromagnetic-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"},
  ["cryogenic-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack", "cryogenic-science-pack"},
  ["promethium-science-pack"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"}
}

local EXTENSION_PACKS = {
  ["braking-force"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"},
  ["research-speed"] = "all",
  ["worker-robots-storage"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "electromagnetic-science-pack"},
  ["inserter-capacity-bonus"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "agricultural-science-pack"},
  ["weapon-shooting-speed"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  ["laser-shooting-speed"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  research_electric_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "electromagnetic-science-pack"},
  research_flamethrower_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  research_rocket_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "electromagnetic-science-pack"},
  research_cannon_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "electromagnetic-science-pack"}
}

local lab_inputs_cache = nil
local science_pack_unlock_cache = nil
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
  local source = deepcopy(ingredients or {})
  if #source == 0 then return nil, "empty" end
  if S.valid_research_ingredients(source) then return source, "full" end
  if lab_incompatibility_policy() == "skip" then
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology") .. " because no lab accepts the full selected science-pack set and the lab incompatibility policy is skip.")
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
    log("[more-infinite-research] Reduced science packs for " .. tostring(context or "unknown technology") .. " to a lab-compatible subset accepted by " .. best_lab .. ".")
    return best, "reduced"
  end

  log("[more-infinite-research] No lab can research the selected science packs for " .. tostring(context or "unknown technology") .. ".")
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

local function build_science_pack_unlock_cache()
  if science_pack_unlock_cache then return science_pack_unlock_cache end
  science_pack_unlock_cache = {}
  local lab_inputs = S.all_lab_inputs()
  local technology_names = {}
  for tech_name, _ in pairs(data_raw.prototypes("technology")) do
    table.insert(technology_names, tech_name)
  end
  table.sort(technology_names)
  for _, tech_name in ipairs(technology_names) do
    local tech = data_raw.technology(tech_name)
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        local recipe = data_raw.prototype("recipe", effect.recipe)
        if recipe then
          for _, pack_name in ipairs(lab_inputs) do
            if recipe_outputs_item(recipe, pack_name) and not science_pack_unlock_cache[pack_name] then
              science_pack_unlock_cache[pack_name] = tech_name
            end
          end
        end
      end
    end
  end
  return science_pack_unlock_cache
end

function S.prereq_tech_for_science_pack(pack_name)
  if lookup.technology_exists(pack_name) then return pack_name end
  local cache = build_science_pack_unlock_cache()
  local tech_name = cache[pack_name]
  if tech_name and lookup.technology_exists(tech_name) then return tech_name end
  return nil
end

return S
