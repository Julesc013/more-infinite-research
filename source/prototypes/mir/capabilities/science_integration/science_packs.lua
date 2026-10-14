-- One science integration path binds approved sources and validates finite
-- research/lab references. It never loads factory acquisition solvers.
local deepcopy = require("prototypes.mir.core.deepcopy")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local lab_compatibility = require("prototypes.mir.capabilities.science_integration.lab_compatibility")
local lab_bindings = require("prototypes.mir.capabilities.science_integration.lab_bindings")
local pack_bindings = require("prototypes.mir.capabilities.science_integration.pack_bindings")
local recipe_unlock_facts = require("prototypes.mir.capabilities.science_integration.recipe_unlock_facts")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local science_selection_policy = require("prototypes.mir.capabilities.science_integration.science_selection_policy")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local catalogue = require("prototypes.mir.streams.registry")

local S = {pack_registry = pack_registry, lab_compatibility = lab_compatibility,
  pack_bindings = pack_bindings, science_selection_policy = science_selection_policy}

local function index()
  return compiler_context.current():state_view("approved_research_bindings", function()
    return pack_bindings.compile_references(catalogue.shared, lab_bindings.snapshot())
  end)
end

local function source_for(pack_name)
  local bindings = index()
  local status, reason = pack_bindings.bound_pack_status(bindings, pack_name)
  if not status then
    error("MIR approved science binding is unresolved: " .. tostring(pack_name) .. " (" .. tostring(reason)
      .. "). No research was removed and the former solver will not be invoked.", 2)
  end
  return bindings.packs[pack_name]
end

local function production_status(pack_name)
  if not pack_registry.science_pack_exists(pack_name) then return "unreachable", nil end
  local source = source_for(pack_name)
  return source.status, source.unlocker
end

local function prerequisites(pack_name)
  return deepcopy(source_for(pack_name).unlockers)
end

local function researchability_reason(technology_name)
  local bindings = index()
  local reason = pack_bindings.bound_technology_reason(bindings, technology_name)
  if reason and string.find(reason, "unresolved-approved-research-dependencies:", 1, true) == 1 then
    error("MIR approved research binding is unresolved: " .. tostring(technology_name)
      .. ". Refusing to discard established research or enter production discovery.", 2)
  end
  return reason
end

function S.ensure_services(context)
  context = context or compiler_context.current()
  if context:has_service("science.approved_binding_index") then return context end
  local services = {
    ["science.pack_production_status"] = production_status,
    ["science.prereq_techs_for_science_pack"] = prerequisites,
    ["science.prereq_tech_for_science_pack"] = function(pack_name)
      local gates = prerequisites(pack_name)
      return #gates == 1 and gates[1] or nil
    end,
    ["science.technology_researchability_reason"] = researchability_reason,
    ["science.lab_binding_available"] = function(name)
      return pack_bindings.bound_lab_available(index(), name)
    end
  }
  for name, callback in pairs(services) do
    if not context:has_service(name) then context:set_service(name, callback) end
  end
  context:set_service("science.approved_binding_index", index)
  return context
end

local function ready(callback)
  return function(...)
    S.ensure_services(compiler_context.current())
    return callback(...)
  end
end

S.all_lab_inputs = pack_registry.all_lab_inputs
S.science_pack_exists = pack_registry.science_pack_exists
S.native_pack_name = pack_registry.native_pack_name
S.pack_list_all = pack_registry.pack_list_all
S.pack_list_official = pack_registry.pack_list_official
S.is_official_science_pack = pack_registry.is_official_science_pack
S.any_lab_accepts_all = ready(lab_compatibility.any_lab_accepts_all)
S.valid_research_ingredients = ready(lab_compatibility.valid_research_ingredients)
S.best_lab_compatible_ingredients = ready(lab_compatibility.best_lab_compatible_ingredients)
S.space_age_progression_packs_for = science_selection_policy.space_age_progression_packs_for
S.official_progression_packs_for = science_selection_policy.official_progression_packs_for
S.mod_progression_packs_for = ready(science_selection_policy.mod_progression_packs_for)
S.end_game_science_pack = science_selection_policy.end_game_science_pack
S.pack_list_for_extension = science_selection_policy.pack_list_for_extension
S.pack_production_status = ready(production_status)
S.prereq_techs_for_science_pack = ready(prerequisites)
S.prereq_tech_for_science_pack = ready(function(pack_name)
  local gates = prerequisites(pack_name)
  return #gates == 1 and gates[1] or nil
end)
S.production_route_for_pack = ready(function(pack_name) return deepcopy(source_for(pack_name)) end)
S.researchable_unlockers_for_recipe = ready(function(recipe_name)
  local fact = recipe_facts.view(recipe_name)
  if not fact or fact.enabled_without_research == true then return {} end
  local out = {}
  for _, name in ipairs(recipe_unlock_facts.unlockers_for_recipe(recipe_name)) do
    if not researchability_reason(name) then out[#out + 1] = name end
  end
  return out
end)
S.technology_researchability_reason = ready(researchability_reason)
S.technology_is_researchable = ready(function(name) return researchability_reason(name) == nil end)
S.technology_is_enabled_and_reachable = ready(function(name)
  return pack_bindings.bound_technology_reason(index(), name) == nil
end)
S.binding_snapshot = ready(function() return deepcopy(index()) end)

return S
