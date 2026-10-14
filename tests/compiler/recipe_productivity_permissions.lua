-- Source-bound control for explicit productivity permissions.  A permission
-- marked implicit-only may enable an engine-default recipe, but must not
-- replace an upstream declaration of an allowance or cap.
local permissions = MIR_RECIPE_PRODUCTIVITY_PERMISSIONS

local assertions = 0
local function check(value, message)
  assert(value, message)
  assertions = assertions + 1
end

local function count(rows)
  return #(rows or {})
end

local function deepcopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, nested in pairs(value) do out[deepcopy(key)] = deepcopy(nested) end
  return out
end

local function equal(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local mining_permissions = {
  {name = "burner-mining-drill", required_mods = {"base"}, only_if_implicit_productivity = true},
  {name = "electric-mining-drill", required_mods = {"base"}, only_if_implicit_productivity = true},
  {name = "big-mining-drill", required_mods = {"space-age"}, only_if_implicit_productivity = true},
  {name = "se-core-miner-drill", required_mods = {"space-exploration"}, only_if_implicit_productivity = true}
}

local function apply(mods, recipes, entries)
  _G.mods = mods
  _G.data = {raw = {recipe = recipes}}
  _G.MIR_PERMISSION_STREAMS = {
    research_mining_drill = {productivity_permission_recipes = entries or mining_permissions}
  }
  _G.MIR_ENABLED_STREAMS = {research_mining_drill = true}
  return permissions.apply()
end

do
  local recipes = {
    ["burner-mining-drill"] = {},
    ["electric-mining-drill"] = {normal = {}, expensive = {}},
    ["big-mining-drill"] = {},
    ["se-core-miner-drill"] = {}
  }
  local result = apply({base = "2.1.21", ["space-age"] = "2.1.21", ["space-exploration"] = "0.7.61"}, recipes)
  check(count(result.changed) == 4 and result.changed_count == 4,
    "implicit native and Space Exploration drill recipes receive their four exact permissions")
  for name, recipe in pairs(recipes) do
    check(recipe.allow_productivity == true,
      "implicit recipe receives an explicit permission: " .. name)
  end
  check(recipes["electric-mining-drill"].normal.allow_productivity == true
      and recipes["electric-mining-drill"].expensive.allow_productivity == true,
    "implicit legacy variants receive the same explicit permission")
end

do
  local recipes = {
    ["burner-mining-drill"] = {}, ["electric-mining-drill"] = {},
    ["big-mining-drill"] = {}
  }
  local result = apply({base = "2.1.21", ["space-age"] = "2.1.21", ["space-exploration"] = "0.7.61"}, recipes)
  check(count(result.changed) == 3 and recipes["se-core-miner-drill"] == nil,
    "an active Space Exploration declaration without its named recipe is ignored without mutation or a nil recipe access")
end

do
  local recipes = { ["electric-mining-drill"] = {} }
  _G.mods = {base = "2.1.21"}
  _G.data = {raw = {recipe = recipes}}
  _G.MIR_PERMISSION_STREAMS = {
    research_mining_drill = {productivity_permission_recipes = mining_permissions}
  }
  _G.MIR_ENABLED_STREAMS = {research_mining_drill = false}
  local result = permissions.apply()
  check(count(result.changed) == 0 and recipes["electric-mining-drill"].allow_productivity == nil,
    "a disabled mining-drill stream cannot mutate a native recipe permission")
end

for _, subject in ipairs({
  {label = "root denial", recipe = {allow_productivity = false}},
  {label = "normal denial", recipe = {normal = {allow_productivity = false}}},
  {label = "expensive denial", recipe = {expensive = {allow_productivity = false}}},
  {label = "root cap", recipe = {maximum_productivity = 0}},
  {label = "normal cap", recipe = {normal = {maximum_productivity = 0}}},
  {label = "expensive cap", recipe = {expensive = {maximum_productivity = 0}}}
}) do
  local recipe = subject.recipe
  local before = deepcopy(recipe)
  local result = apply({base = "2.1.21", ["space-age"] = "2.1.21", ["space-exploration"] = "0.7.61"}, {
    ["burner-mining-drill"] = {}, ["electric-mining-drill"] = {}, ["big-mining-drill"] = {},
    ["se-core-miner-drill"] = recipe
  })
  check(count(result.changed) == 3 and equal(recipe, before),
    "implicit-only core permission preserves every upstream " .. subject.label .. " field exactly")
end

do
  local legacy = {allow_productivity = false}
  local result = apply({base = "2.1.21"}, {legacy = legacy}, {
    {name = "legacy", required_mods = {"base"}}
  })
  _G.MIR_ENABLED_STREAMS = {research_mining_drill = false}
  local disabled_result = permissions.apply()
  check(count(disabled_result.changed) == 1 and legacy.allow_productivity == true,
    "pre-existing reviewed permissions retain their explicit-override behavior when a different stream setting is disabled")
end

print("MIR-RECIPE-PRODUCTIVITY-PERMISSIONS-PASS " .. assertions)
return {assertions = assertions}
