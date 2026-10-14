local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local researchability_index = require("prototypes.mir.graph.researchability_index")
local recipe_semantics = require("prototypes.mir.domain.facts.recipe_semantics")
local prototype_lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")

local M = {}

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do if value == wanted then return true end end
  return false
end

local function structural_index()
  return compiler_context.current():state_view("technology_researchability_index", researchability_index.build)
end

local function technology_reason(name)
  local technology = data_raw.technology(name)
  if not technology then return "missing-technology:" .. tostring(name) end
  if technology.enabled == false then return "disabled-technology:" .. name end
  return structural_index().structural_failures[name] or nil
end

local function outputs_pack(fact, pack_name)
  local variants = (fact and fact.variants) or {}
  if #variants == 0 then return false end
  for _, variant in ipairs(variants) do
    local possible = false
    for _, output in ipairs(variant.results or {}) do
      if output.type == "item" and output.name == pack_name
        and recipe_semantics.possible_item_result(output) then possible = true; break end
    end
    if not possible then return false end
  end
  return true
end

local function binding(pack_name, declaration, reference_only)
  if not pack_registry.science_pack_exists(pack_name) then
    return nil, "not-a-lab-input:" .. tostring(pack_name)
  end
  if type(declaration) ~= "table" or declaration.pack ~= pack_name
    or type(declaration.recipe) ~= "string" then
    return nil, "missing-approved-pack-declaration:" .. tostring(pack_name)
  end
  local fact = recipe_facts.view(declaration.recipe)
  if not fact then return nil, "missing-approved-pack-recipe:" .. declaration.recipe end
  if not outputs_pack(fact, pack_name) then
    return nil, "approved-pack-recipe-output-mismatch:" .. declaration.recipe
  end
  local out = {
    pack_name = pack_name,
    recipe_name = declaration.recipe,
    binding_id = "approved-pack/" .. pack_name,
    source_kind = "declared-recipe",
    unlockers = {},
    ingredient_packs = {},
    -- This record validates the approved source references. It is not an
    -- acquisition proof and must never be published as one.
    acquisition_proof = false
  }
  for _, ingredient in ipairs(fact.ingredient_identities or {}) do
    if ingredient.type == "item" and pack_registry.science_pack_exists(ingredient.name) then
      out.ingredient_packs[#out.ingredient_packs + 1] = ingredient.name
    end
  end
  if declaration.allow_initial == true and fact.enabled_without_research == true then
    out.status, out.initial = "initial", true
    return out
  end
  local gate = declaration.technology
  if type(gate) ~= "string" or not contains(recipe_unlocks.for_recipe(declaration.recipe), gate) then
    return nil, "approved-pack-unlock-mismatch:" .. declaration.recipe
  end
  local reason = technology_reason(gate)
  if reason then return nil, reason end
  local technology = data_raw.technology(gate)
  for _, ingredient in ipairs(((technology.unit or {}).ingredients) or {}) do
    if (ingredient.name or ingredient[1]) == pack_name and not reference_only then
      return nil, "approved-pack-gate-self-lock:" .. gate
    end
  end
  out.status, out.initial, out.unlocker = "research", false, gate
  out.unlockers[1] = gate
  return out
end

-- Bind exactly the approved source. Later alternative producers neither
-- trigger exploration nor replace the declaration's progression decision.
-- A failed binding is explicit and never invokes the former route solver.
function M.bind(pack_name, declaration)
  local result, reason = binding(pack_name, declaration)
  return result and deepcopy(result) or nil, reason
end

function M.declaration_for_role(role, declarations)
  local declared = (declarations or {})[role]
  if not declared then return nil end
  local out = deepcopy(declared)
  out.pack = pack_registry.native_pack_name(role)
  out.recipe = pack_registry.native_pack_name(out.recipe)
  out.technology = pack_registry.native_pack_name(out.technology)
  return out
end

function M.technology_structural_reason(name)
  return technology_reason(name)
end

local function positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function has_item_output(entries, wanted)
  for _, entry in ipairs(entries or {}) do
    if type(entry) == "table" and (entry.type or "item") == "item"
      and (entry.name or entry[1] or entry.item) == wanted and recipe_semantics.possible_item_result(entry) then
      return true
    end
  end
  return false
end

-- This is a declaration of the published admission policy, not a claim that
-- Factorio cannot supply the pack. In particular, do not silently correct the
-- old rocket inventory guard and thereby change existing research science.
-- Positive/unfamiliar native cases remain explicit until separately approved.
local function retained_launch_exclusion(pack_name, policy)
  if not policy or pack_name ~= pack_registry.native_pack_name(policy.pack) then return nil end
  local payload = prototype_lookup.item_prototype(policy.payload)
  local products = payload and (payload.rocket_launch_products
    or (payload.rocket_launch_product and {payload.rocket_launch_product}))
  if not has_item_output(products, pack_name) then return nil end
  -- A non-launch native producer is relevant new input. Do not pretend the
  -- old launch exclusion proves that producer unavailable.
  for kind, prototypes in pairs(data_raw.raw()) do
    if kind ~= "recipe" then
      for _, prototype in pairs(prototypes) do
        local minable = prototype.minable or {}
        if minable.result == pack_name or has_item_output(minable.results, pack_name)
          or has_item_output(prototype.loot, pack_name)
          or prototype.spoil_result == pack_name or prototype.burnt_result == pack_name then
          return nil
        end
      end
    end
  end
  local line = target_profiles.current_factorio_version
  local reason = "published-native-launch-contract-not-supported-on-target"
  if line == "2.0" or line == "2.1" then
    if payload.send_to_orbit_mode ~= "manual" and payload.send_to_orbit_mode ~= "automated" then
      reason = "published-native-launch-mode-not-admitted"
    else
      local receiver = false
      for _, pad in pairs(data_raw.prototypes("cargo-landing-pad")) do
        if positive(pad.inventory_size) then receiver = true; break end
      end
      for _, silo in pairs(data_raw.prototypes("rocket-silo")) do
        local rocket = data_raw.prototypes("rocket-silo-rocket")[silo.rocket_entity]
        if receiver and type(silo.fixed_recipe) == "string" and silo.fixed_recipe ~= "" and rocket
          and silo.launch_to_space_platforms ~= true and positive(silo.to_be_inserted_to_rocket_inventory_size)
          and positive(rocket.inventory_size) and positive(silo.crafting_speed)
          and positive(silo.rocket_parts_required) and silo.rocket_parts_required % 1 == 0 then
          return nil -- A possible positive route needs an approved binding.
        end
      end
      reason = "published-native-launch-required-structure-not-admitted"
    end
  end
  return {pack_name = pack_name, binding_id = "retained-launch-policy/" .. pack_name,
    status = "not-admitted", initial = false, unlockers = {}, ingredient_packs = {},
    source_kind = "retained-published-native-launch-policy", policy_reason = reason, acquisition_proof = false}
end

local function declared_source(pack_name, shared)
  local declarations = shared.science_bindings or {}
  local declared_roles = {}
  for role in pairs(declarations) do declared_roles[#declared_roles + 1] = role end
  table.sort(declared_roles)
  for _, role in ipairs(declared_roles) do
    local declaration = M.declaration_for_role(role, declarations)
    if declaration and declaration.pack == pack_name then
      local result, reason = binding(pack_name, declaration, true)
      if result then return result end
      -- A different actual unlock may be admitted only by the separately
      -- authored unique-owner rule below, never by production exploration.
      if not (shared.science_binding_policy or {}).unique_direct_unlock then return nil, reason end
      break
    end
  end
  if not (shared.science_binding_policy or {}).named_pack_recipe then
    return nil, "missing-approved-pack-declaration:" .. pack_name
  end
  local recipe_name = pack_name
  local fact = recipe_facts.view(recipe_name)
  if not fact or not outputs_pack(fact, pack_name) then
    if not (shared.science_binding_policy or {}).unique_direct_recipe then
      return nil, "missing-approved-named-pack-source:" .. pack_name
    end
    -- An approved parameterized rule may bind one actual typed producer with
    -- an unfamiliar name. Ambiguity is explicit; it never starts a competing
    -- route search or chooses an alternative by traversal order.
    local producers = recipe_facts.recipes_by_output_identity_view("item", pack_name)
    if #producers == 0 then
      local excluded = retained_launch_exclusion(pack_name, (shared.science_binding_policy or {}).retained_launch_source)
      if excluded then return excluded end
      return nil, "missing-approved-pack-source:" .. pack_name
    end
    if #producers ~= 1 then return nil, "ambiguous-approved-pack-source:" .. pack_name end
    recipe_name = producers[1]
    fact = recipe_facts.view(recipe_name)
    if not outputs_pack(fact, pack_name) then
      return nil, "approved-pack-recipe-output-mismatch:" .. recipe_name
    end
  end
  local gates = {}
  if fact.enabled_without_research ~= true then
    for _, name in ipairs(recipe_unlocks.for_recipe(recipe_name)) do
      if not technology_reason(name) then gates[#gates + 1] = name end
    end
    if #gates ~= 1 then return nil, "ambiguous-approved-pack-unlock:" .. pack_name end
  end
  return binding(pack_name, {pack = pack_name, recipe = recipe_name, technology = gates[1], allow_initial = true}, true)
end

-- Positive reference rules validate only declared pack sources, direct lab
-- placement sources and research units/prerequisites. Each established fact
-- is propagated once. No rule recursively acquires a material, machine,
-- power source or surface, and no complete production proof is constructed.
local function propagate(rules, unknown_sources, native_source_guard)
  local facts, watchers, queue, edge_count = {}, {}, {}, 0
  local function establish(name)
    if not facts[name] then facts[name] = true; queue[#queue + 1] = name end
  end
  for _, rule in ipairs(rules) do
    local seen = {}
    rule.pending = 0
    for _, dependency in ipairs(rule.requires) do
      if not seen[dependency] then
        seen[dependency] = true
        rule.pending = rule.pending + 1
        edge_count = edge_count + 1
        watchers[dependency] = watchers[dependency] or {}
        watchers[dependency][#watchers[dependency] + 1] = rule
      end
    end
    if rule.pending == 0 then establish(rule.result) end
  end
  local cursor, notifications = 1, 0
  while cursor <= #queue do
    local name = queue[cursor]
    cursor = cursor + 1
    for _, rule in ipairs(watchers[name] or {}) do
      notifications = notifications + 1
      rule.pending = rule.pending - 1
      if rule.pending == 0 then establish(rule.result) end
    end
  end
  -- Completion of a finite positive rule set distinguishes closed unseeded
  -- references from unsupported inputs. Reuse the reverse index to propagate
  -- possible unknown influence, conservatively across either AND/OR branch.
  -- A proven positive always wins over an unknown alternative.
  local unknown, unknown_queue, unknown_notifications = {}, {}, 0
  local function mark_unknown(name)
    if not facts[name] and not unknown[name] then
      unknown[name] = true; unknown_queue[#unknown_queue + 1] = name
    end
  end
  for name in pairs(unknown_sources or {}) do mark_unknown(name) end
  cursor = 1
  local function drain_unknown()
    while cursor <= #unknown_queue do
      local name = unknown_queue[cursor]; cursor = cursor + 1
      for _, rule in ipairs(watchers[name] or {}) do
        unknown_notifications = unknown_notifications + 1
        mark_unknown(rule.result)
      end
    end
  end
  drain_unknown()
  -- Native-source inspection is unnecessary when references already resolve
  -- positively or remain unknown. Only a proposed closed negative needs it.
  local native_visits = 0
  if native_source_guard then
    local guarded_sources, visits = native_source_guard(facts, unknown)
    native_visits = visits
    for name in pairs(guarded_sources) do mark_unknown(name) end
    drain_unknown()
  end
  return facts, {rules = #rules, dependency_edges = edge_count, facts = #queue,
    dependency_notifications = notifications, unknown_facts = #unknown_queue,
    unknown_dependency_notifications = unknown_notifications, native_source_prototype_visits = native_visits,
    factory_acquisition_calls = 0}, unknown
end

local function node(kind, name)
  return kind .. ":" .. tostring(name)
end

local function sorted_names(values)
  local names = {}
  for name in pairs(values or {}) do names[#names + 1] = name end
  table.sort(names)
  return names
end

local function ingredient_names(ingredients)
  local names, seen = {}, {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = ingredient.name or ingredient[1]
    if name and not seen[name] then names[#names + 1] = name; seen[name] = true end
  end
  table.sort(names)
  return names
end

local function accepts(lab, names)
  local accepted = {}
  for _, name in ipairs(lab.inputs or {}) do accepted[name] = true end
  for _, name in ipairs(names) do if not accepted[name] then return false end end
  return true
end

-- A non-recipe source may supply a seed outside the approved recipe fragment.
-- Record that possibility once for the relevant pack names; never reconstruct
-- acquisition proofs or certify that the native source is itself obtainable.
local function possible_native_pack_sources(pack_names)
  local wanted, possible, visits = {}, {}, 0
  for _, name in ipairs(pack_names) do wanted[name] = true end
  local function products(entries)
    for _, entry in ipairs(entries or {}) do
      if type(entry) == "table" and (entry.type or "item") == "item" then
        local name = entry.name or entry[1] or entry.item
        if wanted[name] and recipe_semantics.possible_item_result(entry) then possible[name] = true end
      end
    end
  end
  for kind, prototypes in pairs(data_raw.raw()) do
    if kind ~= "recipe" then
      for _, prototype in pairs(prototypes) do
        visits = visits + 1
        local minable = prototype.minable or {}
        if wanted[minable.result] and minable.count ~= 0 and minable.result_count ~= 0 then
          possible[minable.result] = true
        end
        products(minable.results)
        products(prototype.loot)
        products(prototype.rocket_launch_products)
        if prototype.rocket_launch_product then products({prototype.rocket_launch_product}) end
        if wanted[prototype.spoil_result] then possible[prototype.spoil_result] = true end
        if wanted[prototype.burnt_result] then possible[prototype.burnt_result] = true end
      end
    end
  end
  return possible, visits
end

local function build_reference_bindings(shared, labs)
  local result = {packs = {}, issues = {}, labs = labs, lab_names = {}, unavailable_labs = {},
    technologies = {}, rules = {}}
  local unknown_sources = {}
  local function add(kind, name, required)
    result.rules[#result.rules + 1] = {result = node(kind, name), requires = required}
  end
  local pack_names = pack_registry.pack_list_all()
  for _, pack in ipairs(pack_names) do
    local source, reason = declared_source(pack, shared)
    result.packs[pack], result.issues[pack] = source, reason
    if not source then unknown_sources[node("pack", pack)] = true end
    if source and source.status == "not-admitted" then result.has_policy_exclusions = true end
    if source and source.status ~= "not-admitted" then
      -- A failed approved source cannot prove absence when another raw
      -- producer might supply a seed. No search or ranking is performed.
      if #recipe_facts.recipes_by_output_identity_view("item", pack) > 1 then
        unknown_sources[node("pack", pack)] = true
      end
      local required = {}
      for _, gate in ipairs(source.unlockers) do required[#required + 1] = node("technology", gate) end
      for _, ingredient in ipairs(source.ingredient_packs) do required[#required + 1] = node("pack", ingredient) end
      add("pack", pack, required)
    end
  end
  for _, lab in ipairs(labs) do
    result.lab_names[lab.name] = true
    if #(lab.sources or {}) == 0 then unknown_sources[node("lab", lab.name)] = true end
    for _, source in ipairs(lab.sources or {}) do
      local required = {}
      for _, pack in ipairs(source.ingredient_packs or {}) do required[#required + 1] = node("pack", pack) end
      if source.initial then
        add("lab", lab.name, required)
      else
        for _, gate in ipairs(source.unlockers or {}) do
          local dependencies = deepcopy(required)
          dependencies[#dependencies + 1] = node("technology", gate)
          add("lab", lab.name, dependencies)
        end
      end
    end
  end
  local technologies = data_raw.prototypes("technology")
  local accepting_labs_by_vector = {}
  for _, name in ipairs(sorted_names(technologies)) do
    local technology = technologies[name]
    local reason = technology_reason(name)
    result.technologies[name] = reason or false
    if not reason then
      local required = {}
      for _, prerequisite in ipairs(technology.prerequisites or {}) do
        required[#required + 1] = node("technology", prerequisite)
      end
      if technology.research_trigger then
        add("technology", name, required)
      else
        local unit = technology.unit
        local names = ingredient_names(unit and unit.ingredients)
        if not unit or #names == 0 or (unit.count == nil and unit.count_formula == nil) then
          result.technologies[name] = "missing-research-mechanism"
        else
          for _, pack in ipairs(names) do required[#required + 1] = node("pack", pack) end
          local vector = table.concat(names, "\0")
          local accepting = accepting_labs_by_vector[vector]
          if not accepting then
            accepting = {}
            for _, lab in ipairs(labs) do
              if accepts(lab, names) then
                accepting[#accepting + 1] = lab.name
                add("lab-vector", vector, {node("lab", lab.name)})
              end
            end
            accepting_labs_by_vector[vector] = accepting
          end
          -- Share the OR of real accepting labs across every technology using
          -- this vector. Do not copy its entire prerequisite list per lab.
          required[#required + 1] = node("lab-vector", vector)
          add("technology", name, required)
          if #accepting == 0 then result.technologies[name] = "no-accepting-lab" end
        end
      end
    end
  end
  local unknown
  result.facts, result.work, unknown = propagate(result.rules, unknown_sources, function(facts, unresolved)
    local candidates = {}
    for pack, source in pairs(result.packs) do
      local key = node("pack", pack)
      if source.status ~= "not-admitted" and not facts[key] and not unresolved[key] then
        candidates[#candidates + 1] = pack
      end
    end
    if #candidates == 0 then return {}, 0 end
    local native, visits = possible_native_pack_sources(candidates)
    local guarded = {}
    for pack in pairs(native) do guarded[node("pack", pack)] = true end
    return guarded, visits
  end)
  -- Retain the separately declared published launch exclusion. Completed
  -- reference cycles are classified below; unsupported sources stay unknown.
  if result.has_policy_exclusions then
    local blocked, reverse, queue = {}, {}, {}
    local function block(name, reason)
      if not blocked[name] then
        blocked[name] = reason
        if result.technologies[name] == false then result.technologies[name] = reason end
        queue[#queue + 1] = name
      end
    end
    for _, name in ipairs(sorted_names(technologies)) do
      local technology = technologies[name]
      for _, prerequisite in ipairs(technology.prerequisites or {}) do
        reverse[prerequisite] = reverse[prerequisite] or {}
        reverse[prerequisite][#reverse[prerequisite] + 1] = name
      end
      for _, pack in ipairs(ingredient_names(not technology.research_trigger and (technology.unit or {}).ingredients)) do
        if result.packs[pack] and result.packs[pack].status == "not-admitted" then
          block(name, "science-excluded-by-published-policy:" .. pack)
          break
        end
      end
    end
    local cursor, notifications = 1, 0
    while cursor <= #queue do
      local name = queue[cursor]; cursor = cursor + 1
      for _, dependent in ipairs(reverse[name] or {}) do
        notifications = notifications + 1
        block(dependent, blocked[name])
      end
    end
    result.work.policy_exclusion_technologies = #queue
    result.work.policy_exclusion_notifications = notifications
  end
  -- This is a completed closed-reference result, not a pending recursion or
  -- factory-impossibility proof. Unknown inputs and unexamined alternative
  -- pack producers remain unresolved rather than becoming exclusions.
  local closed_exclusions = 0
  for name, source in pairs(result.packs) do
    local key = node("pack", name)
    if source.status ~= "not-admitted" and not result.facts[key] and not unknown[key] then
      source.status = "not-admitted"
      source.policy_reason = "unseeded-approved-reference-dependencies"
      source.reference_policy_exclusion = true
      closed_exclusions = closed_exclusions + 1
    end
  end
  for name, reason in pairs(result.technologies) do
    local key = node("technology", name)
    if reason == false and not result.facts[key] and not unknown[key] then
      result.technologies[name] = "unseeded-approved-reference-dependencies:" .. name
    end
  end
  for name in pairs(result.lab_names) do
    local key = node("lab", name)
    if not result.facts[key] and not unknown[key] then result.unavailable_labs[name] = true end
  end
  result.work.closed_reference_pack_exclusions = closed_exclusions
  if closed_exclusions > 0 then result.has_policy_exclusions = true end
  -- Rule counters are sufficient for ordinary metadata. Do not retain the
  -- reverse propagation graph or expanded explanation inventories.
  result.rules = nil
  return result
end

function M.compile_references(shared, labs)
  return build_reference_bindings(shared, labs)
end

function M.bound_pack_status(index, pack_name)
  local source = index.packs[pack_name]
  if not source then return nil, index.issues[pack_name] or ("missing-approved-pack-source:" .. tostring(pack_name)) end
  if source.status == "not-admitted" then return source.status, nil end
  if not index.facts[node("pack", pack_name)] then return nil, "unresolved-approved-pack-dependencies:" .. pack_name end
  return source.status, source.unlocker
end

function M.bound_technology_reason(index, technology_name)
  if index.technologies[technology_name] == nil then return "missing" end
  if index.facts[node("technology", technology_name)] then return nil end
  return index.technologies[technology_name] or ("unresolved-approved-research-dependencies:" .. tostring(technology_name))
end

function M.bound_lab_available(index, lab_name)
  if index.facts[node("lab", lab_name)] then return true end
  if index.unavailable_labs[lab_name] then return false end
  if index.lab_names[lab_name] then return nil, "unresolved-approved-lab-dependencies:" .. lab_name end
  return false
end

return M
