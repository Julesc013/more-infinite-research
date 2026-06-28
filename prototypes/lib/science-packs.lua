local deepcopy = require("prototypes.lib.deepcopy")
local lookup = require("prototypes.lib.prototype-lookup")

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

local EXTENSION_PACKS = {
  ["braking-force"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"},
  ["research-speed"] = "all",
  ["worker-robots-storage"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "electromagnetic-science-pack"},
  ["inserter-capacity-bonus"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "agricultural-science-pack"},
  ["weapon-shooting-speed"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  ["laser-shooting-speed"] = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  research_electric_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "electromagnetic-science-pack"},
  research_flamethrower_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "space-science-pack"},
  research_rocket_shooting_speed = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack", "agricultural-science-pack"}
}

local lab_inputs_cache = nil
local science_pack_unlock_cache = nil

local function ingredient_name(ingredient)
  if not ingredient then return nil end
  if type(ingredient) == "string" then return ingredient end
  return ingredient.name or ingredient[1]
end

local function ingredient_amount(ingredient)
  if not ingredient or type(ingredient) == "string" then return 1 end
  return ingredient.amount or ingredient[2] or 1
end

function S.all_lab_inputs()
  if lab_inputs_cache then return deepcopy(lab_inputs_cache) end
  -- Factorio 2.1 science packs are ordinary items, so labs are the source of
  -- truth for what can participate in research.
  local out, seen = {}, {}
  for _, lab in pairs(data.raw.lab or {}) do
    for _, input in ipairs(lab.inputs or {}) do
      if not seen[input] and lookup.item_prototype(input) then
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
  if not lookup.item_prototype(name) then return false end
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
  for _, lab in pairs(data.raw.lab or {}) do
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

  -- Some mods add separate labs with disjoint inputs. Prefer a deterministic
  -- subset over creating a technology no available lab can research.
  local labs = {}
  for name, lab in pairs(data.raw.lab or {}) do
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

function S.pack_list_for_extension(key, desired)
  if desired == "all" then return S.pack_list_all() end
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
  for tech_name, tech in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(tech.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        local recipe = (data.raw.recipe or {})[effect.recipe]
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
