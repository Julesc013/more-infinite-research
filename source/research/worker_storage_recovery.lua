-- One authored native holder for explicitly prepared default worker-storage4.
-- Data callers supply the ordinary MIR default, never a foreign prototype.
local M = {id="mir-worker-storage-preservation-4", canonical="worker-robots-storage-4"}
M.ordinary_default_id = "mir-worker-storage-default-5"
M.ordinary_provider_id = "mir-worker-storage-provider-4"
M.provider_debit_id = "mir-worker-storage-provider-debit-4"
M.head_id = "mir-worker-storage-head-4"
local target = require("platform.target")
local MAX = 4294967295

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

function M.prototype(authored)
  assert(type(authored) == "table" and authored.name == M.canonical
    and authored.level == 4 and authored.max_level == "infinite", "MIR worker recovery requires its authored default4")
  local out = copy(authored)
  -- Empty/new/reset forces must not acquire another research option. The
  -- preparation command alone restores an unfinished source's native flags.
  out.name, out.hidden, out.enabled, out.visible_when_disabled = M.id, true, false, false
  out.order = "zz[mir-worker-storage-preservation]"
  return out
end

-- Profiles which do not expose the MIR default worker stream have no recovery
-- contract to continue. Keep the stable native identity empty without adding
-- removed Base prerequisites/sciences to that profile. Its deliberately
-- different work contract cannot admit an invested prepared default save.
function M.uninvested(authored, science)
  assert(type(science) == "string" and science ~= "", "MIR worker recovery needs an admitted science input")
  local out = M.prototype(authored)
  out.enabled, out.prerequisites = false, {}
  out.unit = {count=1, time=1, ingredients={{science, 1}}}
  return out
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function atom(value)
  local text = type(value) == "number" and string.format("%.17g", value) or value
  assert(type(text) == "string", "MIR worker recovery contract scalar is invalid")
  return #text .. ":" .. text
end

-- A bounded exact native contract, not a reconstruction of previous settings.
-- Names/presentation/force flags differ deliberately; all gameplay fields below
-- must match before transfer and remain identical on the protected holder.
function M.fingerprint(prototype)
  assert(prototype and prototype.level == 4 and prototype.max_level == MAX,
    "MIR worker recovery requires an infinite native level4 contract")
  local effects = prototype.effects
  assert(type(effects) == "table" and #effects == 1, "MIR worker recovery requires the authored worker effect")
  local effect = effects[1]
  assert(type(effect) == "table", "MIR worker recovery effect contract is invalid")
  local hidden = effect.hidden
  -- F200's runtime TechnologyModifier omits hidden. Its absence represents
  -- false; F210 requires the boolean. Never change the native effect table.
  if hidden == nil and target.id == "f200" then hidden = false end
  assert(effect.type == "worker-robot-storage"
    and finite(effect.modifier) and effect.modifier >= 0 and type(hidden) == "boolean",
    "MIR worker recovery effect contract is invalid")
  for key in pairs(effect) do
    assert(key == "type" or key == "modifier" or key == "hidden", "MIR worker recovery effect has an unsupported field")
  end
  local ingredients = prototype.research_unit_ingredients
  assert(type(ingredients) == "table" and #ingredients > 0 and #ingredients <= 32,
    "MIR worker recovery science contract is invalid")
  assert(type(prototype.ignore_tech_cost_multiplier) == "boolean", "MIR worker recovery map-price contract is unavailable")
  local out = {"worker-storage-1", atom(effect.type), atom(effect.modifier), tostring(hidden),
    tostring(prototype.ignore_tech_cost_multiplier)}
  local formula = prototype.research_unit_count_formula
  if formula ~= nil then
    assert(type(formula) == "string" and #formula > 0 and #formula <= 1024,
      "MIR worker recovery formula contract is invalid")
    out[#out + 1], out[#out + 2] = "formula", atom(formula)
  else
    local count = prototype.research_unit_count
    assert(finite(count) and count > 0 and count % 1 == 0, "MIR worker recovery count contract is invalid")
    out[#out + 1], out[#out + 2] = "count", atom(count)
  end
  local energy = prototype.research_unit_energy
  assert(finite(energy) and energy > 0, "MIR worker recovery time contract is invalid")
  out[#out + 1], out[#out + 2] = atom(energy), atom(#ingredients)
  for _, ingredient in ipairs(ingredients) do
    assert(type(ingredient) == "table" and type(ingredient.name) == "string"
      and finite(ingredient.amount) and ingredient.amount > 0 and ingredient.amount % 1 == 0,
      "MIR worker recovery science entry is invalid")
    for key in pairs(ingredient) do
      assert(key == "name" or key == "amount", "MIR worker recovery science has an unsupported field")
    end
    out[#out + 1], out[#out + 2] = atom(ingredient.name), atom(ingredient.amount)
  end
  local names = {}
  for key, prerequisite in pairs(prototype.prerequisites or {}) do
    local name = type(key) == "string" and key or prerequisite and prerequisite.name
    assert(type(name) == "string" and name ~= "" and #names < 32,
      "MIR worker recovery prerequisite contract is invalid")
    names[#names + 1] = name
  end
  table.sort(names)
  out[#out + 1] = atom(#names)
  for _, name in ipairs(names) do out[#out + 1] = atom(name) end
  return table.concat(out, "|")
end

-- Compare only the caller's detached owned emissions. The projection uses
-- authored unit fields; it is not an observation of native saved research.
local function emitted_contract(row)
  assert(type(row) == "table" and row.name == M.canonical and type(row.unit) == "table")
  local effects, ingredients, prerequisites = copy(row.effects), {}, {}
  for _, effect in ipairs(effects) do
    if effect.hidden == nil and target.id == "f210" then effect.hidden = false end
  end
  for index, ingredient in ipairs(row.unit.ingredients) do
    ingredients[index] = {name=ingredient[1], amount=ingredient[2]}
  end
  for _, name in ipairs(row.prerequisites or {}) do
    assert(type(name) == "string" and prerequisites[name] == nil)
    prerequisites[name] = {name=name}
  end
  return M.fingerprint({level=row.level, max_level=row.max_level == "infinite" and MAX or row.max_level,
    effects=effects, research_unit_count_formula=row.unit.count_formula, research_unit_count=row.unit.count,
    research_unit_energy=row.unit.time * 60, research_unit_ingredients=ingredients, prerequisites=prerequisites,
    ignore_tech_cost_multiplier=row.ignore_tech_cost_multiplier == true})
end

function M.matches_default(emitted, authored)
  local expected = emitted_contract(authored)
  local ok, actual = pcall(emitted_contract, emitted)
  return ok and actual == expected
end

-- Draft constructors only: callers own admission, settings and publication.
-- Neither constructor normalizes a provider's level, price or paid basis.
local function owner_copy(value, stack)
  local kind = type(value)
  assert(kind == "table" or kind == "string" or kind == "boolean" or kind == "number",
    "MIR worker owner requires plain authored data")
  if kind == "number" then assert(finite(value), "MIR worker owner has a nonfinite value") end
  if kind ~= "table" then return value end
  stack = stack or {}
  assert(getmetatable(value) == nil and not stack[value], "MIR worker owner has a metatable or cycle")
  stack[value] = true
  local out = {}
  for key, item in pairs(value) do
    assert(type(key) == "string" or type(key) == "number" and finite(key), "MIR worker owner has an invalid key")
    out[key] = owner_copy(item, stack)
  end
  stack[value] = nil
  return out
end

local function owner_array(value, limit)
  assert(type(value) == "table" and #value <= limit, "MIR worker owner array is invalid")
  local count = 0
  for key in pairs(value) do
    assert(type(key) == "number" and key % 1 == 0 and key >= 1 and key <= #value,
      "MIR worker owner array is not dense")
    count = count + 1
  end
  assert(count == #value, "MIR worker owner array is not dense")
end

local function owner_source(authored, id)
  assert(type(authored) == "table" and authored.type == "technology"
    and type(authored.name) == "string" and authored.name:match("%-4$")
    and authored.name ~= M.id and authored.name ~= M.ordinary_default_id
    and authored.name ~= M.ordinary_provider_id and authored.name ~= M.provider_debit_id and authored.name ~= M.head_id
    and authored.level == 4 and authored.max_level == "infinite",
    "MIR worker owner requires an authored infinite level4 source")
  for _, field in ipairs({"hidden", "enabled", "visible_when_disabled", "ignore_tech_cost_multiplier"}) do
    assert(authored[field] == nil or type(authored[field]) == "boolean", "MIR worker owner boolean is invalid")
  end
  owner_array(authored.effects, 1)
  assert(#authored.effects == 1 and type(authored.effects[1]) == "table"
    and authored.effects[1].type == "worker-robot-storage"
    and finite(authored.effects[1].modifier) and authored.effects[1].modifier >= 0,
    "MIR worker owner requires one authored nonnegative worker effect")
  local unit = authored.unit
  assert(type(unit) == "table" and finite(unit.time) and unit.time > 0
    and ((unit.count == nil and type(unit.count_formula) == "string" and unit.count_formula ~= "")
      or (unit.count_formula == nil and finite(unit.count) and unit.count > 0
        and unit.count < 18446744073709551616 and unit.count % 1 == 0)),
    "MIR worker owner unit contract is invalid")
  owner_array(unit.ingredients, 32)
  assert(#unit.ingredients > 0, "MIR worker owner requires science")
  for _, ingredient in ipairs(unit.ingredients) do
    owner_array(ingredient, 2)
    assert(#ingredient == 2 and type(ingredient[1]) == "string" and ingredient[1] ~= ""
      and finite(ingredient[2]) and ingredient[2] > 0 and ingredient[2] <= 65535 and ingredient[2] % 1 == 0,
      "MIR worker owner science entry is invalid")
  end
  owner_array(authored.prerequisites or {}, 32)
  local seen = {}
  for _, name in ipairs(authored.prerequisites or {}) do
    assert(type(name) == "string" and name ~= "" and name ~= authored.name and name ~= id and not seen[name],
      "MIR worker owner prerequisite is invalid")
    seen[name] = true
  end
  return owner_copy(authored)
end

function M.ordinary(authored, id)
  assert(id == M.ordinary_provider_id, "MIR worker ordinary identity is invalid")
  local out = owner_source(authored, id)
  out.name, out.hidden = id, false
  return out
end

function M.default_tail(authored)
  assert(type(authored) == "table" and authored.name == M.canonical,
    "MIR worker default tail requires authored canonical4")
  local out = owner_source(authored, M.ordinary_default_id)
  out.name, out.level, out.hidden = M.ordinary_default_id, 5, false
  out.prerequisites = out.prerequisites or {}
  assert(#out.prerequisites < 32, "MIR worker default tail has too many prerequisites")
  for _, name in ipairs(out.prerequisites) do
    assert(name ~= M.head_id, "MIR worker default source already has a head gate")
  end
  out.prerequisites[#out.prerequisites + 1] = M.head_id
  return out
end

function M.head_gate(authored)
  assert(type(authored) == "table" and authored.name == M.canonical,
    "MIR worker head gate requires authored canonical4")
  local out = owner_source(authored, M.head_id)
  out.name, out.max_level = M.head_id, 4
  out.hidden, out.enabled, out.visible_when_disabled = true, false, false
  out.effects[1].modifier = 0
  out.prerequisites = {}
  out.unit = {count=1, time=1, ingredients={{authored.unit.ingredients[1][1], 1}}}
  return out
end

-- Native source4 and tail5 have different real initial levels. Their exact
-- work/effect contracts match after removing only the stable zero-effect gate.
-- This comparison never writes either native object or changes the legacy key.
function M.matches_default_tail(source, tail)
  local ok, matches = pcall(function()
    assert(source and source.name == M.canonical and source.level == 4)
    assert(tail and tail.name == M.ordinary_default_id and tail.level == 5 and tail.max_level == MAX)
    local expected = M.fingerprint(source)
    local prerequisites, gate = {}, false
    for key, prerequisite in pairs(tail.prerequisites or {}) do
      local name = type(key) == "string" and key or prerequisite and prerequisite.name
      assert(type(name) == "string" and name ~= M.canonical)
      if name == M.head_id then assert(not gate); gate = true
      else assert(prerequisites[name] == nil); prerequisites[name] = {name=name} end
    end
    assert(gate, "MIR worker default tail has no stable head gate")
    return expected == M.fingerprint({level=4, max_level=tail.max_level, effects=tail.effects,
      prerequisites=prerequisites, research_unit_count_formula=tail.research_unit_count_formula,
      research_unit_count=tail.research_unit_count, research_unit_energy=tail.research_unit_energy,
      research_unit_ingredients=tail.research_unit_ingredients,
      ignore_tech_cost_multiplier=tail.ignore_tech_cost_multiplier})
  end)
  return ok and matches
end

function M.debit(authored)
  local out = owner_source(authored, M.provider_debit_id)
  out.name, out.hidden, out.enabled, out.visible_when_disabled = M.provider_debit_id, true, false, false
  local modifier = out.effects[1].modifier
  out.effects[1].modifier = modifier == 0 and 0 or -modifier
  return out
end

return M
