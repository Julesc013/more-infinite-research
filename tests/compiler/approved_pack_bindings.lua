local checks = 0
local function check(condition, message)
  checks = checks + 1
  assert(condition, message)
end

local Context = require("prototypes.mir.pipeline.compiler_context")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
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

-- Accepted input sets and canonical order are private Context state.  Repeated
-- Boolean/reduction queries must reuse them, while a new Context sees the
-- current data-stage records.  The aliased raw row remains a separate named
-- candidate, matching the former raw-table traversal rather than collapsing it.
do
  local raw = world(0, false)
  raw.lab["lab-alias"] = raw.lab.lab
  local owner = Context.new()
  owner:set_service("science.pack_production_status", function() return "research" end)
  owner:set_service("science.lab_binding_available", function() return true end)
  owner:freeze_services()
  Context.with_active(owner, function()
    for _ = 1, 8 do
      check(lab_compatibility.valid_research_ingredients({{roles[1], 1}, {roles[2], 1}}),
        "Repeated declared lab checks retain the former Boolean result")
    end
    local first_view = owner:state_view("approved_lab_acceptance_view")
    check(first_view == owner:state_view("approved_lab_acceptance_view") and #first_view == 2
        and first_view[1].name == "lab" and first_view[2].name == "lab-alias"
        and first_view[1].accepted_inputs[roles[1]] and first_view[2].accepted_inputs[roles[2]],
      "Accepted input sets and canonical lab order are prepared once without collapsing aliases")
  end)
  raw.lab["lab-alias"] = nil
  raw.lab.lab.inputs = {roles[1]}
  local fresh = Context.new()
  fresh:set_service("science.pack_production_status", function() return "research" end)
  fresh:set_service("science.lab_binding_available", function() return true end)
  fresh:freeze_services()
  Context.with_active(fresh, function()
    check(not lab_compatibility.valid_research_ingredients({{roles[1], 1}, {roles[2], 1}}),
      "A fresh Context rebuilds accepted inputs after a data-stage input change")
  end)
end

do
  local raw = world(0, false)
  raw.lab = {}
  local owner = Context.new()
  owner:set_service("science.pack_production_status", function() return "research" end)
  owner:set_service("science.lab_binding_available", function() return true end)
  owner:freeze_services()
  Context.with_active(owner, function()
    check(not lab_compatibility.valid_research_ingredients({{roles[1], 1}}),
      "An empty physical laboratory set remains a known negative")
    local selected, status = lab_compatibility.best_lab_compatible_ingredients({{roles[1], 1}}, "zero-labs", {})
    check(selected == nil and status == "invalid", "An empty lab set cannot justify a reduced science vector")
  end)
end

do
  local raw = world(0, false)
  raw.lab = {
    zeta = {name = "zeta", inputs = {roles[1], roles[2]}},
    alpha = {name = "alpha", inputs = {roles[1]}}
  }
  local owner = Context.new()
  owner:set_service("science.pack_production_status", function() return "research" end)
  owner:set_service("science.lab_binding_available", function() return true end)
  owner:freeze_services()
  Context.with_active(owner, function()
    for _ = 1, 8 do
      local chosen, status = lab_compatibility.best_lab_compatible_ingredients(
        {{roles[1], 1}, {roles[2], 1}, {"excluded-pack", 1}}, "canonical-reduction", {})
      check(chosen and status == "reduced" and #chosen == 2
          and chosen[1][1] == roles[1] and chosen[2][1] == roles[2],
        "Repeated reduction preserves the best accepted science vector")
    end
    local view = owner:state_view("approved_lab_acceptance_view")
    check(#view == 2 and view[1].name == "alpha" and view[2].name == "zeta",
      "Reduction consumes the one canonical Context-owned lab order")
  end)
end

-- A declared external science input may have other raw producers.  The
-- approved source stays the named recipe and direct unlock owner; alternatives
-- neither choose a route by traversal order nor veto the proven declaration.
do
  local raw = world(0, false)
  local token = "angels-token-bio"
  local source = "angels-temperate-garden-a"
  local alternative = "unapproved-garden-token-producer"
  local unlocker = "angels-gardens"
  local dependent = "token-dependent-prerequisite"
  raw.tool[token] = {type = "tool", name = token}
  raw.lab.lab.inputs[#raw.lab.lab.inputs + 1] = token
  raw.recipe[source] = {type = "recipe", name = source, enabled = false,
    ingredients = {{"iron-plate", 1}}, results = {{type = "item", name = token, amount = 1}}}
  raw.recipe[alternative] = {type = "recipe", name = alternative, enabled = false,
    ingredients = {{"iron-plate", 1}}, results = {{type = "item", name = token, amount = 1}}}
  raw.technology[unlocker] = {type = "technology", name = unlocker, prerequisites = {roles[2]},
    unit = {count = 1, ingredients = {{roles[1], 1}, {roles[2], 1}}},
    effects = {{type = "unlock-recipe", recipe = source}}}
  raw.technology[dependent] = {type = "technology", name = dependent, prerequisites = {unlocker},
    unit = {count = 1, ingredients = {{roles[1], 1}, {roles[2], 1}, {token, 1}}}}
  raw.technology[roles[4]].prerequisites[#raw.technology[roles[4]].prerequisites + 1] = dependent
  local without_declaration = deepcopy(catalogue.shared)
  without_declaration.science_bindings[token] = nil
  Context.with_active(Context.new(), function()
    local index = bindings.compile_references(without_declaration,
      {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
    check(index.packs[token] == nil
        and string.find(index.issues[token], "ambiguous-approved-pack-source", 1, true),
      "Removing the authored Angel token declaration reproduces the ambiguous-source refusal")
  end)
  Context.with_active(Context.new(), function()
    local index = bindings.compile_references(catalogue.shared,
      {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
    local status, gate = bindings.bound_pack_status(index, token)
    check(status == "research" and gate == unlocker and index.packs[token].recipe_name == source,
      "An approved named token source remains bound despite an unapproved alternative producer")
    check(bindings.bound_technology_reason(index, roles[4]) == nil
        and bindings.bound_pack_status(index, roles[4]) == "research",
      "A declared token seed resolves its dependent established science chain")
  end)
  local wrong_owner = deepcopy(catalogue.shared)
  wrong_owner.science_bindings[token].technology = roles[1]
  Context.with_active(Context.new(), function()
    local index = bindings.compile_references(wrong_owner,
      {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
    check(index.packs[token] == nil
        and string.find(index.issues[token], "ambiguous-approved-pack-source", 1, true),
      "A named token source with a wrong owner cannot fall through to choose an ambiguous producer")
  end)
end

-- Diagnostic limits still count duplicate physical inputs and stop before a
-- lab binding is consulted. Normal research admission has no such work budget.
do
  local raw = world(0, false)
  raw.lab = {ordinary = {name = "ordinary", inputs = {roles[1], roles[2], roles[1]}}}
  local owner, binding_queries = Context.new(), 0
  owner:set_service("science.lab_binding_available", function()
    binding_queries = binding_queries + 1
    return true
  end)
  owner:freeze_services()
  Context.with_active(owner, function()
    for _, limit in ipairs({6, 7}) do
      local visits, before = 0, binding_queries
      local observer = {reserve_visit = function()
        visits = visits + 1
        return visits <= limit
      end}
      local accepted = lab_compatibility.any_lab_accepts_all({roles[1], roles[2]}, observer)
      check(accepted == (limit == 7) and visits == 7,
        "Diagnostic lab work retains its exact boundary including duplicate inputs")
      check(binding_queries - before == (limit == 7 and 1 or 0),
        "An exhausted diagnostic cannot consult the lab binding beyond its budget")
    end
    local before = binding_queries
    local accepted = lab_compatibility.any_lab_accepts_all({roles[1]}, {
      is_stopped = function() return true end,
      reserve_visit = function() error("A stopped diagnostic must not reserve more work") end
    })
    check(not accepted and binding_queries == before,
      "An already stopped diagnostic does not query a lab or reserve more work")
    check(lab_compatibility.any_lab_accepts_all({roles[1], roles[2]}),
      "Ordinary admission remains independent of private diagnostic exhaustion")
  end)
end

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
-- Factorio 0.15 stores its satellite-qualified space-science result on the
-- rocket entity, rather than on the satellite item. It is a retained policy
-- exclusion only: exact output and payload tuple are required, while all
-- unrecognized or potentially positive shapes stay unresolved.
local function legacy_015_launch_world(result)
  local value = world(0, false)
  value.tool["space-science-pack"] = {type = "tool", name = "space-science-pack"}
  value.lab.lab.inputs[#value.lab.lab.inputs + 1] = "space-science-pack"
  value.item.satellite = {type = "item", name = "satellite"}
  value["rocket-silo-rocket"] = {legacy_rocket = {name = "legacy-rocket", result_items = result and {result} or {}}}
  value.technology["bullet-damage-6"] = {type = "technology", name = "bullet-damage-6", prerequisites = {},
    unit = {count = 1, ingredients = {{roles[4], 1}}}}
  value.technology["bullet-damage-7"] = {type = "technology", name = "bullet-damage-7",
    prerequisites = {"bullet-damage-6"}, max_level = "infinite", effects = {{type = "ammo-damage", ammo_category = "bullet", modifier = 0.4}},
    unit = {count = 1000, ingredients = {{roles[1], 1}, {roles[2], 1}, {roles[3], 1}, {roles[4], 1}, {"space-science-pack", 1}}}}
  return value
end
local target_profiles = package.loaded["prototypes.mir.platform.factorio.target_profiles"]
target_profiles.current_factorio_version = "0.15"
raw = legacy_015_launch_world({"space-science-pack", 1000, "satellite"})
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(science.pack_production_status("space-science-pack") == "unreachable",
    "The exact F015 rocket result shape remains a retained negative policy, not an acquisition route")
  local source = science.production_route_for_pack("space-science-pack")
  check(source.status == "not-admitted" and source.acquisition_proof == false
      and source.source_kind == "retained-published-native-launch-policy"
      and source.policy_reason == "published-native-launch-contract-not-supported-on-target",
    "The F015 result-item policy keeps the existing detailed negative record")
  check(science.technology_researchability_reason("bullet-damage-7") == "science-excluded-by-published-policy:space-science-pack",
    "A real F015-shaped late technology receives the retained exclusion rather than an unresolved binding")
end)
raw = legacy_015_launch_world(nil)
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "A missing F015 rocket result cannot inherit the retained policy")
end)
raw = legacy_015_launch_world({"space-science-pack", 1000, "wrong-payload"})
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "A wrong F015 launch payload cannot inherit the retained policy")
end)
raw = legacy_015_launch_world({"space-science-pack", 0, "satellite"})
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "A zero-result F015 launch tuple cannot inherit the retained policy")
end)
raw = legacy_015_launch_world({"space-science-pack", 1000, "satellite"})
raw.item.satellite = nil
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "An F015 result tuple without its actual payload item cannot inherit the retained policy")
end)
target_profiles.current_factorio_version = "0.16"
raw = legacy_015_launch_world({"space-science-pack", 1000, "satellite"})
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "Legacy rocket result tuples cannot become a policy adapter for a different target line")
end)
target_profiles.current_factorio_version = "0.15"
raw = legacy_015_launch_world({"space-science-pack", 1000, "satellite"})
raw.resource = {ore = {name = "ore", minable = {result = "space-science-pack"}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(not pcall(science.pack_production_status, "space-science-pack"),
    "A non-launch native producer prevents the F015 policy answer")
end)
raw = legacy_015_launch_world({"space-science-pack", 1000, "satellite"})
raw.recipe["space-science-pack"] = {type = "recipe", name = "space-science-pack", enabled = true,
  results = {{type = "item", name = "space-science-pack", amount = 1}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(science.pack_production_status("space-science-pack") == "initial",
    "An actual direct recipe retains precedence over the F015 negative policy")
end)

-- F015 keeps a small, explicit progression frontier for the three actual
-- late science recipes. It is independent of their direct unlockers and
-- applies only after every declared recipe shape still matches the engine.
local function f015_progression_world()
  local value = world(0, false)
  -- The ordinary fixture creates a modern same-named production unlock. The
  -- F015 source instead owns the native advanced-material-processing-2 gate.
  value.technology["production-science-pack"] = nil
  value.item["assembling-machine-1"] = {type = "item", name = "assembling-machine-1"}
  value.item["assembling-machine-2"] = {type = "item", name = "assembling-machine-2"}
  value["assembling-machine"] = {
    ["assembling-machine-1"] = {type = "assembling-machine", name = "assembling-machine-1",
      minable = {result = "assembling-machine-1"}, crafting_categories = {"crafting"}, ingredient_count = 2},
    ["assembling-machine-2"] = {type = "assembling-machine", name = "assembling-machine-2",
      minable = {result = "assembling-machine-2"}, crafting_categories = {"crafting"}, ingredient_count = 4}
  }
  value.recipe["assembling-machine-1"] = {type = "recipe", name = "assembling-machine-1", enabled = false,
    results = {{type = "item", name = "assembling-machine-1", amount = 1}}}
  value.recipe["assembling-machine-2"] = {type = "recipe", name = "assembling-machine-2", enabled = false,
    results = {{type = "item", name = "assembling-machine-2", amount = 1}}}
  value.technology.automation = {type = "technology", name = "automation",
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
    effects = {{type = "unlock-recipe", recipe = "assembling-machine-1"}}}
  local sources = {
    ["high-tech-science-pack"] = {
      unlocker = "advanced-electronics-2",
      ingredients = {{"battery", 1}, {"processing-unit", 1}, {"speed-module", 1}, {"copper-cable", 1}}
    },
    ["production-science-pack"] = {
      unlocker = "advanced-material-processing-2",
      ingredients = {{"electric-engine-unit", 1}, {"assembling-machine-1", 1}, {"electric-furnace", 1}}
    },
    ["military-science-pack"] = {
      unlocker = "military-2",
      ingredients = {{"piercing-rounds-magazine", 1}, {"grenade", 1}, {"gun-turret", 1}}
    }
  }
  for pack, source in pairs(sources) do
    value.tool[pack] = {type = "tool", name = pack}
    value.lab.lab.inputs[#value.lab.lab.inputs + 1] = pack
    value.recipe[pack] = {type = "recipe", name = pack, enabled = false,
      ingredients = deepcopy(source.ingredients), results = {{type = "item", name = pack, amount = 1}}}
    value.technology[source.unlocker] = {type = "technology", name = source.unlocker,
      research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
      effects = {{type = "unlock-recipe", recipe = pack}}}
  end
  for _, name in ipairs({"automation-2", "battery", "speed-module", "electric-engine", "engine", "turrets"}) do
    value.technology[name] = {type = "technology", name = name,
      research_trigger = {type = "craft-item", item = "iron-plate", count = 1}}
  end
  value.technology["automation-2"].effects = {{type = "unlock-recipe", recipe = "assembling-machine-2"}}
  return value
end

local function equal_names(actual, expected)
  if #actual ~= #expected then return false end
  for index, name in ipairs(expected) do if actual[index] ~= name then return false end end
  return true
end

local function f015_vector_gates(science, packs)
  local gates, seen = {}, {}
  for _, pack in ipairs(packs) do
    for _, gate in ipairs(science.prereq_techs_for_science_pack(pack)) do
      if not seen[gate] then seen[gate] = true; gates[#gates + 1] = gate end
    end
  end
  table.sort(gates)
  return gates
end

target_profiles.current_factorio_version = "0.15"
raw = f015_progression_world()
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  local expected = {
    ["high-tech-science-pack"] = {"advanced-electronics-2", "automation-2", "battery", "speed-module"},
    ["production-science-pack"] = {"advanced-material-processing-2", "electric-engine", "engine"},
    ["military-science-pack"] = {"military-2", "turrets"}
  }
  for pack, gates in pairs(expected) do
    check(equal_names(science.prereq_techs_for_science_pack(pack), gates),
      "F015 declared progression preserves the exact published gate union for " .. pack)
    local source = science.production_route_for_pack(pack)
    check(#source.unlockers == 1 and source.unlockers[1] == gates[1]
        and #source.progression_prerequisites == #gates - 1 and source.acquisition_proof == false,
      "F015 progression gates remain separate from the direct source unlocker for " .. pack)
  end
  local actual_422_vectors = {
    ["braking-force-8"] = {{"high-tech-science-pack", "production-science-pack"},
      {"advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "speed-module"}},
    ["inserter-capacity-bonus-8"] = {{"high-tech-science-pack", "production-science-pack"},
      {"advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "speed-module"}},
    ["research-speed-7"] = {{"high-tech-science-pack", "production-science-pack"},
      {"advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "speed-module"}},
    ["worker-robots-storage-4"] = {{"high-tech-science-pack", "production-science-pack"},
      {"advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "speed-module"}},
    ["recipe-prod-research_character_crafting_speed-1"] = {{"high-tech-science-pack", "military-science-pack"},
      {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}},
    ["recipe-prod-research_character_mining_speed-1"] = {{"high-tech-science-pack", "military-science-pack"},
      {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}},
    ["recipe-prod-research_character_reach-1"] = {{"high-tech-science-pack", "military-science-pack"},
      {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}},
    ["recipe-prod-research_character_walking_speed-1"] = {{"high-tech-science-pack", "military-science-pack"},
      {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}},
    ["recipe-prod-research_inventory_capacity-1"] = {{"high-tech-science-pack", "military-science-pack"},
      {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}},
    ["recipe-prod-research_electric_shooting_speed-1"] = {{"military-science-pack", "production-science-pack"},
      {"advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets"}},
    ["recipe-prod-research_flamethrower_shooting_speed-1"] = {{"military-science-pack", "production-science-pack"},
      {"advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets"}},
    ["recipe-prod-research_rocket_shooting_speed-1"] = {{"military-science-pack", "production-science-pack"},
      {"advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets"}},
    ["recipe-prod-research_robot_battery-1"] = {{"production-science-pack"},
      {"advanced-material-processing-2", "electric-engine", "engine"}}
  }
  for name, row in pairs(actual_422_vectors) do
    check(equal_names(f015_vector_gates(science, row[1]), row[2]),
      "F015 retained declaration matches the captured 4.2.2 prerequisite union for " .. name)
  end
  check(equal_names(science.prereq_techs_for_science_pack("logistic-science-pack"), {"logistic-science-pack"}),
    "The F015 declaration does not add progression gates to a non-selected pack")
  local changed = science.production_route_for_pack("high-tech-science-pack")
  changed.progression_prerequisites[1] = "caller-mutation"
  check(science.production_route_for_pack("high-tech-science-pack").progression_prerequisites[1] == "automation-2",
    "Public F015 progression records remain copy-isolated")
end)

raw = f015_progression_world()
raw.recipe["high-tech-science-pack"].ingredients[1] = {"iron-plate", 1}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["high-tech-science-pack"] == nil
      and string.find(index.issues["high-tech-science-pack"], "retained-progression-recipe-ingredients-mismatch", 1, true),
    "A changed F015 pack recipe refuses the retained progression declaration")
end)

raw = f015_progression_world()
raw.recipe["military-science-pack"].category = "chemistry"
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["military-science-pack"] == nil
      and string.find(index.issues["military-science-pack"], "retained-progression-recipe-category-mismatch", 1, true),
    "A changed F015 recipe machine category refuses the retained progression declaration")
end)

raw = f015_progression_world()
raw["assembling-machine"]["assembling-machine-1"].ingredient_count = 4
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["high-tech-science-pack"] == nil
      and string.find(index.issues["high-tech-science-pack"], "retained-progression-initial-machine-mismatch:assembling-machine-1", 1, true),
    "A raised F015 initial assembler ingredient limit refuses the automation-2 declaration")
end)

raw = f015_progression_world()
raw.item["initial-wide-assembler"] = {type = "item", name = "initial-wide-assembler"}
raw["assembling-machine"]["initial-wide-assembler"] = {type = "assembling-machine", name = "initial-wide-assembler",
  minable = {result = "initial-wide-assembler"}, crafting_categories = {"crafting"}, ingredient_count = 4}
raw.recipe["initial-wide-assembler"] = {type = "recipe", name = "initial-wide-assembler", enabled = false,
  results = {{type = "item", name = "initial-wide-assembler", amount = 1}}}
raw.technology.automation.effects[#raw.technology.automation.effects + 1] =
  {type = "unlock-recipe", recipe = "initial-wide-assembler"}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["high-tech-science-pack"] == nil
      and string.find(index.issues["high-tech-science-pack"], "retained-progression-initial-machine-capability-changed:initial-wide-assembler", 1, true),
    "An additional initial wide crafting machine refuses the automation-2 declaration")
end)

raw = f015_progression_world()
raw.item["late-wide-assembler"] = {type = "item", name = "late-wide-assembler"}
raw["assembling-machine"]["late-wide-assembler"] = {type = "assembling-machine", name = "late-wide-assembler",
  minable = {result = "late-wide-assembler"}, crafting_categories = {"crafting"}, ingredient_count = 4}
raw.recipe["late-wide-assembler"] = {type = "recipe", name = "late-wide-assembler", enabled = false,
  results = {{type = "item", name = "late-wide-assembler", amount = 1}}}
raw.technology["automation-3"] = {type = "technology", name = "automation-3",
  research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
  effects = {{type = "unlock-recipe", recipe = "late-wide-assembler"}}}
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(equal_names(science.prereq_techs_for_science_pack("high-tech-science-pack"),
      {"advanced-electronics-2", "automation-2", "battery", "speed-module"}),
    "An unrelated non-initial wide machine cannot veto the F015 retained declaration")
end)

raw = f015_progression_world()
raw.technology["speed-module"] = nil
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["high-tech-science-pack"] == nil
      and string.find(index.issues["high-tech-science-pack"], "retained-progression-prerequisite-missing-technology:speed-module", 1, true),
    "A missing F015 retained progression technology refuses the declaration")
end)

raw = f015_progression_world()
raw.technology["battery"].enabled = false
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["high-tech-science-pack"] == nil
      and string.find(index.issues["high-tech-science-pack"], "retained-progression-prerequisite-disabled-technology:battery", 1, true),
    "A disabled F015 retained progression technology refuses the declaration")
end)

raw = f015_progression_world()
raw.technology["advanced-electronics-2"].effects = {}
raw.technology["other-high-tech-unlock"] = {type = "technology", name = "other-high-tech-unlock",
  research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
  effects = {{type = "unlock-recipe", recipe = "high-tech-science-pack"}}}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["high-tech-science-pack"] == nil
      and string.find(index.issues["high-tech-science-pack"], "retained-progression-source-mismatch", 1, true),
    "A different F015 direct recipe unlocker cannot inherit the retained progression declaration")
end)

target_profiles.current_factorio_version = "0.17"
raw = f015_progression_world()
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  check(equal_names(science.prereq_techs_for_science_pack("high-tech-science-pack"), {"advanced-electronics-2"}),
    "The F015 retained progression declaration cannot apply on a different target line")
end)

-- Captured 4.2.01602 definitions, independently observed before the R22
-- upgrade failure, retain these science gates. The 0.16 production recipe
-- has two ingredients; it must not inherit the 0.15 recipe shape.
local function f016_progression_world()
  local value = f015_progression_world()
  value.recipe["production-science-pack"].ingredients = {{"electric-engine-unit", 1}, {"electric-furnace", 1}}
  value.tool["science-pack-3"] = {type = "tool", name = "science-pack-3"}
  value.lab.lab.inputs[#value.lab.lab.inputs + 1] = "science-pack-3"
  value.recipe["science-pack-3"] = {type = "recipe", name = "science-pack-3", enabled = false,
    ingredients = {{"advanced-circuit", 1}, {"engine-unit", 1}, {"electric-mining-drill", 1}},
    results = {{type = "item", name = "science-pack-3", amount = 1}}}
  value.technology["advanced-electronics"] = {type = "technology", name = "advanced-electronics",
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
    effects = {{type = "unlock-recipe", recipe = "science-pack-3"}}}
  return value
end

target_profiles.current_factorio_version = "0.16"
raw = f016_progression_world()
Context.with_active(Context.new(), function()
  local science = require("prototypes.mir.capabilities.science_integration.science_packs")
  local groups = {
    {names = {"braking-force-8", "inserter-capacity-bonus-8", "worker-robots-storage-4"},
      packs = {"science-pack-3", "high-tech-science-pack", "production-science-pack"},
      gates = {"advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "speed-module"}},
    {names = {"research-speed-7", "recipe-prod-research_lab_productivity-1"},
      packs = {"science-pack-3", "high-tech-science-pack", "production-science-pack", "military-science-pack"},
      gates = {"advanced-electronics", "advanced-electronics-2", "advanced-material-processing-2", "automation-2", "battery", "electric-engine", "engine", "military-2", "speed-module", "turrets"}},
    {names = {"recipe-prod-research_character_crafting_speed-1", "recipe-prod-research_character_mining_speed-1",
        "recipe-prod-research_character_reach-1", "recipe-prod-research_character_walking_speed-1", "recipe-prod-research_inventory_capacity-1"},
      packs = {"high-tech-science-pack", "military-science-pack"},
      gates = {"advanced-electronics-2", "automation-2", "battery", "military-2", "speed-module", "turrets"}},
    {names = {"recipe-prod-research_electric_shooting_speed-1", "recipe-prod-research_flamethrower_shooting_speed-1", "recipe-prod-research_rocket_shooting_speed-1"},
      packs = {"science-pack-3", "production-science-pack", "military-science-pack"},
      gates = {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine", "military-2", "turrets"}},
    {names = {"recipe-prod-research_robot_battery-1"}, packs = {"science-pack-3", "production-science-pack"},
      gates = {"advanced-electronics", "advanced-material-processing-2", "electric-engine", "engine"}}
  }
  for _, group in ipairs(groups) do
    local actual = f015_vector_gates(science, group.packs)
    for _, name in ipairs(group.names) do
      check(equal_names(actual, group.gates),
        "F016 retained science gates match the independent published definition for " .. name)
    end
  end
  check(equal_names(science.prereq_techs_for_science_pack("science-pack-3"), {"advanced-electronics", "engine"}),
    "F016 chemical science retains its declared engine-unit progression gate")
  check(science.production_route_for_pack("science-pack-3").acquisition_proof == false,
    "F016 retained progression is a declared reference contract, not a factory proof")
end)

raw = f016_progression_world()
raw.recipe["production-science-pack"].ingredients[#raw.recipe["production-science-pack"].ingredients + 1] = {"assembling-machine-1", 1}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["production-science-pack"] == nil
      and string.find(index.issues["production-science-pack"], "retained-progression-recipe-ingredients-mismatch", 1, true),
    "F016 cannot inherit the different F015 production recipe declaration")
end)

raw = f016_progression_world()
raw.recipe["science-pack-3"].ingredients[2] = {"iron-plate", 1}
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["science-pack-3"] == nil
      and string.find(index.issues["science-pack-3"], "retained-progression-recipe-ingredients-mismatch", 1, true),
    "A changed F016 chemical recipe cannot receive a stale engine progression gate")
end)

raw = f016_progression_world()
raw.technology.engine.enabled = false
Context.with_active(Context.new(), function()
  local index = bindings.compile_references(catalogue.shared, {{name = "lab", inputs = deepcopy(raw.lab.lab.inputs), sources = {{initial = true}}}})
  check(index.packs["science-pack-3"] == nil
      and string.find(index.issues["science-pack-3"], "retained-progression-prerequisite-disabled-technology:engine", 1, true),
    "A disabled F016 engine technology refuses its retained chemical declaration")
end)
target_profiles.current_factorio_version = "2.0"

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
