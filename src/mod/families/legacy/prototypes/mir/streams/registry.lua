local M = {}
local deepcopy = require("prototypes.mir.core.deepcopy")
local descriptor = require("prototypes.mir.domain.streams.descriptor")
local target_line = require("prototypes.mir.platform.factorio.target_line")

M.shared = {
  per_level_default = 0.10,
  base_cost = 8000,
  growth_factor = 2,
  research_time = 60
}

local raw_streams = require("prototypes.streams.init")
require("prototypes.mir.compatibility.profiles").apply({ streams = raw_streams })

local canonical_streams = {}
for key, raw_spec in pairs(raw_streams) do
  local spec = descriptor.normalize(key, raw_spec)
  if target_line.stream_supported(key, spec) then canonical_streams[key] = spec end
end

function M.snapshot()
  return deepcopy(canonical_streams)
end

function M.get(key)
  local spec = canonical_streams[key]
  return spec and deepcopy(spec) or nil
end

function M.sorted_keys()
  local keys = {}
  for key, _ in pairs(canonical_streams) do table.insert(keys, key) end
  table.sort(keys)
  return keys
end

return M
