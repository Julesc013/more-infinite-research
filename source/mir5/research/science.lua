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

local function policy_ingredients(source, binding, context, selected, view)
  local policy = option(context, "mir-science-pack-ingredient-policy", POLICY_DEFAULT)
  if not VALID_POLICIES[policy] then policy = POLICY_DEFAULT end
  local out, seen, added, added_seen = {}, {}, {}, {}
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

  local function add_if_available(name)
    if view.available[name] and not seen[name] then
      append(out, seen, name, 1)
      append_name(added, added_seen, name)
    end
  end
  if policy == "space" then
    add_if_available(selected.space)
  elseif policy == "space-and-promethium" then
    add_if_available(selected.space)
    add_if_available("promethium-science-pack")
  elseif policy == "space-age-progression" then
    local names = {}
    for _, row in ipairs(source) do names[row[1]] = true end
    local planets = {"agricultural-science-pack", "metallurgic-science-pack", "electromagnetic-science-pack", "cryogenic-science-pack"}
    local has_planet = names["promethium-science-pack"] == true
    for _, name in ipairs(planets) do has_planet = has_planet or names[name] == true end
    if has_planet then add_if_available(selected.space) end
    if names["promethium-science-pack"] then
      for _, name in ipairs(planets) do add_if_available(name) end
      add_if_available("promethium-science-pack")
    end
  elseif policy == "official-progression" then
    for _, row in ipairs(source) do
      for _, name in ipairs(selected.progression[row[1]] or {}) do add_if_available(name) end
    end
  elseif policy == "mod-progression" then
    -- A caller may supply an approved finite binding for a known external
    -- pack. Unknown packs deliberately retain their original vector instead
    -- of starting the retired unlock/acquisition solver.
    for _, row in ipairs(source) do
      local additions = type(binding.mod_progression) == "table" and binding.mod_progression[row[1]] or nil
      if additions then
        for _, name in ipairs(additions) do add_if_available(name) end
      elseif not selected.official_set[row[1]] then
        context.mod_progression_unbound[row[1]] = true
      end
    end
  elseif policy == "all-official" then
    for _, name in ipairs(selected.official) do add_if_available(name) end
  elseif policy == "all" then
    -- The shipped registry ordered native official roles before arbitrary
    -- lab inputs. Preserve that deterministic order without treating an
    -- external input as a newly official science role.
    for _, name in ipairs(selected.official) do add_if_available(name) end
    for _, name in ipairs(view.all) do add_if_available(name) end
  end
  return out, policy, added
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

local function merge_prerequisites(source, additions)
  local out, seen = {}, {}
  for _, name in ipairs(source or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] then seen[name] = true; out[#out + 1] = name end
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
local function policy_prerequisites(raw, selected, additions)
  local out, seen = {}, {}
  for _, pack in ipairs(additions or {}) do
    for _, prerequisite in ipairs((selected.pack_prerequisites or {})[pack] or {}) do
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

function M.prepare(environment)
  environment = environment or {}
  return {
    raw = environment.raw or {}, options = environment.options or {}, target = environment.target or {}, mods = environment.mods,
    lab_visits = 0, mod_progression_unbound = {}
  }
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

  local required = copy_list(binding.required_science)
  for _, name in ipairs(required) do
    if not item_exists(raw, name) then return disable(technology, "missing-required-science:" .. name, source) end
  end
  local ingredients, policy, additions = policy_ingredients(source, binding, context, selected, view)
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

  local policy_prereqs, prerequisite_reason = policy_prerequisites(raw, selected, additions)
  if not policy_prereqs then return disable(technology, prerequisite_reason, source) end
  local prerequisites = merge_prerequisites(technology.prerequisites, policy_prereqs)
  if option(context, "ips-require-space-gate", false) == true and binding.space_gate ~= false then
    local gate = selected.end_game
    if not gate then return disable(technology, "missing-end-game-gate", ingredients, prerequisites) end
    if not item_exists(raw, gate.pack) then return disable(technology, "missing-end-game-science:" .. gate.pack, ingredients, prerequisites) end
    for _, name in ipairs(gate.prerequisites) do
      if not technology_exists(raw, name) then
        return disable(technology, "missing-end-game-gate-prerequisite:" .. name, ingredients, prerequisites)
      end
    end
    prerequisites = merge_prerequisites(prerequisites, gate.prerequisites)
  end

  local compatible = false
  for _, lab in ipairs(view.labs) do
    if accepts(lab, ingredients) and contains_all(ingredients, required)
      and contains_one(ingredients, phase_any) then
      compatible = true
      break
    end
  end
  local lab_policy = option(context, "mir-lab-incompatibility-policy", LAB_DEFAULT)
  if lab_policy ~= "skip" and lab_policy ~= "engine-default" then lab_policy = LAB_DEFAULT end
  if compatible then
    technology.unit.ingredients, technology.prerequisites = ingredients, prerequisites
    return {enabled = technology.enabled ~= false, reason = policy == POLICY_DEFAULT and "configured" or policy,
      ingredients = ingredients, prerequisites = prerequisites}
  end
  if lab_policy ~= "reduce" then
    return disable(technology, "lab-incompatible-" .. lab_policy, ingredients, prerequisites)
  end

  local best
  for _, lab in ipairs(view.labs) do
    local candidate = {}
    for _, row in ipairs(ingredients) do if lab.accepted[row[1]] then candidate[#candidate + 1] = {row[1], row[2]} end end
    if #candidate > 0 and contains_all(candidate, required) and contains_one(candidate, phase_any)
      and (not best or #candidate > #best) then best = candidate end
  end
  if not best then return disable(technology, "lab-incompatible-reduce", ingredients, prerequisites) end
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
      binding = bindings.conditions_for(family)
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
