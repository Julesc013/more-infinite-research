-- Actual catalogue, qualifier and common emitter; independent expected output.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
data = {raw = {item = {}, recipe = {}, technology = {}, tool = {}, lab = {}}}
function data:extend(rows)
  for _, row in ipairs(rows) do
    self.raw[row.type] = self.raw[row.type] or {}
    self.raw[row.type][row.name] = row
  end
end
mods = {base = "2.0.77", ["more-infinite-research"] = "4.4.20000"}
settings = {startup = {}}
feature_flags = {}
log = function() end
for _, name in ipairs({"pack_production_reachability", "recipe_route_feasibility",
  "production_route_policy", "technology_researchability"}) do
  package.preload["prototypes.mir.capabilities.science_integration." .. name] = function()
    error("Retired production solver loaded: " .. name)
  end
end
local roles = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
data.raw.lab.lab = {type = "lab", name = "lab", inputs = roles}
data.raw.item.lab = {type = "item", name = "lab", place_result = "lab"}
data.raw.recipe.lab = {type = "recipe", name = "lab", enabled = true,
  results = {{type = "item", name = "lab", amount = 1}}}
data.raw.item["iron-plate"] = {type = "item", name = "iron-plate",
  icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64}
data.raw.item["iron-ore"] = {type = "item", name = "iron-ore"}
data.raw.recipe["iron-plate"] = {type = "recipe", name = "iron-plate", category = "smelting", enabled = true,
  ingredients = {{"iron-ore", 1}}, results = {{type = "item", name = "iron-plate", amount = 1}}}
for i, name in ipairs(roles) do
  data.raw.tool[name] = {type = "tool", name = name}
  data.raw.recipe[name] = {type = "recipe", name = name, enabled = false,
    ingredients = {{"iron-plate", 1}}, results = {{type = "item", name = name, amount = 1}}}
  data.raw.technology[name] = {type = "technology", name = name, prerequisites = {},
    effects = {{type = "unlock-recipe", recipe = name}},
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1}}
  if i > 1 then
    data.raw.technology[name].research_trigger = nil
    data.raw.technology[name].prerequisites = {roles[i - 1]}
    data.raw.technology[name].unit = {count = 10, time = 10, ingredients = {{roles[i - 1], 1}}}
  end
end
local Context = require("prototypes.mir.pipeline.compiler_context")
local compiler = require("prototypes.mir.pipeline.compiler_orchestrator")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local name = "recipe-prod-research_iron-1"
local expected = {
  name = name, max_level = "infinite", time = 60, count_formula = "8000*2^(L-1)",
  ingredients = {"automation-science-pack:1", "chemical-science-pack:1", "logistic-science-pack:1", "production-science-pack:1"},
  prerequisites = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack", "production-science-pack"},
  effects = {{type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1}}
}
local function assert_preserved()
  local actual = data.raw.technology[name]
  assert(actual, "Established non-core technology is missing")
  local ingredients, prerequisites = {}, deepcopy(actual.prerequisites or {})
  for _, row in ipairs(actual.unit.ingredients) do
    ingredients[#ingredients + 1] = (row.name or row[1]) .. ":" .. tostring(row.amount or row[2])
  end
  table.sort(ingredients)
  table.sort(prerequisites)
  local projection = {name = actual.name, max_level = actual.max_level, time = actual.unit.time,
    count_formula = actual.unit.count_formula, ingredients = ingredients,
    prerequisites = prerequisites, effects = actual.effects}
  assert(fingerprint.of(projection) == fingerprint.of(expected), "Established iron definition changed")
end
local counts
Context.with_active(Context.new(), function()
  local context = Context.current()
  local plan = compiler.compile(context)
  local iron
  for _, row in ipairs(plan.stream_plan.rows) do
    if row.stream_key == "research_iron" then iron = row end
  end
  check(iron and iron.action == "emit", "Existing authored iron family must be admitted")
  check(#plan.stream_plan.rows > 100, "Use the actual catalogue, not a replacement five-family catalogue")
  compiler.apply_streams(context)
  compiler.apply_base_extensions(context)
  assert_preserved()
  check(true, "Shared planner and emitter preserve independently specified iron behavior")
  local journal = context:state_view("mutation_journal")
  check(journal and journal.plan_fingerprint == plan.transformation_plan.plan_fingerprint,
    "The actual emission journal is bound to the actual common plan")
  counts = {rows = #plan.stream_plan.rows, operations = #plan.transformation_plan.operations}
end)
local emitted = data.raw.technology[name]
data.raw.technology[name] = nil
check(not pcall(assert_preserved), "The preservation oracle rejects deletion of non-core research")
data.raw.technology[name] = deepcopy(emitted)
data.raw.technology[name].effects[1].change = 0.2
check(not pcall(assert_preserved), "The preservation oracle rejects a changed effect")
data.raw.technology[name] = emitted
assert_preserved()
check(true, "Opposing controls restore their copied test output")
return {assertions = checks, rows = counts.rows, operations = counts.operations}
