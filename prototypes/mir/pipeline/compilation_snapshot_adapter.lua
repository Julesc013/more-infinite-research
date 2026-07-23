local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local relationships = require("prototypes.mir.index.relationships")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local effect_target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory")
local snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")

local M = {}

local BASE_SURFACES = {
  "technology", "recipe", "fluid", "lab", "module", "ammo-category", "quality", "space-location"
}

local function surface_names()
  local seen, out = {}, {}
  for _, type_name in ipairs(BASE_SURFACES) do seen[type_name] = true end
  for _, type_name in ipairs(lookup.item_types()) do seen[type_name] = true end
  for _, type_name in ipairs(lookup.entity_types()) do seen[type_name] = true end
  for type_name in pairs(seen) do table.insert(out, type_name) end
  table.sort(out)
  return out
end

local function capture_surface(type_name)
  local rows = {}
  for name, prototype in pairs(data_raw.prototypes(type_name)) do
    rows[name] = deepcopy(prototype)
  end
  return rows
end

function M.capture(options)
  options = options or {}
  local surfaces = {}
  for _, type_name in ipairs(surface_names()) do surfaces[type_name] = capture_surface(type_name) end
  local source_fingerprints = deepcopy(options.source_fingerprints or {})
  source_fingerprints.prototype_surfaces = fingerprint.of(surfaces)
  return snapshot_contract.new({
    prototype_surfaces = surfaces,
    relationship_indexes = relationships.snapshot("input"),
    recipe_facts = recipe_facts.snapshot(),
    graph_input = graph_snapshot.new(surfaces.technology or {}),
    effect_target_inventory = effect_target_inventory.capture(),
    provider_inputs = deepcopy(options.provider_inputs or {}),
    stream_inputs = deepcopy(options.stream_inputs or {}),
    base_continuation_inputs = deepcopy(options.base_continuation_inputs or {}),
    source_fingerprints = source_fingerprints
  })
end

return M
