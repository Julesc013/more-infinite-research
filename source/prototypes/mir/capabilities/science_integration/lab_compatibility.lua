local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local function pack_production_status(...)
  local service = compiler_context.current():service("science.pack_production_status")
  if not service then error("MIR science pack-production service is not registered in CompilerContext.", 2) end
  return service(...)
end

local function pack_is_admitted(name)
  local status = pack_production_status(name)
  return status ~= "unreachable" and status ~= "not-admitted"
end

function M.ingredient_name(ingredient)
  if not ingredient then return nil end
  if type(ingredient) == "string" then return ingredient end
  return ingredient.name or ingredient[1]
end

function M.ingredient_amount(ingredient)
  if not ingredient or type(ingredient) == "string" then return 1 end
  return ingredient.amount or ingredient[2] or 1
end

local function policy()
  local value = effective_settings.get("mir-lab-incompatibility-policy")
  if value == "engine-default" then return "engine-default" end
  if value == "skip" then return "skip" end
  return "reduce"
end

-- Only the private bounded rejection projection supplies this observer. The
-- normal lab policy has no cap and retains its existing admission semantics.
local function diagnostic_visit(observer)
  if not observer then return true end
  if type(observer.is_stopped) == "function" and observer:is_stopped() then return false end
  if type(observer.reserve_visit) == "function" then return observer:reserve_visit(0) end
  return true
end

-- The lab acceptance vector is immutable for one compiler Context.  Keep it
-- private: public binding snapshots still cross their defensive-copy boundary.
-- `input_count` retains the diagnostic observer's former visit budget even
-- when a physical lab repeats an input name.
local function build_lab_acceptance_view()
  local labs = {}
  for name, lab in pairs(data_raw.prototypes("lab")) do
    local accepted, input_count = {}, 0
    for _, input in ipairs((lab and lab.inputs) or {}) do
      accepted[input] = true
      input_count = input_count + 1
    end
    labs[#labs + 1] = {name = name, accepted_inputs = accepted, input_count = input_count}
  end
  table.sort(labs, function(left, right) return left.name < right.name end)
  return labs
end

local function lab_acceptance_view()
  return compiler_context.current():state_view("approved_lab_acceptance_view", build_lab_acceptance_view)
end

local function lab_accepts_all(entry, packs, diagnostic_observer)
  for _ = 1, entry.input_count do
    if not diagnostic_visit(diagnostic_observer) then return false end
  end
  for _, pack in ipairs(packs or {}) do
    if not diagnostic_visit(diagnostic_observer) then return false end
    if not entry.accepted_inputs[pack] then return false end
  end
  return true
end

-- Laboratory admission consumes the common declared-reference graph.
-- There is no witness-producing fallback or per-item acquisition query.
local function lab_acquisition_available(lab_name, diagnostic_observer)
  if not diagnostic_visit(diagnostic_observer) then return false end
  local service = compiler_context.current():service("science.lab_binding_available")
  if not service then error("MIR approved lab-binding service is not registered in CompilerContext.", 2) end
  return service(lab_name)
end

local function unresolved_lab(reason)
  error("MIR approved laboratory binding is unresolved: " .. tostring(reason)
    .. ". Refusing to discard established research or invoke production discovery.", 3)
end

local function first_reason(current, reason)
  if reason and (not current or reason < current) then return reason end
  return current
end

local function accepting_lab(packs, diagnostic_observer, reachability_context)
  if not packs or #packs == 0 then return false end
  local unresolved
  for _, entry in ipairs(lab_acceptance_view()) do
    if not diagnostic_visit(diagnostic_observer) then return false end
    if lab_accepts_all(entry, packs, diagnostic_observer) then
      local available, reason = lab_acquisition_available(entry.name, diagnostic_observer, reachability_context)
      if available == true then return true end
      if available == nil then unresolved = first_reason(unresolved, reason or ("unresolved-lab:" .. entry.name)) end
    end
  end
  return false, unresolved
end

function M.any_lab_accepts_all(packs, diagnostic_observer, reachability_context)
  local accepted, reason = accepting_lab(packs, diagnostic_observer, reachability_context)
  if not accepted and reason and not diagnostic_observer then unresolved_lab(reason) end
  return accepted
end

local function accepting_ingredients(ingredients, diagnostic_observer, reachability_context)
  local packs = {}
  for _, ingredient in ipairs(ingredients or {}) do
    if not diagnostic_visit(diagnostic_observer) then return false end
    local name = M.ingredient_name(ingredient)
    if name then table.insert(packs, name) end
  end
  return accepting_lab(packs, diagnostic_observer, reachability_context)
end

function M.valid_research_ingredients(ingredients, diagnostic_observer, reachability_context)
  local accepted, reason = accepting_ingredients(ingredients, diagnostic_observer, reachability_context)
  if not accepted and reason and not diagnostic_observer then unresolved_lab(reason) end
  return accepted
end

local function required_set(required_packs)
  local out = {}
  for _, pack in ipairs(required_packs or {}) do out[pack] = true end
  return out
end

local function contains_required(ingredients, required)
  for pack, _ in pairs(required) do
    local found = false
    for _, ingredient in ipairs(ingredients or {}) do
      if M.ingredient_name(ingredient) == pack then found = true; break end
    end
    if not found then return false, pack end
  end
  return true
end

local function contains_phase_trigger(ingredients, alternatives)
  if not alternatives or #alternatives == 0 then return true end
  local acceptable = required_set(alternatives)
  for _, ingredient in ipairs(ingredients or {}) do
    if acceptable[M.ingredient_name(ingredient)] then return true end
  end
  return false
end

function M.best_lab_compatible_ingredients(ingredients, context, required_packs, required_any_packs)
  local required = required_set(required_packs)
  if not contains_phase_trigger(ingredients, required_any_packs) then return nil, "missing-phase-trigger" end
  local source_has_required, missing_required = contains_required(ingredients, required)
  if not source_has_required then
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology")
      .. " because required science pack " .. tostring(missing_required) .. " was not selected.")
    return nil, "missing-required"
  end
  if policy() == "engine-default" then
    local unchanged = deepcopy(ingredients or {})
    local reachable = #unchanged > 0
    for _, ingredient in ipairs(unchanged) do
      local pack_name = M.ingredient_name(ingredient)
      if not pack_name or not pack_is_admitted(pack_name) then
        reachable = false
        break
      end
    end
    if reachable then
      local accepted, reason = accepting_ingredients(unchanged)
      if accepted then return unchanged, "unchanged" end
      if reason then unresolved_lab(reason) end
    end
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology")
      .. " because engine-default lab policy forbids ingredient rewriting and the selected set is not safely researchable.")
    return nil, "invalid"
  end

  local source = {}
  for _, ingredient in ipairs(deepcopy(ingredients or {})) do
    local pack_name = M.ingredient_name(ingredient)
    if pack_name and pack_is_admitted(pack_name) then
      table.insert(source, ingredient)
    else
      log("[more-infinite-research] Excluding science pack " .. tostring(pack_name)
        .. " from " .. tostring(context or "unknown technology")
        .. " because it is not admitted by the approved science source policy.")
    end
  end
  if #source == 0 then return nil, "empty" end
  if not contains_phase_trigger(source, required_any_packs) then return nil, "phase-trigger-unreachable" end
  local reachable_has_required, unreachable_required = contains_required(source, required)
  if not reachable_has_required then
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology")
      .. " because required science pack " .. tostring(unreachable_required) .. " is unreachable.")
    return nil, "required-unreachable"
  end
  local accepted, unresolved = accepting_ingredients(source)
  if accepted then return source, "full" end
  if policy() == "skip" then
    if unresolved then unresolved_lab(unresolved) end
    log("[more-infinite-research] Skipping " .. tostring(context or "unknown technology")
      .. " because no lab accepts the full selected science-pack set and the lab incompatibility policy is skip.")
    return nil, "invalid"
  end

  local best, best_lab = nil, nil
  for _, entry in ipairs(lab_acceptance_view()) do
    local candidate = {}
    for _, ingredient in ipairs(source) do
      local name = M.ingredient_name(ingredient)
      if name and entry.accepted_inputs[name] then table.insert(candidate, {name, M.ingredient_amount(ingredient)}) end
    end
    local candidate_has_required = contains_required(candidate, required)
    if candidate_has_required and contains_phase_trigger(candidate, required_any_packs) and #candidate > 0 then
      local available, reason = lab_acquisition_available(entry.name)
      if available == true and (not best or #candidate > #best) then
        best, best_lab = candidate, entry.name
      elseif available == nil then
        unresolved = first_reason(unresolved, reason or ("unresolved-lab:" .. entry.name))
      end
    end
  end

  -- An unresolved accepting source cannot be treated as a disproved route to
  -- justify rewriting the requested science. A valid complete vector above
  -- already returns without letting a specialist lab veto it.
  if unresolved then unresolved_lab(unresolved) end
  if best then
    log("[more-infinite-research] Reduced science packs for " .. tostring(context or "unknown technology")
      .. " to a lab-compatible subset accepted by " .. best_lab .. ".")
    return best, "reduced"
  end
  log("[more-infinite-research] No lab can research the selected science packs for "
    .. tostring(context or "unknown technology") .. ".")
  return nil, "invalid"
end

return M
