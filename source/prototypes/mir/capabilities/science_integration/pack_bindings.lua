local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local researchability_index = require("prototypes.mir.graph.researchability_index")

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
  for _, output in ipairs((fact and fact.result_identities) or {}) do
    if output.type == "item" and output.name == pack_name
      and type(output.amount) == "number" and output.amount > 0 then return true end
  end
  return false
end

local function binding(pack_name, declaration)
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
    -- This record validates the approved source references. It is not an
    -- acquisition proof and must never be published as one.
    acquisition_proof = false
  }
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
    if (ingredient.name or ingredient[1]) == pack_name then
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

return M
