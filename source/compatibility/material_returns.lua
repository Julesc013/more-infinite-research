-- A bounded typed return proof for already-selected F210 material routes.
-- Callers own identities, route admission and publication. Any ingredient can
-- lead to its own variant's outputs; this is not a factory/profitability solver.
local items = require("compatibility.product_targets")
local M = {}

local function fail(message)
  error("MIR material return path: " .. message, 3)
end

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function identity(entry)
  if type(entry) ~= "table" then fail("unsupported process entry") end
  local kind, name = entry.type or "item", entry.name or entry[1]
  if (kind ~= "item" and kind ~= "fluid") or type(name) ~= "string" or name == "" then
    fail("unsupported process identity")
  end
  return kind .. ":" .. name, kind, name
end

-- F210 supports these probability fields, but not the legacy probability
-- field. Unknown representations retain a possible edge. Fixed amounts take
-- priority over ranges; bonus exclusions do not erase baseline production.
local function definitely_zero(entry)
  if entry.probability ~= nil or ((entry.type or "item") ~= "item"
      and entry.extra_count_fraction ~= nil) then return false end
  local amount = entry.amount
  if amount == nil then amount = entry[2] end
  if amount == nil then
    if not finite_nonnegative(entry.amount_min) or not finite_nonnegative(entry.amount_max) then return false end
    amount = math.max(entry.amount_min, entry.amount_max)
  end
  local extra, probability = entry.extra_count_fraction, entry.independent_probability
  if extra == nil then extra = 0 end
  if probability == nil then probability = 1 end
  if not finite_nonnegative(amount) or not finite_nonnegative(extra) or extra > 1
      or not finite_nonnegative(probability) or probability > 1 then return false end
  local shared = entry.shared_probability
  if shared ~= nil and (type(shared) ~= "table" or not finite_nonnegative(shared.min)
      or not finite_nonnegative(shared.max) or shared.max > 1 or shared.min > shared.max) then return false end
  return probability == 0 or (shared ~= nil and shared.min == shared.max) or (amount == 0 and extra == 0)
end

local function entries(definition, field)
  local rows = definition[field]
  if rows ~= nil then
    if type(rows) ~= "table" then fail("unsupported process " .. field) end
    local count, maximum = 0, 0
    for key in pairs(rows) do
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then fail("unsupported process array") end
      count = count + 1
      maximum = math.max(maximum, key)
    end
    if count ~= maximum then fail("incomplete process array") end
    return rows
  end
  if field == "results" and definition.result ~= nil then
    if type(definition.result) ~= "string" or definition.result == "" then fail("unsupported process result") end
    return {{name=definition.result, amount=definition.result_count or 1}}
  end
  return {}
end

local function fuel_is_zero(value)
  if value == nil then return true end
  if type(value) ~= "string" then return false end
  local number = value:match("^%s*([%d%.]+)%s*[kMGTPEZYRQ]?[JW]%s*$")
  return number ~= nil and tonumber(number) == 0
end

function M.prepare(raw)
  -- One ingredient index, with references to individual effective variants.
  -- No ingredient x output graph: a reached variant's outputs expand once.
  local consumers = {}
  local function index(definition)
    for _, ingredient in ipairs(entries(definition, "ingredients")) do
      local key = identity(ingredient)
      local rows = consumers[key]
      if rows == nil then rows = {}; consumers[key] = rows end
      rows[#rows + 1] = definition
    end
  end
  for _, recipe in pairs(raw.recipe or {}) do
    if type(recipe) ~= "table" then fail("unsupported recipe") end
    if type(recipe.normal) == "table" or type(recipe.expensive) == "table" then
      if type(recipe.normal) == "table" then index(recipe.normal) end
      if type(recipe.expensive) == "table" then index(recipe.expensive) end
    else
      index(recipe)
    end
  end
  return {raw=raw, consumers=consumers}
end

-- The phase-local ingredient index is reused only while its recipes remain
-- unchanged. No global cache or persistent state can grant admission later.
function M.validate(raw, products, ingredients, context, label)
  local destinations = {}
  for _, ingredient in ipairs(entries({ingredients=ingredients}, "ingredients")) do
    destinations[identity(ingredient)] = true
  end
  if next(destinations) == nil then return end
  context = context or M.prepare(raw)
  if type(context) ~= "table" or context.raw ~= raw or type(context.consumers) ~= "table" then
    fail("the ingredient index belongs to another input")
  end
  local consumers = context.consumers
  local queue, reached, expanded = {}, {}, {}
  local function enqueue(key, kind, name)
    if destinations[key] then fail((label or "selected route") .. " returns to " .. kind .. ":" .. name) end
    if not reached[key] then
      reached[key] = true
      queue[#queue + 1] = {key=key, kind=kind, name=name}
    end
  end
  for _, product in ipairs(entries({results=products}, "results")) do
    local key, kind, name = identity(product)
    if not definitely_zero(product) then enqueue(key, kind, name) end
  end
  local next_node = 1
  while next_node <= #queue do
    local node = queue[next_node]
    next_node = next_node + 1
    for _, definition in ipairs(consumers[node.key] or {}) do
      if not expanded[definition] then
        expanded[definition] = true
        for _, result in ipairs(entries(definition, "results")) do
          local key, kind, name = identity(result)
          if not definitely_zero(result) then enqueue(key, kind, name) end
        end
      end
    end
    if node.kind == "item" then
      local item = items.item_prototype(raw, node.name)
      if item then
        local spoil, burnt = item.spoil_result, item.burnt_result
        if type(spoil) == "string" and spoil ~= "" and type(item.spoil_ticks) == "number"
            and item.spoil_ticks > 0 then enqueue("item:" .. spoil, "item", spoil) end
        if type(burnt) == "string" and burnt ~= "" and not fuel_is_zero(item.fuel_value) then
          enqueue("item:" .. burnt, "item", burnt)
        end
      end
    end
  end
end

return M
