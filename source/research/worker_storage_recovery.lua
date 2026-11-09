-- One authored native holder for explicitly prepared default worker-storage4.
-- Data callers supply the ordinary MIR default, never a foreign prototype.
local M = {id="mir-worker-storage-preservation-4", canonical="worker-robots-storage-4"}
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
  assert(type(effect) == "table" and effect.type == "worker-robot-storage"
    and finite(effect.modifier) and effect.modifier >= 0 and type(effect.hidden) == "boolean",
    "MIR worker recovery effect contract is invalid")
  for key in pairs(effect) do
    assert(key == "type" or key == "modifier" or key == "hidden", "MIR worker recovery effect has an unsupported field")
  end
  local ingredients = prototype.research_unit_ingredients
  assert(type(ingredients) == "table" and #ingredients > 0 and #ingredients <= 32,
    "MIR worker recovery science contract is invalid")
  assert(type(prototype.ignore_tech_cost_multiplier) == "boolean", "MIR worker recovery map-price contract is unavailable")
  local out = {"worker-storage-1", atom(effect.type), atom(effect.modifier), tostring(effect.hidden),
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

return M
