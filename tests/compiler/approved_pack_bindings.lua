local checks = 0
local function check(condition, message)
  checks = checks + 1
  assert(condition, message)
end

local Context = require("prototypes.mir.pipeline.compiler_context")
local bindings = require("prototypes.mir.capabilities.science_integration.pack_bindings")
local catalogue = require("prototypes.mir.streams.registry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local lab_bindings = require("prototypes.mir.capabilities.science_integration.lab_bindings")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
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

world(0, false)
Context.with_active(Context.new(), function()
  local internal_labs = lab_bindings.view()
  local copied_labs = lab_bindings.snapshot()
  local before = fingerprint.of(internal_labs)
  local copied_index = bindings.compile_references(catalogue.shared, copied_labs)
  local internal_index = science_packs.binding_snapshot()
  check(fingerprint.of(copied_index) == fingerprint.of(internal_index),
    "The Context-owned laboratory view produces the same approved reference bindings as the copied public snapshot")
  check(fingerprint.of(lab_bindings.view()) == before,
    "Approved reference construction never mutates Context-owned laboratory bindings")
  local input_before = internal_index.labs[1].inputs[1]
  local recipe_before = internal_index.labs[1].sources[1].recipe_name
  internal_index.labs[1].inputs[1] = "caller-mutation"
  internal_index.labs[1].sources[1].recipe_name = "caller-mutation"
  local fresh_index = science_packs.binding_snapshot()
  check(fresh_index.labs[1].inputs[1] == input_before
      and fresh_index.labs[1].sources[1].recipe_name == recipe_before,
    "Public approved-reference snapshots cannot mutate the shared laboratory view")
  local exposed_index = Context.current():service("science.approved_binding_index")()
  exposed_index.labs[1].inputs[1] = "caller-mutation"
  exposed_index.labs[1].sources[1].recipe_name = "caller-mutation"
  local lab_snapshot = lab_bindings.snapshot()
  check(lab_snapshot[1].inputs[1] == input_before and lab_snapshot[1].sources[1].recipe_name == recipe_before,
    "The exposed approved-binding service cannot mutate the shared laboratory view")
  local service_snapshot = science_packs.binding_snapshot()
  check(service_snapshot.labs[1].inputs[1] == input_before
      and service_snapshot.labs[1].sources[1].recipe_name == recipe_before,
    "The exposed approved-binding service cannot mutate later public binding snapshots")
end)

local first_context, second_context = Context.new(), Context.new()
world(0, false)
local first_labs
Context.with_active(first_context, function()
  first_labs = lab_bindings.view()
  science_packs.binding_snapshot()
end)
world(0, false)
data.raw.lab.lab.inputs = {roles[1]}
local second_labs
Context.with_active(second_context, function()
  second_labs = lab_bindings.view()
  science_packs.binding_snapshot()
  check(second_labs ~= first_labs and #second_labs[1].inputs == 1,
    "A fresh CompilerContext builds its own laboratory bindings from its active prototype world")
end)
check(#first_labs[1].inputs == #roles,
  "A later Context cannot replace the earlier Context-owned laboratory binding view")

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
    check(index.work.native_source_prototype_visits == 0,
      "Resolved ordinary sources do not trigger whole-prototype native-source inspection")
    check(index.work.dependency_notifications <= index.work.dependency_edges,
      "Each finite dependency edge is notified at most once")
    check(index.work.unknown_dependency_notifications <= index.work.dependency_edges,
      "Unknown influence also traverses each finite edge at most once")
    check(index.work.facts == size + 12, "Each established node and shared lab vector enters the work queue once")
  end)
end

-- Unknown lab placement sources must not become an unavailable result that
-- silently suppresses research or justifies a reduced science vector.
for _, operation in ipairs({"any", "best"}) do
  local missing_source = world(0, false)
  missing_source.recipe["lab-kit"] = nil
  for _, role in ipairs(roles) do missing_source.recipe[role].enabled = true end
  Context.with_active(Context.new(), function()
    local science = require("prototypes.mir.capabilities.science_integration.science_packs")
    local ok, reason = pcall(function()
      if operation == "any" then return science.any_lab_accepts_all(roles) end
      local ingredients = {}
      for _, role in ipairs(roles) do ingredients[#ingredients + 1] = {role, 1} end
      return science.best_lab_compatible_ingredients(ingredients, "unknown-lab-source", {})
    end)
    check(not ok and string.find(reason, "approved laboratory binding is unresolved", 1, true),
      "An unresolved lab source must remain explicit in the " .. operation .. " path")
  end)
end
do
  local with_specialist = world(0, false)
  with_specialist.lab["unresolved-specialist"] = {name = "unresolved-specialist", inputs = deepcopy(roles)}
  Context.with_active(Context.new(), function()
    local science = require("prototypes.mir.capabilities.science_integration.science_packs")
    check(science.any_lab_accepts_all(roles), "An unresolved alternative cannot veto a valid complete lab vector")
  end)
end
do
  local reduction = world(0, false)
  reduction.lab.lab.inputs = {roles[1], roles[2]}
  reduction.lab["unresolved-specialist"] = {name = "unresolved-specialist", inputs = deepcopy(roles)}
  for _, role in ipairs(roles) do reduction.recipe[role].enabled = true end
  Context.with_active(Context.new(), function()
    local science = require("prototypes.mir.capabilities.science_integration.science_packs")
    local ingredients = {}
    for _, role in ipairs(roles) do ingredients[#ingredients + 1] = {role, 1} end
    local ok, reason = pcall(science.best_lab_compatible_ingredients, ingredients, "unknown-full-lab", {})
    check(not ok and string.find(reason, "approved laboratory binding is unresolved", 1, true),
      "An unresolved full-vector lab cannot justify silently reducing required research science")
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
  check(status == "not-admitted" and index.packs["exclusive-pack"].reference_policy_exclusion == true,
    "A completed closed specialist cycle is excluded by reference policy, not a fabricated acquisition proof")
end)

raw = world(0, false)
raw.technology[roles[1]].research_trigger = nil
raw.technology[roles[1]].unit = {count = 1, ingredients = {{roles[4], 1}}}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {
    {name = "ordinary-lab", inputs = deepcopy(roles), sources = {{initial = true}}}
  })
  check(bindings.bound_pack_status(index, roles[4]) == "not-admitted"
    and index.work.closed_reference_pack_exclusions == 4,
    "Completion of a closed research/science cycle proves no approved reference seed")
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
local function launch_world()
  local value = world(0, false)
  value.tool["space-science-pack"] = {type = "tool", name = "space-science-pack"}
  value.lab.lab.inputs[#value.lab.lab.inputs + 1] = "space-science-pack"
  value.item.satellite = {type = "item", name = "satellite", send_to_orbit_mode = "automated",
    rocket_launch_products = {{type = "item", name = "space-science-pack", amount = 1000}}}
  value["rocket-silo-rocket"] = {rocket = {name = "rocket", inventory_size = 0}}
  value["rocket-silo"] = {silo = {name = "silo", rocket_entity = "rocket", fixed_recipe = "rocket-part",
    to_be_inserted_to_rocket_inventory_size = 1, crafting_speed = 1, rocket_parts_required = 100}}
  value["cargo-landing-pad"] = {pad = {name = "pad", inventory_size = 100}}
  value.technology["white-research"] = {type = "technology", name = "white-research", prerequisites = {},
    unit = {count = 1, ingredients = {{"space-science-pack", 1}}}}
  value.technology["white-descendant"] = {type = "technology", name = "white-descendant", prerequisites = {"white-research"},
    unit = {count = 1, ingredients = {{roles[1], 1}}}}
  return value
end
raw = launch_world()
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(science.pack_production_status("space-science-pack") == "unreachable",
    "The published launch inventory policy is retained without inventing an acquisition proof")
  local source = science.production_route_for_pack("space-science-pack")
  check(source.status == "not-admitted" and source.acquisition_proof == false and source.source_kind == "retained-published-native-launch-policy"
    and source.policy_reason ~= nil, "The retained exclusion is explicit source policy, not factory impossibility")
  local reason = science.technology_researchability_reason("white-descendant")
  check(string.find(reason, "science-excluded-by-published-policy:", 1, true) == 1,
    "A known policy exclusion propagates through mandatory prerequisites without becoming an unresolved proof")
  local requested = {}
  for _, role in ipairs(roles) do requested[#requested + 1] = {role, 1} end
  requested[#requested + 1] = {"space-science-pack", 1}
  local selected = science.best_lab_compatible_ingredients(requested, "published-policy-control", {})
  check(selected and #selected == 4, "Retained launch policy leaves the published ordinary four-pack vector unchanged")
  check(science.best_lab_compatible_ingredients(requested, "required-policy-control", {"space-science-pack"}) == nil,
    "A required pack cannot be silently removed to make a family pass")
end)
raw = launch_world()
raw["rocket-silo-rocket"].rocket.inventory_size = 1
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "An unapproved positive launch case remains explicit and cannot be replaced by a negative policy answer")
end)
raw = launch_world()
raw.resource = {ore = {name = "ore", minable = {result = "space-science-pack"}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "A new native producer cannot inherit a launch-only exclusion")
end)
raw = launch_world()
raw.recipe["space-science-pack"] = {type = "recipe", name = "space-science-pack", enabled = true,
  results = {{type = "item", name = "space-science-pack", amount = 1}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(science.pack_production_status("space-science-pack") == "initial",
    "An actual approved direct recipe takes precedence over retained launch policy")
end)
local function self_cycle_world()
  local cycle = world(0, false)
  cycle.tool["closed-cycle-pack"] = {type = "tool", name = "closed-cycle-pack"}
  cycle.lab.lab.inputs[#cycle.lab.lab.inputs + 1] = "closed-cycle-pack"
  cycle.recipe["closed-cycle-pack"] = {type = "recipe", name = "closed-cycle-pack", enabled = false,
    results = {{type = "item", name = "closed-cycle-pack", amount = 1}}}
  cycle.technology["closed-cycle-unlocker"] = {type = "technology", name = "closed-cycle-unlocker",
    prerequisites = {}, unit = {count = 1, ingredients = {{"closed-cycle-pack", 1}}},
    effects = {{type = "unlock-recipe", recipe = "closed-cycle-pack"}}}
  return cycle
end
self_cycle_world()
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(science.pack_production_status("closed-cycle-pack") == "unreachable",
    "A completed closed cycle retains the published caller enum")
  local source = science.production_route_for_pack("closed-cycle-pack")
  check(source.status == "not-admitted" and source.policy_reason == "unseeded-approved-reference-dependencies"
    and source.reference_policy_exclusion == true and source.acquisition_proof == false,
    "The detailed cycle exclusion identifies its finite reference policy, never factory impossibility")
  local ingredients = {}
  for _, role in ipairs(roles) do ingredients[#ingredients + 1] = {role, 1} end
  ingredients[#ingredients + 1] = {"closed-cycle-pack", 1}
  local selected = science.best_lab_compatible_ingredients(ingredients, "closed-reference-control", {})
  check(selected and #selected == 4, "A closed bad science cycle does not remove the ordinary research vector")
end)
raw = self_cycle_world()
raw.tool["unknown-external-pack"] = {type = "tool", name = "unknown-external-pack"}
raw.lab.lab.inputs[#raw.lab.lab.inputs + 1] = "unknown-external-pack"
raw.technology["closed-cycle-unlocker"].unit.ingredients[#raw.technology["closed-cycle-unlocker"].unit.ingredients + 1]
  = {"unknown-external-pack", 1}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  local ok, reason = pcall(science.pack_production_status, "closed-cycle-pack")
  check(not ok and string.find(reason, "binding is unresolved", 1, true),
    "An external unknown dependency prevents a closed-cycle negative conclusion")
  check(not pcall(science.technology_is_enabled_and_reachable, "closed-cycle-unlocker"),
    "The Boolean technology facade must not turn unknown reference dependencies into false")
  check(science.pack_production_status(roles[4]) == "research", "An unrelated unknown cannot veto ordinary science")
end)
raw = self_cycle_world()
raw.recipe["unapproved-alternative"] = {type = "recipe", name = "unapproved-alternative", enabled = false,
  results = {{type = "item", name = "closed-cycle-pack", amount = 1}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "closed-cycle-pack"),
    "An unexamined alternative cannot be silently disproved by a failed approved cycle")
end)
raw.recipe["approved-independent-source"] = {type = "recipe", name = "approved-independent-source", enabled = true,
  results = {{type = "item", name = "closed-cycle-pack", amount = 1}}}
Context.with_active(Context.new(), function()
  local shared = deepcopy(catalogue.shared)
  shared.science_bindings["closed-cycle-pack"] = {recipe = "approved-independent-source", allow_initial = true}
  local index = bindings.compile_references(shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(bindings.bound_pack_status(index, "closed-cycle-pack") == "initial",
    "A proven approved seed wins over unknown or cyclic alternatives")
end)
raw = self_cycle_world()
raw.resource = {seed = {name = "seed", minable = {result = "closed-cycle-pack"}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "closed-cycle-pack"),
    "A possible native seed prevents a recipe-only closed-cycle negative conclusion")
end)
return checks
