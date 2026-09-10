-- Read-only final-prototype observer. No emission authority.
local function names(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    out[#out + 1] = value.name or value[1]
  end
  table.sort(out)
  return out
end

local function productivity_effects(technology)
  local out = {}
  for _, effect in ipairs((technology and technology.effects) or {}) do
    if effect.type == "change-recipe-productivity" then
      out[#out + 1] = { recipe = effect.recipe, change = effect.change }
    end
  end
  table.sort(out, function(a, b) return a.recipe < b.recipe end)
  return out
end

local function recipe_row(name)
  local recipe = data.raw.recipe[name]
  if not recipe then return { name = name, present = false } end
  local result_values = recipe.results or (recipe.result and {{ name = recipe.result }}) or {}
  return {
    name = name,
    present = true,
    hidden = recipe.hidden == true,
    allow_productivity = recipe.allow_productivity == true,
    ingredients = names(recipe.ingredients),
    results = names(result_values)
  }
end

local native = assert(data.raw.technology["kr-imersite-productivity"], "missing native Imersite owner")
local mir = assert(data.raw.technology["recipe-prod-research_material_imersite-1"], "missing MIR Imersite owner")
local native_effects = productivity_effects(native)
local mir_effects = productivity_effects(mir)
local exact_owners = {}
for technology_name, technology in pairs(data.raw.technology) do
  for _, effect in ipairs(productivity_effects(technology)) do
    if effect.recipe == "kr-imersite-crystal" or effect.recipe == "kr-imersite-powder" then
      exact_owners[#exact_owners + 1] = {
        recipe = effect.recipe,
        technology = technology_name,
        change = effect.change
      }
    end
  end
end
table.sort(exact_owners, function(a, b)
  if a.recipe ~= b.recipe then return a.recipe < b.recipe end
  return a.technology < b.technology
end)
assert(#native_effects == 7, "native Imersite owner effect count differs")
assert(#mir_effects == 1, "MIR Imersite owner effect count differs")
assert(#exact_owners == 2, "Imersite crystal/powder effective owner count differs")
assert(exact_owners[1].recipe == "kr-imersite-crystal" and exact_owners[1].technology == "kr-imersite-productivity" and exact_owners[1].change == 0.1, "native crystal owner differs")
assert(exact_owners[2].recipe == "kr-imersite-powder" and exact_owners[2].technology == "recipe-prod-research_material_imersite-1" and exact_owners[2].change == 0.02, "MIR powder owner differs")

local routes = {}
for name in pairs(data.raw.recipe) do
  if string.find(name, "imersite", 1, true) then routes[#routes + 1] = recipe_row(name) end
end
table.sort(routes, function(a, b) return a.name < b.name end)
assert(#routes == 19, "Imersite route count differs")
local crystal_return = recipe_row("kr-crush-kr-imersite-crystal")
assert(crystal_return.present and crystal_return.hidden and not crystal_return.allow_productivity, "hidden crystal return route differs")

local native_science = names(native.unit and native.unit.ingredients)
local mir_science = names(mir.unit and mir.unit.ingredients)
local compatible_labs = {}
for lab_name, lab in pairs(data.raw.lab) do
  local inputs = {}
  for _, input in ipairs(lab.inputs or {}) do inputs[input] = true end
  local accepts = true
  for _, science in ipairs(mir_science) do
    if not inputs[science] then accepts = false end
  end
  if accepts then compatible_labs[#compatible_labs + 1] = lab_name end
end
table.sort(compatible_labs)
assert(#compatible_labs > 0, "no compatible lab for MIR Imersite science")
log("[MIR4_A05_OWNER] native=kr-imersite-productivity;native_effects=7;native_crystal=0.1;mir=recipe-prod-research_material_imersite-1;mir_effects=1;mir_powder=0.02;exact_owners=2")
for _, owner in ipairs(exact_owners) do
  log("[MIR4_A05_EFFECT_OWNER] recipe=" .. owner.recipe .. ";technology=" .. owner.technology .. ";change=" .. owner.change)
end
log("[MIR4_A05_SCIENCE] native=" .. table.concat(native_science, ",") .. ";mir=" .. table.concat(mir_science, ",") .. ";labs=" .. table.concat(compatible_labs, ","))
for _, route in ipairs(routes) do
  log("[MIR4_A05_ROUTE] name=" .. route.name .. ";hidden=" .. tostring(route.hidden) .. ";allow=" .. tostring(route.allow_productivity) .. ";ingredients=" .. table.concat(route.ingredients, ",") .. ";results=" .. table.concat(route.results, ","))
end