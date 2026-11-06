-- The retained native finite7 route continues at MIR8. This is one named
-- alternative, never a search for the next available technology suffix.
local M = {}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR finite research-speed input contains a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function integer(value)
  return positive(value) and value == math.floor(value)
end

function M.use_identity(row)
  row.id, row.level, row.predecessor = "research-speed-8", 8, "research-speed-7"
end

function M.adapt(row, raw, selected_ingredients)
  local technologies = type(raw) == "table" and raw.technology
  local seven = technologies and technologies["research-speed-7"]
  local six = technologies and technologies["research-speed-6"]
  if type(seven) ~= "table" or seven.type ~= "technology" or seven.name ~= "research-speed-7"
      or (seven.max_level ~= nil and seven.max_level ~= 7)
      or (seven.level ~= nil and seven.level ~= 7)
      or type(six) ~= "table" or six.type ~= "technology" or six.name ~= "research-speed-6"
      or (six.max_level ~= nil and six.max_level ~= 6) or type(six.unit) ~= "table" then return false end
  local unit = seven.unit
  if type(unit) ~= "table" or not integer(unit.count) or unit.count_formula ~= nil
      or not positive(unit.time) or type(unit.ingredients) ~= "table"
      or #unit.ingredients == 0 or #unit.ingredients > 32 then return false end
  if not integer(six.unit.count) and not (six.unit.count == nil
      and type(six.unit.count_formula) == "string" and six.unit.count_formula ~= "") then return false end
  local prerequisites, seen, anchored = {}, {}, false
  if type(seven.prerequisites) ~= "table" or #seven.prerequisites > 32 then return false end
  for _, name in ipairs(seven.prerequisites) do
    if type(name) ~= "string" or name == "" or seen[name] or name == "research-speed-7"
        or name == "research-speed-8" then return false end
    prerequisites[#prerequisites + 1], seen[name] = name, true
    if name == "research-speed-6" then anchored = true end
  end
  if not anchored then return false end
  prerequisites[#prerequisites + 1], seen["research-speed-7"] = "research-speed-7", true
  local ingredients = {}
  local ingredient_seen = {}
  for index, ingredient in ipairs(unit.ingredients) do
    if type(ingredient) ~= "table" or type(ingredient[1]) ~= "string" or ingredient[1] == ""
        or not integer(ingredient[2]) then return false end
    ingredients[index] = {ingredient[1], ingredient[2]}
    ingredient_seen[ingredient[1]] = true
  end
  if type(seven.effects) ~= "table" or #seven.effects == 0 or #seven.effects > 32 then return false end
  local speed = false
  for _, effect in ipairs(seven.effects) do
    if type(effect) ~= "table" or type(effect.type) ~= "string" then return false end
    if effect.type == "laboratory-speed" then
      if not positive(effect.modifier) then return false end
      speed = true
    end
  end
  if not speed then return false end

  -- The authored profile already declares the admitted pack set. Preserve
  -- the finite predecessor's vector, then append that set in the old
  -- official order; the normal science pass retains source/lab/policy checks.
  local official = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "utility-science-pack", "space-science-pack"}
  local selected = {}
  for _, ingredient in ipairs(selected_ingredients or {}) do selected[ingredient[1]] = ingredient end
  local function append(ingredient)
    if not ingredient_seen[ingredient[1]] then
      ingredients[#ingredients + 1] = {ingredient[1], ingredient[2]}
      ingredient_seen[ingredient[1]] = true
    end
  end
  for _, name in ipairs(official) do if selected[name] then append(selected[name]) end end
  for _, ingredient in ipairs(selected_ingredients or {}) do append(ingredient) end

  M.use_identity(row)
  row.prerequisites, row.exact_prerequisites = prerequisites, true
  row.ingredients, row.inherited_research_speed_effects = ingredients, copy(seven.effects)
  row.inheritance = {last_count=unit.count,
    -- The old numeric-ratio rule falls back to growth1 for a formula-only6.
    previous_count=integer(six.unit.count) and six.unit.count or unit.count,
    research_time=unit.time}
  row.order = seven.order
  if seven.icons ~= nil then row.icons = copy(seven.icons)
  elseif type(seven.icon) == "string" and seven.icon ~= "" then
    row.icons = {{icon=seven.icon, icon_size=seven.icon_size or 256}}
  end
  -- Inherited and authored Base packs need the same named gates as policy
  -- additions. Unknown packs keep their foreign prerequisite boundary;
  -- ordinary science admission below owns additional pack/source decisions.
  local base_packs = { ["automation-science-pack"]=true, ["logistic-science-pack"]=true,
    ["chemical-science-pack"]=true, ["production-science-pack"]=true,
    ["military-science-pack"]=true, ["utility-science-pack"]=true }
  for _, ingredient in ipairs(ingredients) do
    local name = ingredient[1]
    if base_packs[name] and technologies[name] ~= nil and not seen[name] then
      prerequisites[#prerequisites + 1], seen[name] = name, true
    end
  end
  return true
end

return M
