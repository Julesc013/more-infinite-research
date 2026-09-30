local early_name = "recipe-prod-research_material_tin-1"
local continuation_name = "recipe-prod-research_material_tin-4"
local recipe_name = "bob-tin-plate"

local function fail(message)
  error("[mir-f210-current-bob-tin-level4] " .. message)
end

local function effect_change(technology)
  local count, change = 0, nil
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      count = count + 1
      change = effect.change
    end
  end
  if count ~= 1 or change ~= 0.02 then
    fail("technology productivity effect differs " .. technology.name .. " count="
      .. tostring(count) .. " change=" .. tostring(change))
  end
  return change
end

local function has_value(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function science_names(technology)
  local unit = technology.unit
  if type(unit) ~= "table" or type(unit.ingredients) ~= "table" or #unit.ingredients == 0 then
    fail("continuation science ingredients are absent")
  end
  local lab = data.raw.lab and data.raw.lab.lab
  if type(lab) ~= "table" or type(lab.inputs) ~= "table" then
    fail("base lab inputs are absent")
  end
  local names = {}
  for _, ingredient in ipairs(unit.ingredients) do
    local name = ingredient.name or ingredient[1]
    local amount = ingredient.amount or ingredient[2]
    if type(name) ~= "string" or type(amount) ~= "number" or amount <= 0 then
      fail("continuation science ingredient shape differs")
    end
    if not has_value(lab.inputs, name) then
      fail("base lab does not accept continuation science " .. name)
    end
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local early = data.raw.technology[early_name]
local continuation = data.raw.technology[continuation_name]
if type(early) ~= "table" or early.max_level ~= 3 then
  fail("finite legacy Tin technology differs")
end
if type(continuation) ~= "table" or continuation.level ~= 4 or continuation.max_level ~= "infinite" then
  fail("level-four Tin continuation differs")
end
if not has_value(continuation.prerequisites, early_name) then
  fail("level-four Tin continuation does not require the finite legacy technology")
end
effect_change(early)
effect_change(continuation)
local science = science_names(continuation)
log("[mir-f210-current-bob-tin-level4] DATA PASS"
  .. " early=" .. early_name .. ":1:3"
  .. " continuation=" .. continuation_name .. ":4:infinite"
  .. " prerequisite=true"
  .. " science=" .. table.concat(science, ",")
  .. " lab-compatible=true")
