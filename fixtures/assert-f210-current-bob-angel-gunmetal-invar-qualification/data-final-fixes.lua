-- Package-excluded qualification of the exact staged Gunmetal/Invar technology
-- contract. It binds declaration-level owners and effects only; control.lua
-- retains its narrow persisted early-research create/reload check.
local subjects = {
  {
    family = "gunmetal",
    recipe = "angels-plate-gunmetal",
    unlock = "angels-gunmetal-smelting-1",
    early = "recipe-prod-research_material_gunmetal-1",
    continuation = "recipe-prod-research_material_gunmetal-4"
  },
  {
    family = "invar",
    recipe = "angels-plate-invar",
    unlock = "angels-invar-smelting-1",
    early = "recipe-prod-research_material_invar-1",
    continuation = "recipe-prod-research_material_invar-4"
  }
}

local function fail(message)
  error("[mir-f210-current-ba-gunmetal-invar] " .. message)
end

local function exact_strings(values, expected, label)
  if type(values) ~= "table" then fail(label .. " is absent") end
  local actual, seen = {}, {}
  for _, value in ipairs(values) do
    if type(value) ~= "string" or seen[value] then fail(label .. " has an invalid member") end
    seen[value] = true
    actual[#actual + 1] = value
  end
  table.sort(actual)
  local wanted = {}
  for _, value in ipairs(expected) do wanted[#wanted + 1] = value end
  table.sort(wanted)
  if #actual ~= #wanted then fail(label .. " cardinality differs") end
  for index, value in ipairs(wanted) do
    if actual[index] ~= value then fail(label .. " differs") end
  end
end

local function exact_science(unit, expected, label)
  if type(unit) ~= "table" or type(unit.ingredients) ~= "table" then fail(label .. " science is absent") end
  local actual, count = {}, 0
  for _, entry in ipairs(unit.ingredients) do
    local name, amount = entry.name or entry[1], entry.amount or entry[2]
    if type(name) ~= "string" or type(amount) ~= "number" or actual[name] ~= nil then
      fail(label .. " science shape differs")
    end
    actual[name] = amount
    count = count + 1
  end
  if count ~= #expected then fail(label .. " science cardinality differs") end
  for _, entry in ipairs(expected) do
    if actual[entry[1]] ~= entry[2] then fail(label .. " science differs " .. entry[1]) end
  end
end

local function exact_effect(technology, recipe, label)
  if type(technology.effects) ~= "table" or #technology.effects ~= 1 then
    fail(label .. " effect cardinality differs")
  end
  local effect = technology.effects[1]
  if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
      or effect.recipe ~= recipe or effect.change ~= 0.02 then
    fail(label .. " effect differs")
  end
end

local function productivity_owners(recipe)
  local owners = {}
  for technology_name, technology in pairs(data.raw.technology or {}) do
    for _, effect in ipairs(technology.effects or {}) do
      if effect.type == "change-recipe-productivity" and effect.recipe == recipe then
        owners[#owners + 1] = technology_name .. ":" .. tostring(effect.change)
      end
    end
  end
  table.sort(owners)
  return owners
end

for _, subject in ipairs(subjects) do
  local early = data.raw.technology[subject.early]
  local continuation = data.raw.technology[subject.continuation]
  if type(early) ~= "table" or early.max_level ~= 3 then
    fail(subject.family .. " finite levels 1-3 differ")
  end
  if type(continuation) ~= "table" or continuation.level ~= 4 or continuation.max_level ~= "infinite" then
    fail(subject.family .. " continuation level 4+ range differs")
  end

  -- material_family() fixes base cost/time/effect; material_progression.attach()
  -- supplies the finite 1-3 stage; material_continuation.plan() starts at 4.
  if type(early.unit) ~= "table" or early.unit.count ~= nil
      or early.unit.count_formula ~= "200*2^(L-1)" or early.unit.time ~= 30 then
    fail(subject.family .. " finite research cost differs")
  end
  exact_science(early.unit, {{"automation-science-pack", 1}, {"logistic-science-pack", 1}}, subject.family .. " finite")
  exact_strings(early.prerequisites, {subject.unlock, "automation-science-pack", "logistic-science-pack"}, subject.family .. " finite prerequisites")

  if type(continuation.unit) ~= "table" or continuation.unit.count ~= nil
      or continuation.unit.count_formula ~= "1600+200*(L-4)" or continuation.unit.time ~= 30 then
    fail(subject.family .. " continuation research cost differs")
  end
  exact_science(continuation.unit, {
    {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"space-science-pack", 1}
  }, subject.family .. " continuation")
  exact_strings(continuation.prerequisites, {
    subject.unlock, "automation-science-pack", "logistic-science-pack", "space-science-pack", subject.early
  }, subject.family .. " continuation prerequisites")

  exact_effect(early, subject.recipe, subject.family .. " finite")
  exact_effect(continuation, subject.recipe, subject.family .. " continuation")
  local owners = productivity_owners(subject.recipe)
  exact_strings(owners, {subject.early .. ":0.02", subject.continuation .. ":0.02"}, subject.family .. " productivity owners")
end

log("[mir-f210-current-ba-gunmetal-invar] DATA PASS"
  .. " gunmetal=recipe-prod-research_material_gunmetal-1:1-3+recipe-prod-research_material_gunmetal-4:4+"
  .. " invar=recipe-prod-research_material_invar-1:1-3+recipe-prod-research_material_invar-4:4+"
  .. " effects=0.02 staged-owners=true")
local active_mods = {}
for name, version in pairs(mods or {}) do active_mods[#active_mods + 1] = name .. "@" .. version end
table.sort(active_mods)
log("[MIR_ACTIVE_MODS] " .. table.concat(active_mods, "|"))
