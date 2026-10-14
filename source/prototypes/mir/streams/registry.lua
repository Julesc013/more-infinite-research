local M = {}
local deepcopy = require("prototypes.mir.core.deepcopy")
local descriptor = require("prototypes.mir.domain.streams.descriptor")
local target_line = require("prototypes.mir.platform.factorio.target_line")

M.shared = {
  per_level_default = 0.10,
  base_cost = 8000,
  growth_factor = 2,
  research_time = 60,
  science_binding_policy = {
    -- Parameterized sources bind an actual same-named pack recipe and its
    -- unique direct unlock owner. They never explore ingredient factories.
    named_pack_recipe = true,
    unique_direct_recipe = true,
    unique_direct_unlock = true
  },
  -- Shared source declarations for the ordinary productivity-family science
  -- vector. These are authored progression bindings, not cached discoveries.
  -- The target adapter translates the roles to historical item spellings.
  science_bindings = {
    ["automation-science-pack"] = {
      recipe = "automation-science-pack", technology = "automation-science-pack", allow_initial = true
    },
    ["logistic-science-pack"] = {
      recipe = "logistic-science-pack", technology = "logistic-science-pack", allow_initial = true
    },
    ["chemical-science-pack"] = {
      recipe = "chemical-science-pack", technology = "chemical-science-pack", allow_initial = true
    },
    ["production-science-pack"] = {
      recipe = "production-science-pack", technology = "production-science-pack", allow_initial = true
    }
  }
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

-- Internal planning boundary for source-owned normalized stream policy.
-- Callers must treat the returned catalog as immutable; snapshot() and get()
-- remain the defensive-copy surfaces for independently owned values.
function M.view()
  return canonical_streams
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
