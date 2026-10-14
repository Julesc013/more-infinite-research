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
  local raw = {recipe = {}, technology = {}, tool = {}, lab = {
    lab = {name = "lab", inputs = deepcopy(roles)}
  }}
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
return checks
