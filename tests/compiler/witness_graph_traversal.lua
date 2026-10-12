local hooks = assert(WITNESS_GRAPH_HOOKS, "Missing witness graph test hooks")

local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  assert(condition, message)
end

local function node(recipe, unlocker, identity)
  return {
    kind = "research-unlocked-recipe",
    recipe = recipe,
    unlocker = unlocker,
    output = identity or {type = "item", name = recipe .. "-output"}
  }
end

local function pair_names(pairs)
  local names = {}
  for _, pair in ipairs(pairs) do
    table.insert(names, pair.recipe .. "\0" .. pair.unlocker)
  end
  return table.concat(names, "\1")
end

local function set_names(values)
  local names = {}
  for name, present in pairs(values) do
    if present then table.insert(names, name) end
  end
  table.sort(names)
  return table.concat(names, "\1")
end

local shared_leaf = node("shared-leaf", "tech-shared-leaf")
local shared = node("shared", "tech-shared")
shared.ingredients = {shared_leaf}
local construction = node("construction", "tech-construction")
local receiver = node("receiver", "tech-receiver")
local machine = node("machine-placement", "tech-machine")
local launcher = node("capture-launcher", "tech-launcher")
local ammunition = node("capture-ammunition", "tech-ammunition")
local root = node("outer", "tech-outer", {type = "item", name = "outer-pack"})
root.recipe_witness = shared
root.ingredients = {construction, shared}
root.receiver = {acquisition = receiver}
root.machine = {
  acquisition = machine,
  launcher = launcher,
  ammunition = ammunition
}

local children = hooks.acquisition_children(root)
check(#children == 7, "The complete witness child set must retain every acquisition edge")
check(children[1] == shared, "Recipe witness must remain first")
check(children[2] == construction and children[3] == shared,
  "Construction ingredients and aliases must retain their source order")
check(children[4] == receiver, "Native receiver acquisition must remain reachable")
check(children[5] == machine, "Machine placement acquisition must remain reachable")
check(children[6] == launcher, "Native capture launcher must remain reachable")
check(children[7] == ammunition, "Native capture ammunition must remain reachable")

local selected = hooks.selected_research_unlock_pairs(root)
check(pair_names(selected) == table.concat({
  "capture-ammunition\0tech-ammunition",
  "capture-launcher\0tech-launcher",
  "construction\0tech-construction",
  "machine-placement\0tech-machine",
  "outer\0tech-outer",
  "receiver\0tech-receiver",
  "shared\0tech-shared",
  "shared-leaf\0tech-shared-leaf"
}, "\1"), "Selected pairs must retain each distinct nested unlock exactly once in canonical order")

local dependencies = {pairs = {}, required_technologies = {}}
hooks.witness_unlock_dependencies(root, {
  ["tech-shared"] = false,
  ["tech-ammunition"] = 1,
  ["unrelated-tech"] = true
}, dependencies)
check(set_names(dependencies.pairs) == pair_names(selected),
  "Dependency pairs must retain the complete selected unlock frontier")
check(set_names(dependencies.required_technologies) == "tech-ammunition\1tech-shared",
  "Only non-nil active unlocker entries belong to the reusable dependency set")

local fluid = node("fluid-source", "tech-fluid", {type = "fluid", name = "water"})
check(not hooks.witness_avoids_active_identities(fluid, {["fluid\0water"] = true}, "item\0outer-pack"),
  "An active typed fluid identity must block reuse")
check(hooks.witness_avoids_active_identities(fluid, {["item\0water"] = true}, "item\0outer-pack"),
  "A same-named item must not block a fluid witness")
check(hooks.witness_avoids_active_identities(root, {["item\0outer-pack"] = true}, "item\0outer-pack"),
  "The queried root remains reusable when it is the only active root identity")

local cycle = node("pointer-cycle", "tech-cycle")
cycle.ingredients = {cycle}
check(not hooks.witness_avoids_active_identities(cycle, {}, "item\0different-root"),
  "A structural witness back-edge must never make a memo witness reusable")
local cycle_dependencies = {pairs = {}, required_technologies = {}}
hooks.witness_unlock_dependencies(cycle, {['tech-cycle'] = true}, cycle_dependencies)
check(set_names(cycle_dependencies.pairs) == "pointer-cycle\0tech-cycle",
  "Dependency collection must terminate on a structural witness cycle")
check(pair_names(hooks.selected_research_unlock_pairs(cycle)) == "pointer-cycle\0tech-cycle",
  "Pair collection must terminate on a structural witness cycle")

local alias_leaf = node("alias-leaf", "tech-alias-leaf")
local alias = node("alias", "tech-alias")
alias.ingredients = {alias_leaf}
local alias_root = {output = {type = "item", name = "alias-root"}, ingredients = {}}
for _ = 1, 128 do table.insert(alias_root.ingredients, alias) end

-- This is the exact former recursive shape without pointer deduplication. It
-- supplies an operation-count baseline only; it is never used as production
-- policy and intentionally does not visit the structural cycle above.
local function reference_avoids_active_identities(witness, visiting, root_key)
  if type(witness) ~= "table" then return true end
  local output = witness.output or witness.product
  if type(output) == "table" and output.type and output.name then
    local key = output.type .. "\0" .. output.name
    _G.__witness_identity_calls = (_G.__witness_identity_calls or 0) + 1
    if key ~= root_key and visiting[key] then return false end
  end
  for _, child in ipairs(hooks.acquisition_children(witness)) do
    if not reference_avoids_active_identities(child, visiting, root_key) then return false end
  end
  return true
end

_G.__witness_identity_calls = 0
check(reference_avoids_active_identities(alias_root, {}, "item\0alias-root"),
  "The reference alias graph must be admissible before work is compared")
local naive_alias_identity_calls = _G.__witness_identity_calls
check(naive_alias_identity_calls == 257,
  "The reference traversal must retain its exact repeated-alias work baseline")
_G.__witness_identity_calls = 0
check(hooks.witness_avoids_active_identities(alias_root, {}, "item\0alias-root"),
  "Repeated aliases must remain reusable when their identities are inactive")
local alias_identity_calls = _G.__witness_identity_calls
check(alias_identity_calls == 3,
  "Each witness table must establish its active identity at most once per traversal")
check(alias_identity_calls < naive_alias_identity_calls,
  "The DAG-aware traversal must remove repeated alias visits")

local alternative_left = node("alternative-left", "tech-left", {type = "item", name = "same-output"})
local alternative_right = node("alternative-right", "tech-right", {type = "item", name = "same-output"})
local alternative_root = {output = {type = "item", name = "alternative-root"},
  ingredients = {alternative_left, alternative_right}}
_G.__witness_identity_calls = 0
check(hooks.witness_avoids_active_identities(alternative_root, {}, "item\0alternative-root"),
  "Separate witness alternatives with one output identity must remain admissible")
check(_G.__witness_identity_calls == 3,
  "Pointer aliases may collapse, but distinct witness records must not collapse by output identity")
check(pair_names(hooks.selected_research_unlock_pairs(alternative_root))
    == "alternative-left\0tech-left\1alternative-right\0tech-right",
  "Distinct witness alternatives must retain both unlock pairs")

local mutable = node("mutable-recipe", "tech-before")
local before_mutation = pair_names(hooks.selected_research_unlock_pairs(mutable))
mutable.unlocker = "tech-after"
local after_mutation = pair_names(hooks.selected_research_unlock_pairs(mutable))
check(before_mutation == "mutable-recipe\0tech-before" and after_mutation == "mutable-recipe\0tech-after",
  "Traversal summaries must not survive mutation of an exported witness")

local first = {ingredients = {
  node("z-recipe", "tech-z"),
  node("a-recipe", "tech-a")
}}
local second = {ingredients = {
  node("a-recipe", "tech-a"),
  node("z-recipe", "tech-z")
}}
check(pair_names(hooks.selected_research_unlock_pairs(first))
    == pair_names(hooks.selected_research_unlock_pairs(second)),
  "Permutation of witness child order must not alter canonical selected-pair output")

print("MIR-WITNESS-GRAPH-TRAVERSAL-PASS " .. assertions)
return {
  assertions = assertions,
  alias_identity_calls = alias_identity_calls,
  naive_alias_identity_calls = naive_alias_identity_calls
}
