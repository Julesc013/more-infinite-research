local checks = 0
local function check(condition, message)
  checks = checks + 1
  assert(condition, message)
end

local Context = require("prototypes.mir.pipeline.compiler_context")
local bindings = require("prototypes.mir.capabilities.science_integration.lab_bindings")

local function find(rows, name)
  for _, row in ipairs(rows or {}) do if row.name == name then return row end end
  return nil
end

local function find_source(row, recipe_name)
  for _, source in ipairs((row and row.sources) or {}) do
    if source.recipe_name == recipe_name then return source end
  end
  return nil
end

local function has(values, value)
  for _, actual in ipairs(values or {}) do if actual == value then return true end end
  return false
end

local function world(alternatives, reversed)
  local raw = {lab = {}, item = {}, tool = {}, recipe = {}, technology = {}}
  raw.lab["ordinary-lab"] = {type = "lab", name = "ordinary-lab", inputs = {"automation-science-pack", "chemical-science-pack"}}
  raw.lab["specialist-lab"] = {type = "lab", name = "specialist-lab", inputs = {"special-science-pack"}}
  raw.item["ordinary-lab-kit"] = {type = "item", name = "ordinary-lab-kit", place_result = "ordinary-lab"}
  raw.item["specialist-lab-kit"] = {type = "item", name = "specialist-lab-kit", place_result = "specialist-lab"}
  raw.item["wrong-lab-kit"] = {type = "item", name = "wrong-lab-kit", place_result = "other-lab"}
  raw.recipe["ordinary-lab"] = {type = "recipe", name = "ordinary-lab", enabled = true,
    results = {{type = "item", name = "ordinary-lab-kit", amount = 1}}}
  raw.recipe["specialist-lab"] = {type = "recipe", name = "specialist-lab", enabled = false,
    ingredients = {{type = "item", name = "automation-science-pack", amount = 1}},
    results = {{type = "item", name = "specialist-lab-kit", amount = 1}}}
  raw.technology["specialist-lab-unlock"] = {type = "technology", name = "specialist-lab-unlock", enabled = true,
    unit = {ingredients = {{"special-science-pack", 1}}}, effects = {{type = "unlock-recipe", recipe = "specialist-lab"}}}
  for n = 1, alternatives do
    local index = reversed and (alternatives - n + 1) or n
    raw.recipe["ordinary-lab-alternative-" .. index] = {type = "recipe", name = "ordinary-lab-alternative-" .. index,
      enabled = false, results = {{type = "item", name = "ordinary-lab-kit", amount = 1}}}
    raw.technology["ordinary-lab-alternative-" .. index] = {type = "technology", name = "ordinary-lab-alternative-" .. index,
      enabled = true, effects = {{type = "unlock-recipe", recipe = "ordinary-lab-alternative-" .. index}}}
  end
  data.raw = raw
  return raw
end

for _, size in ipairs({0, 32, 64}) do
  for _, reversed in ipairs({false, true}) do
    world(size, reversed)
    Context.with_active(Context.new(), function()
      local rows = bindings.snapshot()
      local internal = bindings.view()
      check(#rows == 2 and rows[1].name == "ordinary-lab" and rows[2].name == "specialist-lab",
        "Laboratory bindings are sorted by actual prototype name")
      check(internal == bindings.view() and internal ~= rows,
        "Context-owned laboratory bindings have a stable internal view and a distinct public snapshot")
      local ordinary = find(rows, "ordinary-lab")
      local specialist = find(rows, "specialist-lab")
      check(has(ordinary.inputs, "automation-science-pack") and has(ordinary.inputs, "chemical-science-pack"),
        "Binding retains actual laboratory inputs")
      check(not has(specialist.inputs, "automation-science-pack") and has(specialist.inputs, "special-science-pack"),
        "A specialist laboratory keeps its own acceptance vector rather than unioning another laboratory's inputs")
      local initial = find_source(ordinary, "ordinary-lab")
      check(initial and initial.item_name == "ordinary-lab-kit" and initial.initial and #initial.unlockers == 0
          and #initial.ingredient_packs == 0,
        "Enabled placement recipe binds as an initial lab source")
      local gated = find_source(specialist, "specialist-lab")
      check(gated and gated.initial == false and #gated.unlockers == 1 and gated.unlockers[1] == "specialist-lab-unlock"
          and #gated.ingredient_packs == 1 and gated.ingredient_packs[1] == "automation-science-pack",
        "A specialist placement source retains a science dependency accepted by another actual lab for graph-level admission")
      check(#ordinary.sources == size + 1,
        "Later direct placement recipes are represented without route selection")
      rows[1].inputs[1] = "caller-mutation"
      rows[1].sources[1].recipe_name = "caller-mutation"
      local fresh = bindings.snapshot()
      check(fresh[1].inputs[1] ~= "caller-mutation" and fresh[1].sources[1].recipe_name ~= "caller-mutation",
        "Laboratory binding snapshot is copy-isolated")
    end)
  end
end

local function oppose(mutator, expected_sources)
  local raw = world(0, false)
  mutator(raw)
  Context.with_active(Context.new(), function()
    local ordinary = find(bindings.snapshot(), "ordinary-lab")
    check(#ordinary.sources == expected_sources,
      "Invalid direct placement binding is absent from the approved lab projection")
  end)
end

oppose(function(raw) raw.recipe["ordinary-lab"].results[1].type = "fluid" end, 0)
oppose(function(raw) raw.recipe["ordinary-lab"].results[1].amount = 0 end, 0)
oppose(function(raw) raw.item["ordinary-lab-kit"].place_result = "other-lab" end, 0)
oppose(function(raw) raw.recipe["ordinary-lab"].enabled = false; raw.technology["ordinary-lab-unlock"] = {type = "technology", name = "ordinary-lab-unlock", enabled = false, effects = {{type = "unlock-recipe", recipe = "ordinary-lab"}}} end, 0)
oppose(function(raw) raw.recipe["ordinary-lab"].enabled = false end, 0)
oppose(function(raw) raw.recipe["ordinary-lab"].results[1].probability = 0 end, 0)
oppose(function(raw) raw.recipe["ordinary-lab"].results[1].shared_probability = {min = 1, max = 1} end, 0)
oppose(function(raw)
  raw.recipe["ordinary-lab"] = {type = "recipe", name = "ordinary-lab", enabled = true,
    normal = {results = {{type = "item", name = "ordinary-lab-kit", amount = 1}}},
    expensive = {results = {{type = "item", name = "ordinary-lab-kit", amount = 1, probability = 0}}}}
end, 0)

local function admits(mutator, detail)
  local raw = world(0, false)
  mutator(raw)
  Context.with_active(Context.new(), function()
    local ordinary = find(bindings.snapshot(), "ordinary-lab")
    check(#ordinary.sources == 1, detail)
  end)
end

admits(function(raw)
  raw.recipe["ordinary-lab"].results[1] = {type = "item", name = "ordinary-lab-kit", amount = 1, amount_min = 0, amount_max = 0}
end, "Fixed positive amount takes precedence over zero range metadata")
admits(function(raw)
  raw.recipe["ordinary-lab"].results[1] = {type = "item", name = "ordinary-lab-kit", amount_min = 1, amount_max = 0}
end, "Reversed range clamps to its positive minimum")
admits(function(raw)
  raw.recipe["ordinary-lab"].results[1] = {type = "item", name = "ordinary-lab-kit", amount = 0, extra_count_fraction = 0.25}
end, "Positive declared extra result quantity remains a possible direct source")

world(0, false)
data.raw.recipe["specialist-lab"].enabled = true
Context.with_active(Context.new(), function()
  local specialist = find(bindings.snapshot(), "specialist-lab")
  local source = find_source(specialist, "specialist-lab")
  check(source and source.initial == true and #source.ingredient_packs == 1
      and source.ingredient_packs[1] == "automation-science-pack",
    "Enabled specialist placement retains the cross-lab science dependency without changing its accepted inputs")
end)

-- The global physical-input set supplements, rather than replaces, the
-- source lab's own accepted packs.  Preserve the original self-bootstrap
-- shape for the shared graph's independent cycle classification.
world(0, false)
data.raw.recipe["specialist-lab"].ingredients = {{type = "item", name = "special-science-pack", amount = 1}}
Context.with_active(Context.new(), function()
  local specialist = find(bindings.snapshot(), "specialist-lab")
  local source = find_source(specialist, "specialist-lab")
  check(source and #source.ingredient_packs == 1 and source.ingredient_packs[1] == "special-science-pack",
    "A specialist placement source retains its own accepted science dependency for graph-level bootstrap rejection")
end)

return checks
