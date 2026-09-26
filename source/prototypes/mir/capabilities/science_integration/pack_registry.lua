local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

local VANILLA_PACK_ORDER = {
  "automation-science-pack",
  "logistic-science-pack",
  "chemical-science-pack",
  "production-science-pack",
  "military-science-pack",
  "utility-science-pack",
  "space-science-pack",
  "agricultural-science-pack",
  "metallurgic-science-pack",
  "electromagnetic-science-pack",
  "cryogenic-science-pack",
  "promethium-science-pack"
}

function M.research_pack_prototype(name)
  -- Target profiles describe known engine shapes; they do not decide whether
  -- a particular ecosystem's lab input is research consumable.  Factorio
  -- exposes the concrete item through the platform lookup, while the lab
  -- input relation below is the authoritative research-use admission.
  return lookup.item_prototype(name)
end

-- The optional observer is supplied only by the query-local rejection
-- projection. Normal pack admission remains uncapped and uses this exact same
-- lab/input definition.
local function diagnostic_visit(observer)
  if not observer then return true end
  if type(observer.is_stopped) == "function" and observer:is_stopped() then return false end
  if type(observer.reserve_visit) == "function" then return observer:reserve_visit(0) end
  return true
end

local function lab_input_index(diagnostic_observer)
  local context = compiler_context.current()
  local lab_inputs_cache = context:state_view("lab_input_index")
  if lab_inputs_cache then return lab_inputs_cache end
  local out, seen = {}, {}
  for _, lab in pairs(data_raw.prototypes("lab")) do
    if not diagnostic_visit(diagnostic_observer) then break end
    for _, input in ipairs(lab.inputs or {}) do
      if not diagnostic_visit(diagnostic_observer) then break end
      if not seen[input] and M.research_pack_prototype(input) then
        seen[input] = true
        table.insert(out, input)
      end
    end
  end
  table.sort(out)
  context:set_state("lab_input_index", out)
  return out
end

function M.all_lab_inputs(diagnostic_observer)
  return deepcopy(lab_input_index(diagnostic_observer))
end

function M.science_pack_exists(name, diagnostic_observer)
  if not M.research_pack_prototype(name) then return false end
  if not diagnostic_observer then
    local inputs = lab_input_index()
    local context = compiler_context.current()
    local source_epoch = context:state_epoch("lab_input_index")
    local membership = context:state_view("lab_input_membership")
    if not membership or membership.source_epoch ~= source_epoch then
      local names = {}
      for _, input in ipairs(inputs) do names[input] = true end
      local next_membership = {source_epoch = source_epoch, names = names}
      if membership then
        context:replace_epoch("lab_input_membership", next_membership)
      else
        context:set_state("lab_input_membership", next_membership)
      end
      membership = next_membership
    end
    -- Repeated root queries need only membership, not a copied sorted list.
    -- The context and index epoch own this cache. Physical existence above
    -- and the observer's original visit accounting below remain live checks.
    return membership.names[name] == true
  end
  for _, input in ipairs(M.all_lab_inputs(diagnostic_observer)) do
    if not diagnostic_visit(diagnostic_observer) then return false end
    if input == name then return true end
  end
  return false
end

function M.official_order()
  return deepcopy(VANILLA_PACK_ORDER)
end

function M.ordered_pack_list_from_set(set)
  local remaining = {}
  for pack, enabled in pairs(set or {}) do
    if enabled then remaining[pack] = true end
  end

  local out = {}
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if remaining[pack] then
      table.insert(out, pack)
      remaining[pack] = nil
    end
  end

  local extra = {}
  for pack, _ in pairs(remaining) do table.insert(extra, pack) end
  table.sort(extra)
  for _, pack in ipairs(extra) do table.insert(out, pack) end
  return out
end

function M.pack_list_all()
  local available = {}
  for _, pack in ipairs(M.all_lab_inputs()) do available[pack] = true end
  return M.ordered_pack_list_from_set(available)
end

function M.pack_list_official()
  local available = {}
  for _, pack in ipairs(M.all_lab_inputs()) do available[pack] = true end
  local out = {}
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if available[pack] then table.insert(out, pack) end
  end
  return out
end

function M.is_official_science_pack(name)
  for _, pack in ipairs(VANILLA_PACK_ORDER) do
    if pack == name then return true end
  end
  return false
end

return M
