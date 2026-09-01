local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")

local M = {}
local pack_production_status = nil

function M.configure(dependencies)
  pack_production_status = assert(dependencies.pack_production_status, "lab compatibility requires pack production status")
end

function M.ingredient_name(ingredient)
  if not ingredient then return nil end
  if type(ingredient) == "string" then return ingredient end
  return ingredient.name or ingredient[1]
end

function M.ingredient_amount(ingredient)
  if not ingredient or type(ingredient) == "string" then return 1 end
  return ingredient.amount or ingredient[2] or 1
end

local function policy()
  local value = effective_settings.get("mir-lab-incompatibility-policy")
  if value == "engine-default" then return "engine-default" end
  if value == "skip" then return "skip" end
  return "reduce"
end

local function lab_accepts_all(lab, packs)
  local accepted = {}
  for _, input in ipairs((lab and lab.inputs) or {}) do accepted[input] = true end
  for _, pack in ipairs(packs or {}) do
    if not accepted[pack] then return false end
  end
  return true
end

function M.any_lab_accepts_all(packs)
  if not packs or #packs == 0 then return false end
  for _, lab in pairs(data_raw.prototypes("lab")) do
    if lab_accepts_all(lab, packs) then return true end
  end
  return false
end

function M.valid_research_ingredients(ingredients)
  local packs = {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = M.ingredient_name(ingredient)
    if name then table.insert(packs, name) end
  end
  return M.any_lab_accepts_all(packs)
end

function M.best_lab_compatible_ingredients(ingredients, context)
  if not pack_production_status then error("MIR lab compatibility dependencies were not configured.", 2) end
  if policy() == "engine-default" then
    local unchanged = deepcopy(ingredients or {})
    local reachable = #unchanged > 0
    for _, ingredient in ipairs(unchanged) do
      local pack_name = M.ingredient_name(ingredient)
      if not pack_name or pack_production_status(pack_name) == "unreachable" then
        reachable = false
        break
      end
    end
    if reachable and M.valid_research_ingredients(unchanged) then return unchanged, "unchanged" end
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology")
      .. " because engine-default lab policy forbids ingredient rewriting and the selected set is not safely researchable.")
    return nil, "invalid"
  end

  local source = {}
  for _, ingredient in ipairs(deepcopy(ingredients or {})) do
    local pack_name = M.ingredient_name(ingredient)
    if pack_name and pack_production_status(pack_name) ~= "unreachable" then
      table.insert(source, ingredient)
    else
      log("[more-infinite-research] Excluding science pack " .. tostring(pack_name)
        .. " from " .. tostring(context or "unknown technology")
        .. " because it has no initially available recipe or enabled reachable unlock technology.")
    end
  end
  if #source == 0 then return nil, "empty" end
  if M.valid_research_ingredients(source) then return source, "full" end
  if policy() == "skip" then
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology")
      .. " because no lab accepts the full selected science-pack set and the lab incompatibility policy is skip.")
    return nil, "invalid"
  end

  local labs = {}
  for name, lab in pairs(data_raw.prototypes("lab")) do table.insert(labs, {name = name, lab = lab}) end
  table.sort(labs, function(a, b) return a.name < b.name end)

  local best, best_lab = nil, nil
  for _, entry in ipairs(labs) do
    local candidate, accepted = {}, {}
    for _, input in ipairs(entry.lab.inputs or {}) do accepted[input] = true end
    for _, ingredient in ipairs(source) do
      local name = M.ingredient_name(ingredient)
      if name and accepted[name] then table.insert(candidate, {name, M.ingredient_amount(ingredient)}) end
    end
    if #candidate > 0 and M.valid_research_ingredients(candidate)
      and (not best or #candidate > #best) then
      best, best_lab = candidate, entry.name
    end
  end

  if best then
    log("[more-infinite-research] Reduced science packs for " .. tostring(context or "unknown technology")
      .. " to a lab-compatible subset accepted by " .. best_lab .. ".")
    return best, "reduced"
  end
  log("[more-infinite-research] No lab can research the selected science packs for "
    .. tostring(context or "unknown technology") .. ".")
  return nil, "invalid"
end

return M
