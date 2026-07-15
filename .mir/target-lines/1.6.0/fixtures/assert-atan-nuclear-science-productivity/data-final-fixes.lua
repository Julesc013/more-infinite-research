local techs = data.raw.technology or {}
local labs = data.raw.lab or {}

local tech = techs["recipe-prod-research_science_pack_productivity-1"]

local function fail(message)
  error("MIR ATAN Nuclear Science validation failed: " .. message)
end

if not tech then fail("missing generated science-pack productivity technology.") end

local function has_prerequisite(prerequisite)
  for _, name in ipairs(tech.prerequisites or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local function ingredient_names()
  local out = {}
  for _, ingredient in ipairs(((tech and tech.unit) and tech.unit.ingredients) or {}) do
    local name = ingredient.name or ingredient[1]
    if name then out[name] = true end
  end
  return out
end

local function lab_accepts_all(science)
  for _, lab in pairs(labs) do
    local accepted = {}
    for _, input in ipairs(lab.inputs or {}) do accepted[input] = true end
    local ok = true
    for pack, _ in pairs(science) do
      if not accepted[pack] then
        ok = false
        break
      end
    end
    if ok then return true end
  end
  return false
end

local found_pack_effect = false
local found_atom_forge_effect = false
for _, effect in ipairs(tech.effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "nuclear-science-pack" then
    found_pack_effect = true
    local change = tonumber(effect.change) or 0
    if math.abs(change - 0.10) > 0.000000001 then
      fail("nuclear-science-pack should use +0.10, got " .. tostring(effect.change) .. ".")
    end
  elseif effect.type == "change-recipe-productivity" and effect.recipe == "atan-atom-forge" then
    found_atom_forge_effect = true
  end
end

if not found_pack_effect then fail("nuclear-science-pack did not receive science-pack productivity.") end
if found_atom_forge_effect then fail("atan-atom-forge should not receive science-pack productivity.") end
if not has_prerequisite("atan-nuclear-science") then
  fail("science-pack productivity should require the ATAN nuclear science unlock technology.")
end

local science = ingredient_names()
if not science["nuclear-science-pack"] then
  fail("science-pack productivity should include the active nuclear-science-pack lab input.")
end
if not lab_accepts_all(science) then
  fail("science-pack productivity selected science packs that no active lab accepts.")
end
