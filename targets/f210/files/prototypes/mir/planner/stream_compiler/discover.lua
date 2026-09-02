local C = require("prototypes.mir.streams.registry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")

local M = {}

local function append_unique_item(items, seen, item_name)
  if item_name and not seen[item_name] then
    seen[item_name] = true
    table.insert(items, item_name)
  end
end

function M.expand_dynamic_items(spec)
  if not (spec and spec.dynamic_items_from_lab_inputs) then return spec end

  local out = deepcopy(spec)
  local base_group_items = {}
  for _, item_name in ipairs(out.items or {}) do table.insert(base_group_items, item_name) end

  if not out.groups then
    out.groups = {{change = C.shared.per_level_default, items = base_group_items}}
  end
  if not out.groups[1] then
    out.groups[1] = {change = C.shared.per_level_default, items = base_group_items}
  end
  out.groups[1].items = out.groups[1].items or {}

  local first_group_seen = {}
  for _, item_name in ipairs(out.groups[1].items) do first_group_seen[item_name] = true end
  for _, item_name in ipairs(base_group_items) do
    append_unique_item(out.groups[1].items, first_group_seen, item_name)
  end

  local seen = {}
  for _, item_name in ipairs(out.items or {}) do seen[item_name] = true end
  for _, group in ipairs(out.groups or {}) do
    for _, item_name in ipairs(group.items or {}) do seen[item_name] = true end
  end
  for _, item_name in ipairs(science_packs.pack_list_all()) do
    append_unique_item(out.groups[1].items, seen, item_name)
  end
  return out
end

function M.ensure_services(context)
  science_packs.ensure_services(context)
end

function M.source_snapshot()
  local streams = C.view()
  local native_owner_inputs = {}
  for key, spec in pairs(streams) do
    local binding = spec.native_owner_binding
    if binding and binding.owner then
      local owner = data_raw.technology(binding.owner)
      native_owner_inputs[key] = owner and native_owner_contract.snapshot(owner)
        or {name = binding.owner, missing = true}
    end
  end
  return streams, native_owner_inputs
end

return M
