local checks = 0
local function check(condition, message)
  checks = checks + 1
  assert(condition, message)
end

local Context = require("prototypes.mir.pipeline.compiler_context")
local bindings = require("prototypes.mir.capabilities.science_integration.pack_bindings")
local catalogue = require("prototypes.mir.streams.registry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local roles = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}

local function world(alternatives, reversed)
  local raw = {recipe = {}, technology = {}, tool = {}, item = {
    ["lab-kit"] = {type = "item", name = "lab-kit", place_result = "lab"}
  }, lab = {
    lab = {name = "lab", inputs = deepcopy(roles)}
  }}
  raw.recipe["lab-kit"] = {type = "recipe", name = "lab-kit", enabled = true,
    results = {{type = "item", name = "lab-kit", amount = 1}}}
  for index, name in ipairs(roles) do
    raw.tool[name] = {type = "tool", name = name}
    raw.recipe[name] = {type = "recipe", name = name, enabled = false,
      ingredients = {{"iron-plate", 1}}, results = {{type = "item", name = name, amount = 1}}}
    raw.technology[name] = {type = "technology", name = name,
      effects = {{type = "unlock-recipe", recipe = name}}, prerequisites = {},
      research_trigger = {type = "craft-item", item = "iron-plate", count = 1}}
    if index > 1 then
      raw.technology[name].research_trigger = nil
      raw.technology[name].prerequisites = {roles[index - 1]}
      raw.technology[name].unit = {count = 10, time = 10, ingredients = {{roles[index - 1], 1}}}
    end
  end
  for n = 1, alternatives do
    local i = reversed and (alternatives - n + 1) or n
    local name = "later-automation-alternative-" .. i
    raw.recipe[name] = {type = "recipe", name = name, enabled = false,
      ingredients = {{"late-machine", 1}}, results = {{type = "item", name = roles[1], amount = 1}}}
    raw.technology[name] = {type = "technology", name = name, prerequisites = {roles[4]},
      unit = {count = 1, time = 1, ingredients = {{roles[1], 1}}},
      effects = {{type = "unlock-recipe", recipe = name}}}
  end
  data.raw = raw
  return raw
end

local function bind_all()
  local result = {}
  for _, role in ipairs(roles) do
    local declaration = bindings.declaration_for_role(role, catalogue.shared.science_bindings)
    local value, reason = bindings.bind(role, declaration)
    check(value ~= nil, "Approved ordinary pack must bind: " .. tostring(reason))
    check(value.status == "research" and #value.unlockers == 1 and value.unlockers[1] == role,
      "Published F200 ordinary science gates must remain exact")
    check(value.recipe_name == role and value.acquisition_proof == false,
      "A bound reference must not claim an acquisition proof")
    result[role] = value
  end
  return result
end

for _, size in ipairs({0, 32, 64, 128}) do
  for _, reversed in ipairs({false, true}) do
    world(size, reversed)
    Context.with_active(Context.new(), function()
      local first = bind_all()
      first[roles[1]].unlockers[1] = "caller-mutation"
      local fresh = bindings.bind(roles[1], bindings.declaration_for_role(roles[1], catalogue.shared.science_bindings))
      check(fresh.unlockers[1] == roles[1], "Returned bindings must be copy-isolated")
    end)
  end
end

local function oppose(mutator, expected)
  local raw = world(0, false)
  mutator(raw)
  Context.with_active(Context.new(), function()
    local value, reason = bindings.bind(roles[1], bindings.declaration_for_role(roles[1], catalogue.shared.science_bindings))
    check(value == nil and string.find(reason, expected, 1, true) ~= nil,
      "Rejected binding must identify " .. expected .. "; observed " .. tostring(reason))
  end)
end
oppose(function(raw) raw.recipe[roles[1]] = nil end, "missing-approved-pack-recipe")
oppose(function(raw) raw.recipe[roles[1]].results[1].type = "fluid" end, "output-mismatch")
oppose(function(raw) raw.recipe[roles[1]].results[1].amount = 0 end, "output-mismatch")
oppose(function(raw) raw.recipe[roles[1]].results[1].probability = 0 end, "output-mismatch")
oppose(function(raw) raw.recipe[roles[1]].results[1].shared_probability = {min = 0.4, max = 0.4} end, "output-mismatch")
oppose(function(raw)
  raw.recipe[roles[1]].normal = {enabled = false, results = {{type = "item", name = roles[1], amount = 1}}}
  raw.recipe[roles[1]].expensive = {enabled = false, results = {{type = "item", name = roles[1], amount = 0}}}
end, "output-mismatch")
oppose(function(raw) raw.technology[roles[1]].effects = {} end, "unlock-mismatch")
oppose(function(raw) raw.technology[roles[1]].enabled = false end, "disabled-technology")
oppose(function(raw) raw.technology[roles[1]].prerequisites = {"missing"} end, "missing-prerequisite")
oppose(function(raw) raw.technology[roles[1]].prerequisites = {roles[1]} end, "technology-cycle")
oppose(function(raw) raw.technology[roles[1]].unit = {ingredients = {{roles[1], 1}}} end, "gate-self-lock")
oppose(function(raw) raw.lab.lab.inputs = {} end, "not-a-lab-input")
world(0, false)
Context.with_active(Context.new(), function()
  local declaration = bindings.declaration_for_role(roles[1], catalogue.shared.science_bindings)
  local no_rule, reason = bindings.bind(roles[1], nil)
  check(no_rule == nil and string.find(reason, "missing-approved-pack-declaration", 1, true), "Unknown binding is explicit")
  data.raw.recipe[roles[1]].enabled = true
  local initial = bindings.bind(roles[1], declaration)
  check(initial and initial.initial and #initial.unlockers == 0, "Approved initially enabled source retains no gates")
  initial.unlockers[1] = "changed"
  check(#bindings.bind(roles[1], declaration).unlockers == 0, "Initial output remains isolated")
  declaration.recipe = "caller-mutation"
  check(catalogue.shared.science_bindings[roles[1]].recipe == roles[1], "Copied declaration must not change catalogue")
end)

for _, size in ipairs({32, 64, 128}) do
  world(size, false)
  Context.with_active(Context.new(), function()
    local index = bindings.compile_references(catalogue.shared, {
      {name = "ordinary-lab", inputs = deepcopy(roles), sources = {{initial = true}}},
      {name = "specialist-lab", inputs = {"exclusive-pack"}, sources = {{unlockers = {"exclusive-lab-tech"}}}}
    })
    for _, role in ipairs(roles) do
      local status, gate = bindings.bound_pack_status(index, role)
      check(status == "research" and gate == role, "Declared science graph preserves each ordinary gate")
      check(bindings.bound_technology_reason(index, role) == nil, "Declared research units are validated")
    end
    check(bindings.bound_lab_available(index, "ordinary-lab"), "An ordinary declared lab remains available")
    check(not bindings.bound_lab_available(index, "specialist-lab"), "A missing specialist gate cannot establish its lab")
    check(index.work.factory_acquisition_calls == 0, "No factory acquisition is part of binding")
    check(index.work.dependency_notifications <= index.work.dependency_edges,
      "Each finite dependency edge is notified at most once")
    check(index.work.facts == size + 12, "Each established node and shared lab vector enters the work queue once")
  end)
end

local raw = world(0, false)
raw.tool["exclusive-pack"] = {type = "tool", name = "exclusive-pack"}
raw.recipe["exclusive-pack"] = {type = "recipe", name = "exclusive-pack", enabled = false,
  results = {{type = "item", name = "exclusive-pack", amount = 1}}}
raw.technology["exclusive-lab-tech"] = {type = "technology", name = "exclusive-lab-tech", prerequisites = {},
  effects = {{type = "unlock-recipe", recipe = "exclusive-pack"}},
  unit = {count = 1, ingredients = {{"exclusive-pack", 1}}}}
raw.lab.specialist = {name = "specialist", inputs = {"exclusive-pack"}}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {
    {name = "ordinary-lab", inputs = deepcopy(roles), sources = {{initial = true}}},
    {name = "specialist", inputs = {"exclusive-pack"}, sources = {{unlockers = {"exclusive-lab-tech"}}}}
  })
  check(bindings.bound_pack_status(index, roles[4]) == "research", "Specialist self-bootstrap does not veto ordinary science")
  check(not bindings.bound_lab_available(index, "specialist"), "An unseeded specialist science/lab cycle cannot establish itself")
  local status, reason = bindings.bound_pack_status(index, "exclusive-pack")
  check(status == nil and reason ~= nil, "Unresolved specialist source is explicit, not a fabricated reachable answer")
end)

raw = world(0, false)
raw.technology[roles[1]].research_trigger = nil
raw.technology[roles[1]].unit = {count = 1, ingredients = {{roles[4], 1}}}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {
    {name = "ordinary-lab", inputs = deepcopy(roles), sources = {{initial = true}}}
  })
  check(bindings.bound_pack_status(index, roles[4]) == nil, "A research/science cycle is not seeded by pending visits")
  check(bindings.bound_technology_reason(index, roles[4]) ~= nil, "Unestablished research retains an explicit reason")
end)

-- Exercise the actual production facade and its actual lab-source projection;
-- former solver modules remain poisoned by the host throughout this fixture.
world(128, false)
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  local ingredients = {}
  for _, role in ipairs(roles) do ingredients[#ingredients + 1] = {role, 1} end
  local selected, status = science.best_lab_compatible_ingredients(ingredients, "research_iron", {})
  check(selected and #selected == 4 and status == "full", "Actual science facade preserves the complete default iron science vector")
  check(science.any_lab_accepts_all(roles), "Actual lab binding accepts the whole ordinary vector")
  check(science.technology_is_enabled_and_reachable(roles[4]), "A fully bound ordinary technology remains available")
  check(science.technology_researchability_reason("absent-upstream-technology") == "missing",
    "An absent optional upstream technology is a reference miss, not an unresolved solver query")
  for _, role in ipairs(roles) do
    local gates = science.prereq_techs_for_science_pack(role)
    check(#gates == 1 and gates[1] == role, "Actual facade preserves each published default gate")
  end
  local first_index = Context.current():state_view("approved_research_bindings")
  local first_work = first_index.work.dependency_notifications
  for _ = 1, 100 do science.technology_is_researchable(roles[4]) end
  check(Context.current():state_view("approved_research_bindings") == first_index
    and first_index.work.dependency_notifications == first_work,
    "Repeated family questions reuse the same completed reference graph")
  local snapshot = science.binding_snapshot()
  snapshot.packs[roles[1]].unlockers[1] = "caller-mutation"
  check(science.prereq_techs_for_science_pack(roles[1])[1] == roles[1], "Facade snapshot cannot change the binding authority")
end)
raw = world(0, false)
raw.tool["exclusive-pack"] = {type = "tool", name = "exclusive-pack"}
raw.lab.specialist = {name = "specialist", inputs = {"exclusive-pack"}}
raw.item.specialist = {type = "item", name = "specialist", place_result = "specialist"}
raw.recipe.specialist = {type = "recipe", name = "specialist", enabled = false,
  results = {{type = "item", name = "specialist", amount = 1}}}
raw.recipe["exclusive-pack"] = {type = "recipe", name = "exclusive-pack", enabled = false,
  results = {{type = "item", name = "exclusive-pack", amount = 1}}}
raw.technology["specialist-unlock"] = {type = "technology", name = "specialist-unlock", enabled = true,
  prerequisites = {}, unit = {count = 1, ingredients = {{"exclusive-pack", 1}}},
  effects = {{type = "unlock-recipe", recipe = "specialist"}, {type = "unlock-recipe", recipe = "exclusive-pack"}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not science.technology_is_enabled_and_reachable("specialist-unlock"),
    "Structural validity alone cannot claim an unseeded specialist research/lab binding is reachable")
end)
-- Approved reference snapshots have the same immutable-input lifetime as the
-- other compiler snapshots. A source replacement must stop before retaining
-- stale positive lab/pack answers; early replacements remain supported.
raw = world(0, false)
Context.with_active(Context.new(), function()
  local recipes = require("prototypes.mir.index.recipe_facts")
  local original = deepcopy(raw.recipe)
  recipes.view(roles[1])
  local epoch = recipes.source_epoch()
  local changed = deepcopy(original)
  changed[roles[1]] = nil
  check(recipes.replace_source(changed, epoch) == epoch + 1,
    "A recipe source replacement is allowed before approved bindings exist")
  local value, reason = bindings.bind(roles[1], bindings.declaration_for_role(roles[1], catalogue.shared.science_bindings))
  check(value == nil and string.find(reason, "missing-approved-pack-recipe", 1, true),
    "An early source replacement is consumed by new approved bindings")
end)
for _, warm in ipairs({"lab", "research"}) do
  raw = world(0, false)
  Context.with_active(Context.new(), function()
    local recipes = require("prototypes.mir.index.recipe_facts")
    if warm == "lab" then
      require("prototypes.mir.capabilities.science_integration.lab_bindings").snapshot()
    else
      require("prototypes.mir.capabilities.science_integration.science_packs").binding_snapshot()
    end
    local epoch = recipes.source_epoch()
    local ok, message = pcall(recipes.replace_source, {}, epoch)
    check(not ok and string.find(message, "approved_lab_bindings", 1, true),
      "A replacement cannot retain stale completed " .. warm .. " bindings")
    check(recipes.source_epoch() == epoch and recipes.view(roles[1]) ~= nil,
      "A refused replacement leaves source facts and epoch unchanged")
  end)
end
for _, reversed in ipairs({false, true}) do
  raw = world(0, reversed)
  raw.tool["mod-science"] = {type = "tool", name = "mod-science"}
  raw.lab.lab.inputs[#raw.lab.lab.inputs + 1] = "mod-science"
  raw.recipe["make-unfamiliar-science"] = {type = "recipe", name = "make-unfamiliar-science", enabled = false,
    results = {{type = "item", name = "mod-science", amount = 1}}}
  -- A same-named fluid recipe must not enter the item producer cardinality.
  raw.recipe["mod-science"] = {type = "recipe", name = "mod-science", enabled = true,
    results = {{type = "fluid", name = "mod-science", amount = 1}}}
  raw.technology["mod-science-unlock"] = {type = "technology", name = "mod-science-unlock", prerequisites = {roles[4]},
    unit = {count = 10, time = 10, ingredients = {{roles[4], 1}}},
    effects = {{type = "unlock-recipe", recipe = "make-unfamiliar-science"}}}
  Context.with_active(Context.new(), function()
    local science = require("prototypes.mir.capabilities.science_integration.science_packs")
    local status, gate = science.pack_production_status("mod-science")
    check(status == "research" and gate == "mod-science-unlock", "One unfamiliar typed pack producer binds parametrically")
    check(science.production_route_for_pack("mod-science").recipe_name == "make-unfamiliar-science",
      "A fluid name collision cannot replace the unique actual item source")
  end)
end
raw = world(0, false)
raw.tool["mod-science"] = {type = "tool", name = "mod-science"}
raw.lab.lab.inputs[#raw.lab.lab.inputs + 1] = "mod-science"
for _, name in ipairs({"source-b", "source-a"}) do
  raw.recipe[name] = {type = "recipe", name = name, enabled = true,
    results = {{type = "item", name = "mod-science", amount = 1}}}
end
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  local ok, reason = pcall(science.pack_production_status, "mod-science")
  check(not ok and string.find(reason, "ambiguous-approved-pack-source", 1, true),
    "Ambiguous unfamiliar pack sources produce an explicit diagnosis without route discovery")
end)
return checks
