local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
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


local function allowed_science_pack_prototype_kinds()
  local profile = target_profiles.current()
  local shapes = profile and profile.prototype_shapes or nil
  local declared_kinds = shapes and shapes.science_pack_prototype_kinds or nil
  if type(declared_kinds) ~= "table" or #declared_kinds == 0 then
    error("MIR target profile does not declare science-pack prototype kinds.", 2)
  end

  local allowed = {}
  for _, kind in ipairs(declared_kinds) do
    if type(kind) ~= "string" or kind == "" then
      error("MIR target profile declares an invalid science-pack prototype kind.", 2)
    end
    allowed[kind] = true
  end
  return allowed
end

function M.research_pack_prototype(name)
  local prototype = lookup.item_prototype(name)
  if not prototype then return nil end
  if not allowed_science_pack_prototype_kinds()[prototype.type] then return nil end
  return prototype
end

function M.all_lab_inputs()
  local context = compiler_context.current()
  local lab_inputs_cache = context:state_view("lab_input_index")
  if lab_inputs_cache then return deepcopy(lab_inputs_cache) end
  local out, seen = {}, {}
  for _, lab in pairs(data_raw.prototypes("lab")) do
    for _, input in ipairs(lab.inputs or {}) do
      if not seen[input] and M.research_pack_prototype(input) then
        seen[input] = true
        table.insert(out, input)
      end
    end
  end
  table.sort(out)
  context:set_state("lab_input_index", out)
  return deepcopy(out)
end

function M.science_pack_exists(name)
  if not M.research_pack_prototype(name) then return false end
  for _, input in ipairs(M.all_lab_inputs()) do
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
