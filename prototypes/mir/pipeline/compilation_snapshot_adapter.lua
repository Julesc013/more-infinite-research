local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local relationships = require("prototypes.mir.index.relationships")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local effect_target_inventory = require("prototypes.mir.platform.factorio.effect_target_inventory")
local science_packs = require("prototypes.mir.capabilities.science_integration.pack_registry")
local snapshot_contract = require("prototypes.mir.domain.compiler.compilation_snapshot")

local M = {}

local function now()
  return os and type(os.clock) == "function" and os.clock() or 0
end

local function memory_bytes()
  return collectgarbage and collectgarbage("count") * 1024 or 0
end

local function sorted_keys(values)
  local out = {}
  for key, enabled in pairs(values or {}) do if enabled then table.insert(out, key) end end
  table.sort(out)
  return out
end

local function technology_facts(graph)
  local facts = {}
  for _, node in ipairs(graph.nodes or {}) do
    local technology = data_raw.technology(node.name) or {}
    local effect_identities = {}
    for _, effect in ipairs(technology.effects or {}) do
      table.insert(effect_identities, effect_contracts.identity(effect))
    end
    table.sort(effect_identities)
    facts[node.name] = {
      schema = 1,
      record_type = "TechnologyFact",
      name = node.name,
      enabled = node.enabled,
      hidden = technology.hidden == true,
      prerequisites = node.prerequisites,
      science_packs = node.science_packs,
      research_trigger = node.research_trigger,
      has_research_count = node.has_research_count,
      max_level = technology.max_level,
      upgrade = technology.upgrade == true,
      effect_identities = effect_identities
    }
  end
  return facts
end

local function item_facts(relationship_index)
  local facts = {}
  for name, item in pairs(relationship_index.items or {}) do
    local prototype = lookup.item_prototype(name) or {}
    facts[name] = {
      schema = 1,
      record_type = "ItemFact",
      name = name,
      prototype_type = item.prototype_type,
      place_result = item.place_result,
      subgroup = item.subgroup,
      stack_size = prototype.stack_size,
      weight = prototype.weight,
      spoil_result = prototype.spoil_result
    }
  end
  return facts
end

local function entity_facts()
  local facts = {}
  lookup.each_entity_prototype(function(name, entity, prototype_type)
    facts[name] = {
      schema = 1,
      record_type = "EntityFact",
      name = name,
      prototype_type = prototype_type,
      subgroup = entity.subgroup,
      next_upgrade = entity.next_upgrade,
      crafting_categories = sorted_keys(entity.crafting_categories),
      surface_conditions = deepcopy(entity.surface_conditions or {})
    }
  end)
  return facts
end

local function lab_facts()
  local facts = {}
  for name, lab in pairs(data_raw.prototypes("lab")) do
    local inputs = {}
    for _, input in ipairs(lab.inputs or {}) do table.insert(inputs, input) end
    table.sort(inputs)
    facts[name] = {
      schema = 1,
      record_type = "LabFact",
      name = name,
      inputs = inputs,
      researching_speed = lab.researching_speed,
      surface_conditions = deepcopy(lab.surface_conditions or {})
    }
  end
  return facts
end

local function science_pack_facts()
  local facts = {}
  for _, name in ipairs(science_packs.pack_list_all()) do
    local prototype = science_packs.research_pack_prototype(name) or {}
    facts[name] = {
      schema = 1,
      record_type = "SciencePackFact",
      name = name,
      prototype_type = prototype.type,
      official = science_packs.is_official_science_pack(name),
      durability = prototype.durability,
      durability_description_key = prototype.durability_description_key
    }
  end
  return facts
end

function M.capture(options)
  options = options or {}
  local started_at, memory_before = now(), memory_bytes()
  local relationship_index = relationships.view("input")
  local recipe_index = recipe_facts.index_view()
  local graph = graph_snapshot.new(data_raw.prototypes("technology"))
  local domains = {
    recipes = {schema = recipe_index.schema, names = recipe_index.names, facts = recipe_index.facts},
    technologies = technology_facts(graph),
    items = item_facts(relationship_index),
    entities = entity_facts(),
    labs = lab_facts(),
    science_packs = science_pack_facts()
  }
  local owners = {
    schema = 1,
    technologies_by_effect_identity = relationship_index.technologies_by_effect_identity,
    technologies_by_recipe_effect = relationship_index.technologies_by_recipe_effect
  }
  local source_fingerprints = deepcopy(options.source_fingerprints or {})
  source_fingerprints.normalized_fact_domains = fingerprint.of({
    recipe_count = #(recipe_index.names or {}),
    technology_count = #(graph.nodes or {})
  })
  local result = snapshot_contract.new({
    fact_domains = domains,
    relationship_indexes = relationship_index,
    owner_index = owners,
    graph_input = graph,
    effect_target_inventory = effect_target_inventory.capture(),
    provider_inputs = options.provider_inputs or {},
    stream_inputs = options.stream_inputs or {},
    base_continuation_inputs = options.base_continuation_inputs or {},
    source_fingerprints = source_fingerprints,
    structural_sharing = {
      reused_domains = {"recipes", "relationships"},
      copied_domains = {"technologies", "items", "entities", "labs", "science_packs", "graph", "effect_targets"}
    },
    metrics = {
      construction_seconds = math.max(0, now() - started_at),
      memory_before_bytes = memory_before,
      memory_after_bytes = memory_bytes(),
      deep_copy_count = 3
    }
  })
  result.metrics.peak_memory_bytes = math.max(result.metrics.memory_before_bytes, result.metrics.memory_after_bytes)
  result.metrics.snapshot_bytes = #fingerprint.canonical(snapshot_contract.snapshot(result))
  result.metrics.canonicalization_passes = result.metrics.canonicalization_passes + 1
  return result
end

return M
