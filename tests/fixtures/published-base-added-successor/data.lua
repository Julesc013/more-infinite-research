-- Five fixture-owned aliases are direct copies of public Base recipes.  This
-- fixture never alters an existing recipe, technology, cost, effect, or main.
local aliases = {
  {"low-density-structure", "mir-fixture-added-low-density-structure"},
  {"plastic-bar", "mir-fixture-added-plastic-bar"},
  {"processing-unit", "mir-fixture-added-processing-unit"},
  {"rocket-fuel", "mir-fixture-added-rocket-fuel"},
  {"steel-plate", "mir-fixture-added-steel-plate"},
}

local rows = {}
for _, row in ipairs(aliases) do
  local original = assert(data.raw.recipe[row[1]], "Base recipe is absent: " .. row[1])
  local copy = table.deepcopy(original)
  copy.name = row[2]
  copy.enabled = true
  copy.hidden = false
  rows[#rows + 1] = copy
end
data:extend(rows)
