-- Continue the one authored worker-storage family after a foreign finite
-- chain. Read its connected levels only; never mutate the provider's rows.
local M = {}
local PREFIX = "worker-robots-storage-"
local MAX_LEVEL = 4294967295

-- Published4.7.3 metadata.lua classified exactly these modifier types as
-- native units. Its worker setting scaled a vector only when every effect
-- shared this positive numeric unit; mixed vectors were preserved whole.
local NATIVE_MODIFIERS = {
  ["bulk-inserter-capacity-bonus"]=true, ["cargo-landing-pad-count"]=true,
  ["character-build-distance"]=true, ["character-inventory-slots-bonus"]=true,
  ["character-item-drop-distance"]=true, ["character-logistic-trash-slots"]=true,
  ["character-reach-distance"]=true, ["character-resource-reach-distance"]=true,
  ["inserter-stack-size-bonus"]=true, ["max-cargo-bay-unloading-distance"]=true,
  ["stack-inserter-capacity-bonus"]=true, ["worker-robot-storage"]=true,
}

local function fail(name, reason)
  error("MIR worker robot storage: " .. name .. ": " .. reason, 3)
end

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function integer(value)
  return positive(value) and value == math.floor(value)
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then fail("effects", "cyclic input") end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function array(value, name)
  if type(value) ~= "table" or getmetatable(value) ~= nil then fail(name, "expected a plain array") end
  local count = 0
  for key in pairs(value) do
    if not integer(key) or key > #value then fail(name, "invalid array index") end
    count = count + 1
  end
  if count ~= #value then fail(name, "sparse array") end
  return count
end

local function count_at(technology, level, evaluate)
  local unit = technology.unit
  if unit.count ~= nil then
    if not integer(unit.count) or unit.count_formula ~= nil then fail(technology.name, "invalid research count") end
    return unit.count
  end
  if type(unit.count_formula) ~= "string" or unit.count_formula == "" or type(evaluate) ~= "function" then
    fail(technology.name, "research formula requires the engine expression evaluator")
  end
  local count = evaluate(unit.count_formula, {L=level, l=level})
  if not positive(count) then fail(technology.name, "research formula gives a nonpositive or nonfinite cost") end
  return count
end

local function finite_stage(technology, name, level, predecessor)
  if type(technology) ~= "table" or technology.type ~= "technology" or technology.name ~= name
      or technology.level ~= nil and technology.level ~= level then fail(name, "invalid finite identity") end
  local last = technology.max_level or level
  if not integer(last) or last < level or last >= MAX_LEVEL then fail(name, "invalid finite maximum level") end
  local anchored, seen = false, {}
  array(technology.prerequisites or {}, name .. " prerequisites")
  for _, id in ipairs(technology.prerequisites or {}) do
    if type(id) ~= "string" or id == "" or id == name or seen[id] then fail(name, "invalid prerequisite") end
    seen[id] = true
    if id == predecessor then anchored = true end
  end
  if not anchored then fail(name, "missing predecessor " .. predecessor) end
  local unit = technology.unit
  if type(unit) ~= "table" or not positive(unit.time) then fail(name, "invalid research time") end
  if array(unit.ingredients, name .. " science") == 0 then fail(name, "missing research science") end
  seen = {}
  for _, ingredient in ipairs(unit.ingredients) do
    if type(ingredient) ~= "table" or type(ingredient[1]) ~= "string" or ingredient[1] == ""
        or seen[ingredient[1]] or not integer(ingredient[2]) or ingredient[2] > 65535 then
      fail(name, "invalid research science")
    end
    seen[ingredient[1]] = true
  end
  array(technology.effects, name .. " effects")
  local storage
  for _, effect in ipairs(technology.effects) do
    if type(effect) ~= "table" or type(effect.type) ~= "string" then fail(name, "invalid research effect") end
    if effect.type == "worker-robot-storage" then
      if storage ~= nil or not positive(effect.modifier) then fail(name, "invalid worker storage effect") end
      storage = effect.modifier
    end
  end
  if storage == nil then fail(name, "missing worker storage effect") end
  return last, storage
end

function M.use_identity(row, route)
  row.id, row.level, row.predecessor = route.technology, route.level, route.predecessor
end

-- The first collision must follow native3. Then each finite maximum names
-- the next level; a ranged4..8 is followed by9, never the vacant name5.
-- A qualified infinite owner terminates the chain without a MIR duplicate.
function M.adapt(row, raw, infinite_owner, evaluate, selected_ingredients)
  local technologies = type(raw) == "table" and raw.technology
  local first = technologies and technologies[PREFIX .. "4"]
  if type(first) ~= "table" or first.max_level == "infinite" or technologies[PREFIX .. "3"] == nil then return nil end
  local level, predecessor = 4, PREFIX .. "3"
  local finite, previous, last, last_level, modifier, last_count = {}, technologies[predecessor]
  local legacy_compatible = type(previous) == "table" and type(previous.unit) == "table"
    and integer(previous.unit.count) and previous.unit.count_formula == nil
  while technologies[PREFIX .. level] ~= nil do
    local name, technology = PREFIX .. level, technologies[PREFIX .. level]
    if type(technology) == "table" and technology.max_level == "infinite" then
      local candidate = {id=name, level=level, predecessor=predecessor, effects=row.effects}
      if not infinite_owner(candidate, technology) then fail(name, "invalid existing infinite owner") end
      local route = {technology=name, level=level, predecessor=predecessor, owned=false,
        finite=finite, legacy_compatible=false}
      M.use_identity(row, route)
      return route
    end
    local ending, effect = finite_stage(technology, name, level, predecessor)
    legacy_compatible = legacy_compatible and ending == level
      and integer(technology.unit.count) and technology.unit.count_formula == nil
    -- Validate every consumed cost, including earlier ranges. Only the last
    -- two costs feed the existing inherited continuation formula below.
    last_count = count_at(technology, ending, evaluate)
    finite[#finite + 1] = {name=name, max_level=ending}
    previous, last, last_level, modifier = last or previous, technology, level, effect
    predecessor, level = name, ending + 1
  end
  local previous_count
  if level - 1 > last_level then previous_count = count_at(last, level - 2, evaluate)
  elseif type(previous) == "table" and type(previous.unit) == "table" then
    previous_count = count_at(previous, last_level - 1, evaluate)
  else fail(predecessor, "missing preceding research cost") end
  local route = {technology=PREFIX .. level, level=level, predecessor=predecessor, owned=true,
    finite=finite, legacy_compatible=legacy_compatible and #last.effects == 1}
  M.use_identity(row, route)
  row.prerequisites, row.exact_prerequisites = {}, true
  for index, name in ipairs(last.prerequisites) do row.prerequisites[index] = name end
  row.prerequisites[#row.prerequisites + 1] = predecessor
  row.inheritance = {last_count=last_count, previous_count=previous_count, research_time=last.unit.time}
  row.ingredients = {}
  local seen = {}
  for index, ingredient in ipairs(last.unit.ingredients) do
    row.ingredients[index], seen[ingredient[1]] = {ingredient[1], ingredient[2]}, true
  end
  -- Published4.7.3 worker defaults inherit the terminal vector and add only
  -- electromagnetic science. The captured default row also contains its
  -- native predecessor's packs; those are not an additive requirement for
  -- another provider. Global ingredient policy runs after this construction.
  for _, ingredient in ipairs(selected_ingredients or {}) do
    if ingredient[1] == "electromagnetic-science-pack" and not seen[ingredient[1]] then
      row.ingredients[#row.ingredients + 1], seen[ingredient[1]] = {ingredient[1], ingredient[2]}, true
    end
  end
  row.effects = {{type="worker-robot-storage", scale=modifier}}
  row.inherited_worker_storage_effects = copy(last.effects)
  row.scale_inherited_worker_storage_effects = true
  for _, effect in ipairs(last.effects) do
    if not NATIVE_MODIFIERS[effect.type] or not positive(effect.modifier) then
      row.scale_inherited_worker_storage_effects = false
    end
  end
  return route
end

-- One explicit current identity crosses the existing data/control bridge.
-- This record is not saved history and grants no migration authority.
function M.copy_route(value)
  if value == nil then return nil end
  if type(value) ~= "table" or getmetatable(value) ~= nil or type(value.owned) ~= "boolean"
      or type(value.legacy_compatible) ~= "boolean"
      or not integer(value.level) or value.level < 5 or value.level >= MAX_LEVEL
      or value.technology ~= PREFIX .. value.level then fail("admission", "invalid continuation identity") end
  for key in pairs(value) do
    if key ~= "technology" and key ~= "level" and key ~= "predecessor" and key ~= "owned"
        and key ~= "finite" and key ~= "legacy_compatible" then
      fail("admission", "unknown continuation field")
    end
  end
  if array(value.finite, "admission finite stages") == 0 then fail("admission", "missing finite stages") end
  local finite, level, predecessor = {}, 4, PREFIX .. "3"
  for index, stage in ipairs(value.finite) do
    if type(stage) ~= "table" or getmetatable(stage) ~= nil or stage.name ~= PREFIX .. level
        or not integer(stage.max_level) or stage.max_level < level or stage.max_level >= MAX_LEVEL then
      fail("admission", "invalid finite stage")
    end
    for key in pairs(stage) do
      if key ~= "name" and key ~= "max_level" then fail("admission", "unknown finite stage field") end
    end
    finite[index] = {name=stage.name, max_level=stage.max_level}
    predecessor, level = stage.name, stage.max_level + 1
  end
  if value.level ~= level or value.predecessor ~= predecessor then fail("admission", "disconnected continuation") end
  return {technology=value.technology, level=level, predecessor=predecessor, owned=value.owned,
    finite=finite, legacy_compatible=value.legacy_compatible}
end

return M
