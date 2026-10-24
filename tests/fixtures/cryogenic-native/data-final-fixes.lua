local science = "cryogenic-science-pack"
local native_science = "mir5-cryogenic-native-science"

local function fail(message)
  error("[mir5-cryogenic-native] " .. message)
end

local function name_of(row)
  return type(row) == "table" and (row.name or row[1]) or nil
end

local function amount_of(row)
  return type(row) == "table" and (row.amount or row[2]) or nil
end

local function has_unlock(technology, recipe)
  local matches = 0
  for _, effect in ipairs((technology or {}).effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == recipe then
      matches = matches + 1
    end
  end
  return matches
end

local function product_count(recipe, item)
  local matches = 0
  for _, product in ipairs((recipe or {}).results or {}) do
    if (product.type == nil or product.type == "item") and name_of(product) == item
        and amount_of(product) == 1 then
      matches = matches + 1
    end
  end
  return matches
end

local function prerequisite_count(technology, name)
  local matches = 0
  for _, prerequisite in ipairs((technology or {}).prerequisites or {}) do
    if prerequisite == name then matches = matches + 1 end
  end
  return matches
end

local recipe = data.raw.recipe and data.raw.recipe[science]
if not recipe or recipe.enabled ~= false or recipe.main_product ~= science
    or product_count(recipe, science) ~= 1 then
  fail("native cryogenic recipe changed")
end

local owner = data.raw.technology and data.raw.technology[science]
if not owner or owner.research_trigger ~= nil or prerequisite_count(owner, "cryogenic-plant") ~= 1
    or #(owner.prerequisites or {}) ~= 1 or has_unlock(owner, science) ~= 1
    or #(owner.effects or {}) ~= 1 then
  fail("native cryogenic unlock or prerequisite changed")
end

local unit = owner.unit
local ingredient = unit and unit.ingredients and unit.ingredients[1]
if not unit or unit.count ~= 1 or unit.count_formula ~= nil or unit.time ~= 1
    or type(unit.ingredients) ~= "table" or #unit.ingredients ~= 1
    or name_of(ingredient) ~= native_science or amount_of(ingredient) ~= 1 then
  fail("native cryogenic owner is not the expected positive foreign unit")
end

local retained = 0
for name, technology in pairs(data.raw.technology or {}) do
  if type(name) == "string" and name:find("recipe-prod-", 1, true) == 1
      and technology.enabled ~= false then
    local matches = 0
    for _, ingredient_row in ipairs((technology.unit or {}).ingredients or {}) do
      if name_of(ingredient_row) == science then
        matches = matches + 1
        if amount_of(ingredient_row) ~= 1 then
          fail("cryogenic science quantity changed for " .. name)
        end
      end
    end
    if matches > 1 then fail("duplicate cryogenic science ingredient for " .. name) end
    if matches == 1 then
      if prerequisite_count(technology, science) ~= 1 then
        fail("exact native cryogenic gate was lost for " .. name)
      end
      retained = retained + 1
    end
  end
end

if retained == 0 then fail("no enabled MIR recipe-productivity research retained cryogenic science") end
log("[MIR5_CRYOGENIC_NATIVE] retained=" .. retained)
