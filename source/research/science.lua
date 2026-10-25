-- Shared startup-policy projection for already-authored MIR technologies.
-- It owns neither technology identities nor ecosystem progression discovery.
local bindings = require("compatibility.science_bindings")

local M = {}
local POLICY_DEFAULT = "configured"
local LAB_DEFAULT = "reduce"
local ITEM_TYPES = {
  "tool", "item", "ammo", "capsule", "gun", "armor", "module", "repair-tool",
  "mining-tool", "item-with-entity-data", "item-with-inventory", "item-with-label",
  "item-with-tags", "selection-tool", "copy-paste-tool", "blueprint", "blueprint-book",
  "deconstruction-item", "upgrade-item", "spidertron-remote", "rail-planner",
  "space-platform-starter-pack"
}
local VALID_POLICIES = {
  configured = true, space = true, ["space-and-promethium"] = true,
  ["space-age-progression"] = true, ["official-progression"] = true,
  ["mod-progression"] = true, ["all-official"] = true, all = true
}

local function copy_list(source)
  local out = {}
  for index, value in ipairs(source or {}) do out[index] = value end
  return out
end

local function option(context, name, fallback)
  local value = (context.options or {})[name]
  return value == nil and fallback or value
end

local function item_exists(raw, name)
  if type(raw) ~= "table" or type(name) ~= "string" or name == "" then return false end
  for _, kind in ipairs(ITEM_TYPES) do
    if type(raw[kind]) == "table" and raw[kind][name] ~= nil then return true end
  end
  return false
end

local function technology_exists(raw, name)
  return type(raw) == "table" and type(raw.technology) == "table" and raw.technology[name] ~= nil
end

local function positive(value)
  return type(value) == "number" and value == value and value > 0
    and value ~= math.huge and value ~= -math.huge
end

local function nonnegative(value)
  return type(value) == "number" and value == value and value >= 0
    and value ~= math.huge and value ~= -math.huge
end

local function named_entry(row)
  if type(row) ~= "table" then return nil end
  return row.name or row[1]
end

local function positive_product_amount(row)
  if type(row) ~= "table" then return false end
  if row.amount ~= nil then
    return positive(row.amount) and row.amount_min == nil and row.amount_max == nil
  end
  if row.amount_min ~= nil or row.amount_max ~= nil then
    -- A zero lower bound remains a productive outcome when its finite upper
    -- bound is positive. This mirrors a probabilistic output rather than
    -- treating the possible zero roll as an absent source.
    return nonnegative(row.amount_min) and positive(row.amount_max) and row.amount_min <= row.amount_max
  end
  if row[2] ~= nil then return positive(row[2]) end
  return true
end

local function positive_product_probability(row)
  return type(row) == "table"
    and (row.probability == nil or positive(row.probability))
    and (row.independent_probability == nil or positive(row.independent_probability))
end

local function has_positive_item_output(rows, wanted)
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    if type(row) == "table" then
      local name = named_entry(row)
      if (row.type == nil or row.type == "item") and name == wanted
        and positive_product_amount(row) and positive_product_probability(row) then return true end
    end
  end
  return false
end

local function recipe_outputs(recipe, pack)
  if type(recipe) ~= "table" then return false end
  if recipe.result == pack and (recipe.result_type == nil or recipe.result_type == "item") then
    return recipe.result_count == nil or positive(recipe.result_count)
  end
  return has_positive_item_output(recipe.results, pack)
end

local function recipe_forms(recipe)
  if type(recipe) ~= "table" then return nil, "recipe-shape" end
  if recipe.normal == nil and recipe.expensive == nil then return {recipe} end
  if type(recipe.normal) ~= "table" or type(recipe.expensive) ~= "table" then
    return nil, "recipe-difficulty-shape"
  end
  return {recipe.normal, recipe.expensive}
end

local function has_direct_self_input(recipe, pack)
  for _, row in ipairs(type(recipe) == "table" and recipe.ingredients or {}) do
    if type(row) == "table" and (row.type == nil or row.type == "item") and named_entry(row) == pack then return true end
  end
  return false
end

local function has_unlock(technology, recipe)
  for _, effect in ipairs(type(technology) == "table" and technology.effects or {}) do
    if type(effect) == "table" and effect.type == "unlock-recipe" and effect.recipe == recipe then return true end
  end
  return false
end

local function has_named_prerequisites(technology, expected)
  if type(expected) ~= "table" or #expected == 0 then return true end
  local found = {}
  for _, name in ipairs(type(technology) == "table" and technology.prerequisites or {}) do found[name] = true end
  for _, name in ipairs(expected) do if not found[name] then return false end end
  return true
end

local function has_expected_trigger(technology, expected)
  if type(expected) ~= "table" then return true end
  local trigger = type(technology) == "table" and technology.research_trigger or nil
  if type(trigger) ~= "table" or trigger.type ~= expected.type then return false end
  for key, value in pairs(expected) do
    if key ~= "type" and trigger[key] ~= value then return false end
  end
  return true
end

local function owner_uses_own_pack(technology, pack)
  for _, row in ipairs(type(technology) == "table" and type(technology.unit) == "table"
    and technology.unit.ingredients or {}) do
    if named_entry(row) == pack then return true end
  end
  for _, prerequisite in ipairs(type(technology) == "table" and technology.prerequisites or {}) do
    if prerequisite == pack then return true end
  end
  return false
end

local function find_item(raw, name)
  for _, kind in ipairs(ITEM_TYPES) do
    local items = type(raw) == "table" and raw[kind] or nil
    if type(items) == "table" and type(items[name]) == "table" then return items[name] end
  end
  return nil
end

local function valid_owner(raw, contract, require_unlock)
  local owner = type(raw.technology) == "table" and raw.technology[contract.owner] or nil
  if type(owner) ~= "table" then return nil, "missing-owner:" .. tostring(contract.owner) end
  if owner.enabled == false then return nil, "disabled-owner:" .. tostring(contract.owner) end
  if require_unlock ~= false and not has_unlock(owner, contract.recipe) then
    return nil, "missing-owner-unlock:" .. tostring(contract.owner)
  end
  if not has_named_prerequisites(owner, contract.owner_prerequisites) then
    return nil, "owner-prerequisites:" .. tostring(contract.owner)
  end
  if not has_expected_trigger(owner, contract.owner_trigger) then
    if not bindings.owner_unit_alternative_is_declared(contract) or owner.research_trigger ~= nil then
      return nil, "owner-trigger:" .. tostring(contract.owner)
    end
    local unit = owner.unit
    if type(unit) ~= "table" or not positive(unit.time)
      or not (positive(unit.count) or (type(unit.count_formula) == "string" and unit.count_formula:find("%S")))
      or (unit.count ~= nil and unit.count_formula ~= nil)
      or type(unit.ingredients) ~= "table" or #unit.ingredients == 0 then
      return nil, "owner-unit:" .. tostring(contract.owner)
    end
    local count, seen = 0, {}
    for key, ingredient in pairs(unit.ingredients) do
      count = count + 1
      local name = named_entry(ingredient)
      if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #unit.ingredients
        or type(ingredient) ~= "table" or (ingredient.type ~= nil and ingredient.type ~= "item")
        or not item_exists(raw, name) or seen[name] or not positive(ingredient.amount or ingredient[2]) then
        return nil, "owner-unit-ingredient:" .. tostring(contract.owner)
      end
      seen[name] = true
    end
    if count ~= #unit.ingredients then return nil, "owner-unit-ingredient:" .. tostring(contract.owner) end
  end
  if owner_uses_own_pack(owner, contract.pack) then return nil, "self-supporting-owner:" .. tostring(contract.owner) end
  return owner
end

local function valid_recipe(raw, contract, require_initial)
  local recipe = type(raw.recipe) == "table" and raw.recipe[contract.recipe] or nil
  if type(recipe) ~= "table" then return nil, "missing-recipe:" .. tostring(contract.recipe) end
  local forms, shape_reason = recipe_forms(recipe)
  if not forms then return nil, shape_reason .. ":" .. tostring(contract.recipe) end
  for _, form in ipairs(forms) do
    -- RecipePrototype defaults `enabled` to true. The older red/green
    -- definitions rely on that default, while an explicit false is not an
    -- initial source. Each difficulty form must establish the named pack.
    if require_initial and form.enabled == false then return nil, "recipe-not-initial:" .. tostring(contract.recipe) end
    if not recipe_outputs(form, contract.pack) then return nil, "recipe-output:" .. tostring(contract.recipe) end
    if has_direct_self_input(form, contract.pack) then return nil, "self-supporting-recipe:" .. tostring(contract.recipe) end
  end
  return recipe
end

local function recipe_is_explicitly_disabled(recipe)
  local forms = recipe_forms(recipe)
  if not forms then return false end
  for _, form in ipairs(forms) do if form.enabled ~= false then return false end end
  return true
end

local function valid_payload(item, pack, legacy)
  if type(item) ~= "table" then return false end
  if legacy == true then
    local row = item.rocket_launch_product
    return type(row) == "table" and row[1] == pack and positive(row[2])
  end
  return has_positive_item_output(item.rocket_launch_products, pack)
end

-- A source contract is a small explicit relation.  It never enumerates raw
-- recipes, owners, labs, or acquisition paths.  `alternatives` is likewise a
-- caller-authored finite OR, not an invitation to find another producer.
local function validate_contract_shape(contract, expected_pack)
  if type(contract) ~= "table" or type(contract.kind) ~= "string" then return nil, "unbound" end
  if type(contract.pack) ~= "string" or contract.pack == "" then return nil, "missing-contract-pack" end
  if contract.pack ~= expected_pack then return nil, "contract-pack-mismatch:" .. tostring(contract.pack) end
  return true
end

local function validate_single_source(raw, contract)
  if contract.kind == "initial-recipe" then
    local _, reason = valid_recipe(raw, contract, true)
    return reason == nil, reason
  end
  if contract.kind == "recipe-unlock" then
    local _, recipe_reason = valid_recipe(raw, contract, false)
    if recipe_reason then return nil, recipe_reason end
    local _, owner_reason = valid_owner(raw, contract, true)
    return owner_reason == nil, owner_reason
  end
  if contract.kind == "trigger-output" then
    if contract.recipe ~= nil then
      local recipe, recipe_reason = valid_recipe(raw, contract, false)
      if recipe_reason then return nil, recipe_reason end
      if not recipe_is_explicitly_disabled(recipe) then return nil, "trigger-recipe-enabled:" .. tostring(contract.recipe) end
    end
    local owner, owner_reason = valid_owner(raw, contract, false)
    if owner_reason then return nil, owner_reason end
    if contract.recipe ~= nil and has_unlock(owner, contract.recipe) then
      return nil, "trigger-owner-unlock:" .. tostring(contract.owner)
    end
    local payload = find_item(raw, contract.payload)
    if not valid_payload(payload, contract.pack, false) then return nil, "payload-output:" .. tostring(contract.payload) end
    return true
  end
  if contract.kind == "legacy-rocket-result" then
    local rocket = type(raw["rocket-silo-rocket"]) == "table" and raw["rocket-silo-rocket"][contract.rocket] or nil
    if type(rocket) ~= "table" then return nil, "missing-rocket:" .. tostring(contract.rocket) end
    local matched = false
    for _, row in ipairs(rocket.result_items or {}) do
      if type(row) == "table" and row[1] == contract.pack and positive(row[2]) and row[3] == contract.payload then
        matched = true; break
      end
    end
    if not matched then return nil, "rocket-result:" .. tostring(contract.rocket) end
    if not find_item(raw, contract.payload) then return nil, "missing-payload:" .. tostring(contract.payload) end
    local owner_contract = {pack = contract.pack, recipe = contract.owner_recipe, owner = contract.owner}
    local _, owner_reason = valid_owner(raw, owner_contract, true)
    return owner_reason == nil, owner_reason
  end
  if contract.kind == "legacy-rocket-product" or contract.kind == "satellite-launch-product" then
    if not valid_payload(find_item(raw, contract.payload), contract.pack, true) then
      return nil, "payload-output:" .. tostring(contract.payload)
    end
    local owner_contract = {pack = contract.pack, recipe = contract.owner_recipe, owner = contract.owner}
    local _, owner_reason = valid_owner(raw, owner_contract, true)
    return owner_reason == nil, owner_reason
  end
  if contract.kind == "resource" then
    local resource = type(raw.resource) == "table" and raw.resource[contract.resource] or nil
    local mined = type(resource) == "table" and resource.minable or nil
    if type(resource) ~= "table" or type(resource.autoplace) ~= "table" or type(mined) ~= "table"
      or mined.required_fluid ~= nil then return nil, "resource-shape:" .. tostring(contract.resource) end
    local positive_result = mined.result == contract.pack and (mined.count == nil or positive(mined.count))
      and (mined.result_count == nil or positive(mined.result_count))
    if not positive_result and not has_positive_item_output(mined.results, contract.pack) then
      return nil, "resource-output:" .. tostring(contract.resource)
    end
    return true
  end
  return nil, "unknown-contract:" .. contract.kind
end

-- Alternatives are one flat authored list. Reject nested/cyclic declarations
-- before reading any source; never interpret a recursive acquisition tree.
local function validate_source_contract(raw, contract, expected_pack)
  expected_pack = expected_pack or (type(contract) == "table" and contract.pack)
  if type(expected_pack) ~= "string" or expected_pack == "" then return nil, "missing-contract-pack" end
  local valid, reason = validate_contract_shape(contract, expected_pack)
  if not valid then return nil, reason end
  if contract.kind ~= "alternatives" then return validate_single_source(raw, contract) end
  local candidates = type(contract.alternatives) == "table" and contract.alternatives or {}
  for _, candidate in ipairs(candidates) do
    if candidate == contract then return nil, "cyclic-alternative" end
    local shape_valid, shape_reason = validate_contract_shape(candidate, expected_pack)
    if not shape_valid then return nil, shape_reason end
    if candidate.kind == "alternatives" then return nil, "nested-alternative" end
  end
  local reasons = {}
  for _, candidate in ipairs(candidates) do
    local accepted, source_reason = validate_single_source(raw, candidate)
    if accepted then return true end
    reasons[#reasons + 1] = source_reason or "invalid"
  end
  return nil, "no-complete-alternative:" .. table.concat(reasons, ",")
end

local function ingredient(ingredient)
  if type(ingredient) ~= "table" then return nil end
  local name, amount = ingredient.name or ingredient[1], ingredient.amount or ingredient[2]
  if type(name) ~= "string" or name == "" or type(amount) ~= "number" or amount ~= amount
    or amount < 1 or amount == math.huge or amount == -math.huge then return nil end
  return name, amount
end

local function copy_ingredients(source)
  local out, seen = {}, {}
  for _, value in ipairs(source or {}) do
    local name, amount = ingredient(value)
    if not name then return nil, "invalid-science-ingredient" end
    out[#out + 1] = {name, amount}
    seen[name] = true
  end
  return out, seen
end

local function append(out, seen, name, amount)
  if not seen[name] then
    seen[name] = true
    out[#out + 1] = {name, amount or 1}
  end
end

local function append_name(out, seen, name)
  if not seen[name] then
    seen[name] = true
    out[#out + 1] = name
  end
end

local function sort_names(values)
  table.sort(values, function(left, right) return left.name < right.name end)
  return values
end

-- This is the one bounded stage-local inspection used by broad policies and
-- lab reduction. It records each lab separately; no union is an accepting lab.
local function collector(context)
  if context.collector then return context.collector end
  local raw = context.raw or {}
  local labs, available, all = {}, {}, {}
  for name, lab in pairs(type(raw.lab) == "table" and raw.lab or {}) do
    context.lab_visits = context.lab_visits + 1
    if type(name) == "string" and type(lab) == "table" then
      local accepted, inputs = {}, {}
      for _, input in ipairs(type(lab.inputs) == "table" and lab.inputs or {}) do
        if item_exists(raw, input) and not accepted[input] then
          accepted[input] = true
          inputs[#inputs + 1] = input
          if not available[input] then available[input] = true; all[#all + 1] = input end
        end
      end
      labs[#labs + 1] = {name = name, accepted = accepted, inputs = inputs}
    end
  end
  sort_names(labs)
  table.sort(all)
  context.collector = {labs = labs, available = available, all = all}
  return context.collector
end

local function accepts(lab, ingredients)
  for _, row in ipairs(ingredients or {}) do
    if not lab.accepted[row[1]] then return false end
  end
  return #ingredients > 0
end

local function contains_all(ingredients, required)
  local seen = {}
  for _, row in ipairs(ingredients or {}) do seen[row[1]] = true end
  for _, name in ipairs(required or {}) do if not seen[name] then return false end end
  return true
end

local function contains_one(ingredients, names)
  if not names or #names == 0 then return true end
  local wanted = {}
  for _, name in ipairs(names) do wanted[name] = true end
  for _, row in ipairs(ingredients or {}) do if wanted[row[1]] then return true end end
  return false
end

-- Compatibility only inspects an ingredient's name.  The key deliberately
-- omits amounts, because the cached result is a set of current-row positions;
-- the result is rebuilt from the current row below.  Length prefixes make the
-- dense authored sequences unambiguous without depending on a name delimiter.
local function ordered_name_key(values, ingredient_rows)
  local encoded = {}
  for _, value in ipairs(values or {}) do
    local name = ingredient_rows and value[1] or value
    if type(name) ~= "string" then return nil end
    encoded[#encoded + 1] = #name .. ":" .. name
  end
  return #encoded .. ";" .. table.concat(encoded)
end

local function lab_decision_key(ingredients, required, phase_any, policy)
  local ingredient_key = ordered_name_key(ingredients, true)
  local required_key = ordered_name_key(required, false)
  local phase_key = ordered_name_key(phase_any, false)
  if not ingredient_key or not required_key or not phase_key then return nil end
  return policy .. "|" .. ingredient_key .. "|" .. required_key .. "|" .. phase_key
end

local function selected_indices(lab, ingredients)
  local indices, selected = {}, {}
  for index, row in ipairs(ingredients) do
    if lab.accepted[row[1]] then
      indices[#indices + 1] = index
      selected[row[1]] = true
    end
  end
  return indices, selected
end

local function selected_contains_all(selected, required)
  for _, name in ipairs(required or {}) do if not selected[name] then return false end end
  return true
end

local function selected_contains_one(selected, names)
  if not names or #names == 0 then return true end
  for _, name in ipairs(names) do if selected[name] then return true end end
  return false
end

local function rebuild_selected_ingredients(ingredients, indices)
  local out = {}
  for _, index in ipairs(indices) do
    local row = ingredients[index]
    out[#out + 1] = {row[1], row[2]}
  end
  return out
end

-- A prepared context represents one fixed data-stage view.  Cache just the
-- lab decision for a dense authored science vector in that view: either the
-- whole vector is accepted, no lab can accept a valid reduction, or these
-- current-vector indices are the canonical reduction.  It retains no caller
-- ingredient tables and has no cross-context invalidation lifecycle.
local function lab_decision(context, view, ingredients, required, phase_any, policy)
  local key = lab_decision_key(ingredients, required, phase_any, policy)
  local decisions = context.lab_decisions
  if not decisions then decisions = {}; context.lab_decisions = decisions end
  if key and decisions[key] then return decisions[key] end

  local decision
  if contains_all(ingredients, required) and contains_one(ingredients, phase_any) then
    for _, lab in ipairs(view.labs) do
      if accepts(lab, ingredients) then
        decision = {kind = "full"}
        break
      end
    end
  end
  if not decision and policy == "reduce" then
    local best_indices, best_size
    for _, lab in ipairs(view.labs) do
      local indices, selected = selected_indices(lab, ingredients)
      if #indices > 0 and selected_contains_all(selected, required)
        and selected_contains_one(selected, phase_any)
        and (not best_indices or #indices > best_size) then
        -- Labs are collected in canonical name order.  Keeping the first
        -- equally sized candidate preserves the historical tie-break.
        best_indices, best_size = indices, #indices
      end
    end
    if best_indices then decision = {kind = "reduced", indices = best_indices} end
  end
  decision = decision or {kind = "incompatible"}
  if key then decisions[key] = decision end
  return decision
end

local function policy_ingredients(source, binding, context, selected, view)
  local policy = option(context, "mir-science-pack-ingredient-policy", POLICY_DEFAULT)
  if not VALID_POLICIES[policy] then policy = POLICY_DEFAULT end
  local out, seen, added, added_seen, contracts = {}, {}, {}, {}, {}
  local function preserve(row)
    local name, amount = row[1], row[2]
    -- Existing ingredients retain their authored order and amounts, including
    -- a duplicate if a historical definition supplied one. `seen` only
    -- suppresses policy additions; it must not rewrite the input vector.
    if policy ~= "all-official" or selected.official_set[name] then
      out[#out + 1] = {name, amount}
      seen[name] = true
    end
  end
  for _, row in ipairs(source) do preserve(row) end

  local function add_if_available(name, contract)
    if type(name) == "string" and view.available[name] and not seen[name] then
      if type(contract) ~= "table" then
        context.unbound_science_sources[name] = context.unbound_science_sources[name] or policy
        return
      end
      append(out, seen, name, 1)
      append_name(added, added_seen, name)
      contracts[name] = contract
    end
  end
  local function selected_contract(name)
    return type(selected.source_contracts) == "table" and selected.source_contracts[name] or nil
  end
  if policy == "space" then
    add_if_available(selected.space, selected_contract(selected.space))
  elseif policy == "space-and-promethium" then
    add_if_available(selected.space, selected_contract(selected.space))
    add_if_available("promethium-science-pack", selected_contract("promethium-science-pack"))
  elseif policy == "space-age-progression" then
    local names = {}
    for _, row in ipairs(source) do names[row[1]] = true end
    local planets = {"agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack"}
    local has_planet = names["promethium-science-pack"] == true
    for _, name in ipairs(planets) do has_planet = has_planet or names[name] == true end
    if has_planet then add_if_available(selected.space, selected_contract(selected.space)) end
    if names["promethium-science-pack"] then
      for _, name in ipairs(planets) do add_if_available(name, selected_contract(name)) end
      add_if_available("promethium-science-pack", selected_contract("promethium-science-pack"))
    end
  elseif policy == "official-progression" then
    for _, row in ipairs(source) do
      for _, name in ipairs(selected.progression[row[1]] or {}) do add_if_available(name, selected_contract(name)) end
    end
  elseif policy == "mod-progression" then
    -- A caller may supply an approved finite binding for a known external
    -- pack. Unknown packs deliberately retain their original vector instead
    -- of starting the retired unlock/acquisition solver.
    for _, row in ipairs(source) do
      local additions = type(binding.mod_progression) == "table" and binding.mod_progression[row[1]] or nil
      if additions then
        for _, name in ipairs(additions) do
          local explicit = type(binding.mod_progression_sources) == "table" and binding.mod_progression_sources[name] or nil
          add_if_available(name, explicit)
        end
      elseif not selected.official_set[row[1]] then
        context.mod_progression_unbound[row[1]] = true
      end
    end
  elseif policy == "all-official" then
    for _, name in ipairs(selected.official) do add_if_available(name, selected_contract(name)) end
  elseif policy == "all" then
    -- The shipped registry ordered native official roles before arbitrary
    -- lab inputs. Preserve that deterministic order without treating an
    -- external input as a newly official science role.
    for _, name in ipairs(selected.official) do add_if_available(name, selected_contract(name)) end
    for _, name in ipairs(view.all) do add_if_available(name, selected_contract(name)) end
  end
  return out, policy, added, contracts
end

-- A compatibility binding can remove a finite, named retired science role
-- from a known owned row.  This runs only after a policy has formed its
-- selected vector, so broad policies cannot re-add the excluded pack.  It
-- also removes that name from the policy additions before their source and
-- prerequisite contracts are read.  Explicit required science is appended
-- later and remains a hard constraint.
local function exclude_science(ingredients, additions, contracts, excluded)
  if type(excluded) ~= "table" or #excluded == 0 then return ingredients, additions, contracts end
  local denied = {}
  for _, name in ipairs(excluded) do
    if type(name) == "string" and name ~= "" then denied[name] = true end
  end
  if next(denied) == nil then return ingredients, additions, contracts end
  local selected = {}
  for _, row in ipairs(ingredients or {}) do
    if not denied[row[1]] then selected[#selected + 1] = row end
  end
  local selected_additions, selected_contracts = {}, {}
  for _, name in ipairs(additions or {}) do
    if not denied[name] then
      selected_additions[#selected_additions + 1] = name
      selected_contracts[name] = contracts and contracts[name] or nil
    end
  end
  return selected, selected_additions, selected_contracts
end

-- This is the one retained K2 phase rule. It operates on the policy-selected
-- vector, as the shipped planner did, and returns a required surviving phase
-- trigger for subsequent lab reduction. It never probes foreign unlocks.
local function normalize_k2_phase(ingredients, selected)
  local phase = selected.k2_phase
  if type(phase) ~= "table" then return ingredients, {} end
  local present, phase_one, phase_two = {}, false, false
  local one, two = {}, {}
  for _, name in ipairs(phase.phase_one or {}) do one[name] = true end
  for _, name in ipairs(phase.phase_two or {}) do two[name] = true end
  for _, row in ipairs(ingredients) do
    local name = row[1]
    present[name] = true
    phase_one = phase_one or one[name] == true
    phase_two = phase_two or two[name] == true
  end
  if not phase_one and not phase_two then return ingredients, {} end

  local removed = {}
  if phase_one then removed[phase.basic] = true end
  local triggers = phase_one and one or {}
  if phase_two then
    for _, name in ipairs(phase.early or {}) do removed[name] = true end
    triggers = two
  end
  local out, required_any, required_seen = {}, {}, {}
  for _, row in ipairs(ingredients) do
    if not removed[row[1]] then out[#out + 1] = {row[1], row[2]} end
  end
  for _, row in ipairs(ingredients) do
    if triggers[row[1]] and present[row[1]] then append_name(required_any, required_seen, row[1]) end
  end
  if #out == 0 then return nil, required_any end
  return out, required_any
end

local function disable(technology, reason, ingredients, prerequisites)
  technology.enabled = false
  if ingredients then technology.unit.ingredients = ingredients end
  if prerequisites then technology.prerequisites = prerequisites end
  return {enabled = false, reason = reason, ingredients = ingredients, prerequisites = prerequisites}
end

local function merge_prerequisites(source, additions, excluded_source)
  local out, seen = {}, {}
  local denied
  if excluded_source then
    denied = {}
    for _, name in ipairs(excluded_source) do denied[name] = true end
  end
  for _, name in ipairs(source or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] and not (denied and denied[name]) then
      seen[name] = true; out[#out + 1] = name
    end
  end
  for _, name in ipairs(additions or {}) do
    if not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  return out
end

-- Existing prerequisites remain authored by the generated definition. This
-- supplements only science ingredients that this policy actually appended,
-- using a target-specific binding rather than reintroducing the retired
-- recipe/unlock discovery service.
local function policy_prerequisites(raw, selected, additions, context)
  local out, seen = {}, {}
  for _, pack in ipairs(additions or {}) do
    local replacement = context and context.direct_replacement_sources
      and context.direct_replacement_sources[pack]
    local prerequisites
    if replacement then prerequisites = replacement.owner and {replacement.owner} or {}
    else prerequisites = (selected.pack_prerequisites or {})[pack] or {} end
    for _, prerequisite in ipairs(prerequisites) do
      if not technology_exists(raw, prerequisite) then
        return nil, "missing-science-prerequisite:" .. pack .. ":" .. prerequisite
      end
      append_name(out, seen, prerequisite)
    end
  end
  return out
end

local function selected_binding(context)
  if context.binding then return context.binding end
  local selected = bindings.select(context.target, context.mods)
  selected.official_set = {}
  for _, name in ipairs(selected.official) do selected.official_set[name] = true end
  context.binding = selected
  return selected
end

local function no_prerequisites(owner)
  return owner.prerequisites == nil or (type(owner.prerequisites) == "table" and next(owner.prerequisites) == nil)
end

local function direct_craft_seed(owner, context, view)
  if type(owner) ~= "table" or owner.enabled == false
    or not no_prerequisites(owner) or owner.unit ~= nil then return false end
  if context.target.id ~= "f200" and context.target.id ~= "f210" then return false end
  local trigger = owner.research_trigger
  if type(trigger) ~= "table" or trigger.type ~= "craft-item" then return false end
  local count = trigger.count == nil and 1 or trigger.count
  return type(trigger.item) == "string" and trigger.item ~= "" and positive(count) and count % 1 == 0
    and find_item(context.raw, trigger.item) ~= nil and not view.available[trigger.item]
end

-- Only already-authored direct seeds may support a new research-owned source.
-- This does not propagate availability through foreign research or materials.
local function declared_seed_packs(context, selected, view)
  local seeds = {}
  for pack, contract in pairs(selected.source_contracts) do
    local choices = contract.kind == "alternatives" and contract.alternatives or {contract}
    for _, choice in ipairs(choices or {}) do
      local direct = choice.kind == "initial-recipe" or choice.kind == "resource"
      if choice.kind == "recipe-unlock" then
        direct = direct_craft_seed((context.raw.technology or {})[choice.owner], context, view)
      end
      if direct and validate_source_contract(context.raw, choice, pack) then seeds[pack] = true; break end
    end
  end
  return seeds
end

local function direct_research_seed(owner, context, view, seeds)
  if type(owner) ~= "table" or owner.enabled == false
    or not no_prerequisites(owner) or owner.research_trigger ~= nil then return false end
  local unit = owner.unit
  if type(unit) ~= "table" or not positive(unit.count) or unit.count % 1 ~= 0
    or unit.count_formula ~= nil or not positive(unit.time) or type(unit.ingredients) ~= "table"
    or #unit.ingredients == 0 then return false end
  local inputs, count = {}, 0
  for key, row in pairs(unit.ingredients) do
    count = count + 1
    local name, amount = ingredient(row)
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #unit.ingredients
      or not name or not seeds[name] or amount % 1 ~= 0
      or (row.type ~= nil and row.type ~= "item") then return false end
    inputs[key] = {name, amount}
  end
  return count == #unit.ingredients and lab_decision(context, view, inputs, {}, {}, "skip").kind == "full"
end

local function direct_recipe_packs(recipe, wanted)
  local forms = recipe_forms(recipe)
  if not forms then return nil end
  local packs, blocked, initial = nil, {}, true
  for _, form in ipairs(forms) do
    local outputs = {}
    if (form.result_type == nil or form.result_type == "item") and wanted[form.result]
      and (form.result_count == nil or positive(form.result_count)) then outputs[form.result] = true end
    for _, row in ipairs(type(form.results) == "table" and form.results or {}) do
      local name = named_entry(row)
      if type(row) == "table" and (row.type == nil or row.type == "item") and wanted[name]
        and positive_product_amount(row) and positive_product_probability(row) then outputs[name] = true end
    end
    for _, row in ipairs(type(form.ingredients) == "table" and form.ingredients or {}) do
      local name = named_entry(row)
      if type(row) == "table" and (row.type == nil or row.type == "item") and wanted[name] then blocked[name] = true end
    end
    if packs == nil then packs = outputs else
      for pack in pairs(packs) do if not outputs[pack] then packs[pack] = nil end end
    end
    initial = initial and form.enabled ~= false
  end
  for pack in pairs(blocked) do packs[pack] = nil end
  return packs, initial
end

-- The two admitted direct-source paths differ only in which packs authorize a
-- pass and where they cache the result. Keep their recipe/owner selection
-- identical: every accepted candidate remains a flat direct seed, and a
-- canonical name can never decide the tie-break.
local function collect_direct_sources(context, selected, view, wanted, recipe_visits, technology_visits)
  local chosen, pending = {}, {}
  local function choose(pack, recipe, owner)
    local previous = chosen[pack]
    if previous and previous.owner == nil and owner ~= nil then return end
    if not previous or (previous.owner ~= nil and owner == nil)
      or (previous.owner == nil) == (owner == nil) and (recipe < previous.recipe
        or recipe == previous.recipe and (owner or "") < (previous.owner or "")) then
      chosen[pack] = {kind = owner and "recipe-unlock" or "initial-recipe", pack = pack,
        recipe = recipe, owner = owner}
    end
  end
  for name, recipe in pairs(type(context.raw.recipe) == "table" and context.raw.recipe or {}) do
    context[recipe_visits] = context[recipe_visits] + 1
    if type(name) == "string" and name ~= "" then
      local packs, initial = direct_recipe_packs(recipe, wanted)
      if packs and next(packs) then
        if initial then for pack in pairs(packs) do choose(pack, name) end else pending[name] = packs end
      end
    end
  end
  for recipe, packs in pairs(pending) do
    for pack in pairs(packs) do if chosen[pack] then packs[pack] = nil end end
    if next(packs) == nil then pending[recipe] = nil end
  end
  if next(pending) then
    local seeds = declared_seed_packs(context, selected, view)
    for name, owner in pairs(type(context.raw.technology) == "table" and context.raw.technology or {}) do
      context[technology_visits] = context[technology_visits] + 1
      if type(name) == "string" and name ~= "" and type(owner) == "table" then
        local eligible
        for _, effect in ipairs(type(owner.effects) == "table" and owner.effects or {}) do
          local packs = type(effect) == "table" and effect.type == "unlock-recipe" and pending[effect.recipe] or nil
          if packs then
            if eligible == nil then eligible = direct_craft_seed(owner, context, view)
              or direct_research_seed(owner, context, view, seeds) end
            if eligible then for pack in pairs(packs) do choose(pack, effect.recipe, name) end end
          end
        end
      end
    end
  end
  return chosen
end

-- The opt-in `all` policy needs one bounded collection for unfamiliar lab
-- inputs. Admit only direct sources; never traverse foreign prerequisites,
-- infer factory acquisition, or treat a union of labs as one accepting lab.
local function bind_fresh_sources(context, selected, view, source)
  if context.fresh_source_contracts or type(selected.source_contracts) ~= "table" then return end
  local present, wanted, missing = {}, {}, false
  for _, row in ipairs(source) do present[row[1]] = true end
  for _, pack in ipairs(view.all) do
    if selected.source_contracts[pack] == nil and not selected.official_set[pack] then
      wanted[pack] = true
      missing = missing or not present[pack]
    end
  end
  -- An existing foreign ingredient alone never starts collection or acquires
  -- a new gate. A later family may independently need that pack as an addition.
  if not missing then return end
  local chosen = collect_direct_sources(context, selected, view, wanted,
    "fresh_recipe_visits", "fresh_technology_visits")
  context.fresh_source_contracts = chosen
  selected.pack_prerequisites = selected.pack_prerequisites or {}
  for pack, contract in pairs(chosen) do
    selected.source_contracts[pack] = contract
    selected.pack_prerequisites[pack] = contract.owner and {contract.owner} or {}
  end
end

-- The published 4.7.3 repair allowed one direct replacement only after an
-- opted-in current named recipe source failed. Inspect that finite selected
-- set once for this data-stage context; this is distinct from the `all`
-- policy's unfamiliar-input collection above and never broadens a healthy
-- or unopted source contract.
local function collect_direct_replacements(context, selected, view)
  if context.direct_replacement_scanned then return end
  context.direct_replacement_scanned = true
  context.direct_replacement_sources = {}
  local wanted = {}
  for pack, contract in pairs(type(selected.source_contracts) == "table" and selected.source_contracts or {}) do
    if type(contract) == "table" and contract.direct_recipe_replacement == true then
      local valid = validate_source_contract(context.raw, contract, pack)
      if not valid then wanted[pack] = true end
    end
  end
  if next(wanted) == nil then return end

  context.direct_replacement_sources = collect_direct_sources(context, selected, view, wanted,
    "direct_replacement_recipe_visits", "direct_replacement_technology_visits")
end

local function direct_replacement_contract(context, selected, view, pack, contract)
  if type(contract) ~= "table" or contract.direct_recipe_replacement ~= true then return contract end
  if validate_source_contract(context.raw, contract, pack) then return contract end
  collect_direct_replacements(context, selected, view)
  return context.direct_replacement_sources[pack] or contract
end

local function reported_policy(policy, context)
  if policy == POLICY_DEFAULT then return "configured" end
  for _, unresolved_policy in pairs(context.unbound_science_sources or {}) do
    if unresolved_policy == policy then return policy .. "-unbound-sources" end
  end
  return policy
end

function M.prepare(environment)
  environment = environment or {}
  return {
    raw = environment.raw or {}, options = environment.options or {}, target = environment.target or {}, mods = environment.mods,
    lab_visits = 0, lab_decisions = {}, mod_progression_unbound = {}, unbound_science_sources = {},
    fresh_recipe_visits = 0, fresh_technology_visits = 0,
    direct_replacement_recipe_visits = 0, direct_replacement_technology_visits = 0
  }
end

-- Kept public only to make the finite compatibility rows independently
-- testable.  It accepts an authored contract; callers cannot make it search.
function M.validate_source_contract(raw, contract, expected_pack)
  return validate_source_contract(raw or {}, contract, expected_pack)
end

-- Apply to a single owned, detached technology before Generator publication.
-- `binding` may be `conditions_for(family)` extended by a known caller-owned
-- finite mod progression table. `preserve_identity` is reserved for a hidden
-- earned carrier whose science vector cannot be reselected. No raw prototype
-- is ever changed here.
function M.apply(technology, binding, context)
  binding, context = binding or {}, context or M.prepare({})
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then
    return {enabled = false, reason = "missing-owned-research-unit"}
  end
  if binding.preserve_identity == true then
    return {enabled = technology.enabled ~= false, reason = "preserved-carrier",
      ingredients = technology.unit.ingredients, prerequisites = technology.prerequisites}
  end
  local source, reason = copy_ingredients(technology.unit.ingredients)
  if not source or #source == 0 then return disable(technology, reason or "missing-science-ingredients") end
  local selected, view = selected_binding(context), collector(context)
  local raw = context.raw
  if option(context, "mir-science-pack-ingredient-policy", POLICY_DEFAULT) == "all" then
    bind_fresh_sources(context, selected, view, source)
  end

  local required = copy_list(binding.required_science)
  for _, name in ipairs(required) do
    if not item_exists(raw, name) then return disable(technology, "missing-required-science:" .. name, source) end
    if name == "cryogenic-science-pack" then
      local contract = type(selected.source_contracts) == "table" and selected.source_contracts[name] or nil
      contract = direct_replacement_contract(context, selected, view, name, contract)
      local valid, source_reason = validate_source_contract(raw, contract, name)
      if not valid then
        return disable(technology, "invalid-required-science-source:" .. name .. ":" .. tostring(source_reason), source)
      end
    end
  end
  local ingredients, policy, additions, addition_contracts = policy_ingredients(source, binding, context, selected, view)
  ingredients, additions, addition_contracts = exclude_science(
    ingredients, additions, addition_contracts, binding.excluded_science)
  for _, name in ipairs(additions) do
    addition_contracts[name] = direct_replacement_contract(
      context, selected, view, name, addition_contracts[name])
    -- Fresh contracts were validated once against this fixed context before
    -- any publication, including all output forms and the selected seed arm.
    local valid, source_reason
    if context.fresh_source_contracts and context.fresh_source_contracts[name] == addition_contracts[name] then
      valid = true
    else
      valid, source_reason = validate_source_contract(raw, addition_contracts[name], name)
    end
    if not valid then
      return disable(technology, "invalid-science-source:" .. name .. ":" .. tostring(source_reason), source)
    end
  end
  local k2_phase_any
  ingredients, k2_phase_any = normalize_k2_phase(ingredients, selected)
  if not ingredients then
    return disable(technology, "k2-phase-empty", source)
  end
  if #ingredients == 0 then
    -- A policy may validly reject every available pack, but Generator still
    -- requires a valid retained identity. Keep its authored vector disabled.
    return disable(technology, "empty-science-selection", source)
  end
  for _, name in ipairs(required) do
    local seen = {}; for _, row in ipairs(ingredients) do seen[row[1]] = true end
    if not seen[name] then append(ingredients, seen, name, 1) end
  end
  if binding.phase_all_selected == true then
    for _, row in ipairs(ingredients) do required[#required + 1] = row[1] end
  end
  local phase_any, phase_seen = copy_list(binding.phase_any_science), {}
  for _, name in ipairs(phase_any) do phase_seen[name] = true end
  for _, name in ipairs(k2_phase_any) do append_name(phase_any, phase_seen, name) end
  if #phase_any > 0 then
    local found = false
    for _, name in ipairs(phase_any) do found = found or item_exists(raw, name) end
    if not found then return disable(technology, "missing-phase-science", ingredients) end
  end

  local policy_prereqs, prerequisite_reason = policy_prerequisites(raw, selected, additions, context)
  if not policy_prereqs then return disable(technology, prerequisite_reason, source) end
  -- A named compatibility binding may retire an already authored prerequisite.
  -- Filter that local source list only; later explicit policy/gate additions
  -- retain their authority. Never infer prerequisites from foreign prototypes.
  local prerequisites = merge_prerequisites(technology.prerequisites, policy_prereqs, binding.excluded_prerequisites)
  if option(context, "ips-require-space-gate", false) == true and binding.space_gate ~= false then
    local gate = selected.end_game
    if not gate then return disable(technology, "missing-end-game-gate", ingredients, prerequisites) end
    if not item_exists(raw, gate.pack) then return disable(technology, "missing-end-game-science:" .. gate.pack, ingredients, prerequisites) end
    local contract = type(selected.source_contracts) == "table" and selected.source_contracts[gate.pack] or nil
    contract = direct_replacement_contract(context, selected, view, gate.pack, contract)
    local valid, source_reason = validate_source_contract(raw, contract, gate.pack)
    if not valid then
      return disable(technology, "invalid-end-game-science-source:" .. gate.pack .. ":" .. tostring(source_reason), ingredients, prerequisites)
    end
    local gate_prerequisites
    if context.direct_replacement_sources and context.direct_replacement_sources[gate.pack] == contract then
      gate_prerequisites = contract.owner and {contract.owner} or {}
    else
      gate_prerequisites = gate.prerequisites
    end
    for _, name in ipairs(gate_prerequisites) do
      if not technology_exists(raw, name) then
        return disable(technology, "missing-end-game-gate-prerequisite:" .. name, ingredients, prerequisites)
      end
    end
    prerequisites = merge_prerequisites(prerequisites, gate_prerequisites)
  end

  local lab_policy = option(context, "mir-lab-incompatibility-policy", LAB_DEFAULT)
  if lab_policy ~= "skip" and lab_policy ~= "engine-default" then lab_policy = LAB_DEFAULT end
  local decision = lab_decision(context, view, ingredients, required, phase_any, lab_policy)
  if decision.kind == "full" then
    technology.unit.ingredients, technology.prerequisites = ingredients, prerequisites
    return {enabled = technology.enabled ~= false, reason = reported_policy(policy, context),
      ingredients = ingredients, prerequisites = prerequisites}
  end
  if lab_policy ~= "reduce" then
    return disable(technology, "lab-incompatible-" .. lab_policy, ingredients, prerequisites)
  end
  if decision.kind ~= "reduced" then return disable(technology, "lab-incompatible-reduce", ingredients, prerequisites) end
  local best = rebuild_selected_ingredients(ingredients, decision.indices)
  technology.unit.ingredients, technology.prerequisites = best, prerequisites
  return {enabled = technology.enabled ~= false, reason = "lab-reduced", ingredients = best, prerequisites = prerequisites}
end

function M.apply_family(rows, family_bindings, environment)
  local context, reports = M.prepare(environment), {}
  for index, row in ipairs(rows or {}) do
    local binding
    if type(family_bindings) == "table" then
      binding = family_bindings[index]
      if binding == nil and type(row) == "table" then
        binding = family_bindings[row.family] or family_bindings[row.name]
      end
    end
    if binding == nil then
      local family = row.name:match("^recipe%-prod%-(.-)%-%d+$") or row.name:match("^(.-)%-%d+$")
      binding = bindings.conditions_for(family, row.name, environment.mods)
      if row.name == "mir-k2-imersite-staged-state-1" or row.name == "mir-k2-imersite-continuation-state-4" then
        binding.preserve_identity, binding.space_gate = true, false
      end
    end
    local report = M.apply(row, binding, context)
    reports[index] = report
    if context.options["mir-debug-generation-report"] == true and type(environment.log) == "function" then
      environment.log("[more-infinite-research] " .. row.name .. ": "
        .. (report.enabled and "available" or "disabled") .. " (" .. report.reason .. ")")
    end
  end
  return reports, context
end

return M
