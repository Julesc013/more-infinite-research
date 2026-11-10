-- Two explicit new recipient routes; neither existed in the pure Base source.
local rows = {}
for _, recipe in ipairs({"plastic-bar", "low-density-structure"}) do
  local original = assert(data.raw.recipe[recipe], "known-Base fixture recipe absent: " .. recipe)
  local copy = table.deepcopy(original)
  copy.name = "mir-known-base-unpaid-" .. recipe
  copy.enabled, copy.hidden = true, false
  copy.allow_productivity = true
  rows[#rows + 1] = copy
end
data:extend(rows)
data:extend({{
  type="technology", name="mir-known-base-plastic-provider",
  icon="__base__/graphics/technology/plastics.png", icon_size=256,
  prerequisites={"plastics"}, max_level="infinite",
  unit={count=1000, time=60, ingredients={{"automation-science-pack",1}}},
  effects={
    {type="change-recipe-productivity", recipe="plastic-bar", change=.1},
    {type="change-recipe-productivity", recipe="mir-known-base-unpaid-plastic-bar", change=.1},
  },
}})
