-- Local family preflight. Definitions are exclusively owned native tables.
-- This checks MIR's write boundary; Factorio still validates its full schema.
local M = {}

local item_types = {
  "tool", "item", "ammo", "capsule", "gun", "armor", "module", "repair-tool",
  "mining-tool", "item-with-entity-data", "item-with-inventory", "item-with-label",
  "item-with-tags", "selection-tool", "copy-paste-tool", "blueprint", "blueprint-book",
  "deconstruction-item", "upgrade-item", "spidertron-remote", "rail-planner",
  "space-platform-starter-pack"
}

local function reject(message)
  error("MIR technology preflight: " .. message, 3)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sequence(value, label)
  if type(value) ~= "table" or getmetatable(value) ~= nil then reject(label .. " must be a plain array") end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then reject(label .. " has an invalid index") end
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then reject(label .. " has a missing entry") end
  end
  return count
end

local function item_exists(raw, name)
  for _, kind in ipairs(item_types) do
    if raw[kind] and raw[kind][name] then return true end
  end
  return false
end

function M.install(prototypes, data_stage)
  local count = sequence(prototypes, "technologies")
  if count == 0 then reject("technologies must not be empty") end
  local raw = data_stage.raw
  local names, indegree, followers = {}, {}, {}

  -- Resolve the complete local namespace before checking any references.
  for index = 1, count do
    local prototype = prototypes[index]
    if type(prototype) ~= "table" or getmetatable(prototype) ~= nil
      or prototype.type ~= "technology" or type(prototype.name) ~= "string" or prototype.name == "" then
      reject("entry " .. index .. " must name a technology")
    end
    local name = prototype.name
    if names[name] or (raw.technology and raw.technology[name]) then reject("duplicate technology " .. name) end
    names[name], indegree[name], followers[name] = prototype, 0, {}
  end

  for index = 1, count do
    local prototype = prototypes[index]
    local name = prototype.name
    local unit = prototype.unit
    if type(unit) ~= "table" or not finite(unit.time) or unit.time <= 0 then reject(name .. " has invalid research time") end
    if unit.count ~= nil then
      if not finite(unit.count) or unit.count <= 0 or unit.count ~= math.floor(unit.count) or unit.count_formula ~= nil then
        reject(name .. " has invalid research count")
      end
    elseif type(unit.count_formula) ~= "string" or unit.count_formula == "" then
      reject(name .. " needs a research count or formula")
    end
    local ingredient_count = sequence(unit.ingredients, name .. " ingredients")
    if ingredient_count == 0 then reject(name .. " has no research ingredients") end
    for _, ingredient in ipairs(unit.ingredients) do
      if type(ingredient) ~= "table" or type(ingredient[1]) ~= "string"
        or not finite(ingredient[2]) or ingredient[2] < 1 or ingredient[2] > 65535
        or ingredient[2] ~= math.floor(ingredient[2]) or not item_exists(raw, ingredient[1]) then
        reject(name .. " has an invalid or missing research ingredient")
      end
    end
    local seen = {}
    local prerequisites = prototype.prerequisites or {}
    sequence(prerequisites, name .. " prerequisites")
    for _, prerequisite in ipairs(prerequisites) do
      if type(prerequisite) ~= "string" or seen[prerequisite] then reject(name .. " has invalid prerequisites") end
      seen[prerequisite] = true
      if names[prerequisite] then
        indegree[name] = indegree[name] + 1
        local next_nodes = followers[prerequisite]
        next_nodes[#next_nodes + 1] = name
      elseif not (raw.technology and raw.technology[prerequisite]) then
        reject(name .. " has missing prerequisite " .. prerequisite)
      end
    end
    local effects = prototype.effects or {}
    sequence(effects, name .. " effects")
    for _, effect in ipairs(effects) do
      if type(effect) ~= "table" or type(effect.type) ~= "string" then reject(name .. " has an invalid effect") end
      if effect.modifier ~= nil and not finite(effect.modifier) then reject(name .. " has a nonfinite modifier") end
      if effect.type == "change-recipe-productivity" or effect.type == "unlock-recipe" then
        if type(effect.recipe) ~= "string" or not (raw.recipe and raw.recipe[effect.recipe]) then
          reject(name .. " has a missing recipe effect target")
        end
        if effect.type == "change-recipe-productivity" and not finite(effect.change) then
          reject(name .. " has invalid recipe productivity")
        end
      end
    end
  end

  -- Kahn's local check permits forward references without recursive stack growth.
  local queue = {}
  for index = 1, count do
    local name = prototypes[index].name
    if indegree[name] == 0 then queue[#queue + 1] = name end
  end
  local cursor = 1
  while cursor <= #queue do
    for _, name in ipairs(followers[queue[cursor]]) do
      indegree[name] = indegree[name] - 1
      if indegree[name] == 0 then queue[#queue + 1] = name end
    end
    cursor = cursor + 1
  end
  if #queue ~= count then reject("local prerequisite cycle") end
  data_stage:extend(prototypes)
end

return M
