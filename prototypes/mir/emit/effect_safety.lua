local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local deepcopy = require("prototypes.mir.core.deepcopy")

local S = {}

local blocked_effect_types = {
  ["character-item-pickup-distance"] = "item pickup reach can vacuum nearby belt items into player inventories and cause severe lag",
  ["character-loot-pickup-distance"] = "loot pickup reach can vacuum nearby belt items into player inventories and cause severe lag"
}

function S.assert_effect_allowed(effect, context)
  local effect_type = effect and effect.type
  local reason = blocked_effect_types[effect_type]
  if reason then
    error("MIR safety guard blocked unsafe technology effect "
      .. effect_type
      .. " in "
      .. tostring(context or "unknown technology")
      .. ": "
      .. reason
      .. ".")
  end
end

function S.assert_effects_allowed(effects, context)
  for _, effect in ipairs(effects or {}) do
    S.assert_effect_allowed(effect, context)
  end
end

local function assert_effect_target_exists(effect, technology_name)
  local valid, reason, target = effect_contracts.target_status(effect)
  if valid then return end
  error("Technology "
    .. tostring(technology_name)
    .. " has invalid "
    .. tostring(effect and effect.type)
    .. " effect target "
    .. tostring(target)
    .. " ("
    .. tostring(reason)
    .. ").")
end

local function log_pruned_effect(technology_name, effect, reason, owner)
  if type(log) ~= "function" then return end
  log("[MIR] pruned dangling technology effect from "
    .. tostring(technology_name)
    .. ": owner="
    .. tostring(owner)
    .. " type="
    .. tostring(effect and effect.type)
    .. " target="
    .. tostring(effect and (effect.recipe or effect.item or effect.space_location or effect.ammo_category))
    .. " reason="
    .. tostring(reason))
end

function S.sanitize_effects(effects, context, owner)
  local kept, removed, retained_effect_order, retained_effect_identities = {}, {}, {}, {}
  for effect_index, effect in ipairs(effects or {}) do
    local valid, reason, target = effect_contracts.target_status(effect)
    if valid then
      table.insert(kept, effect)
      table.insert(retained_effect_order, effect_index)
      local identity = effect_contracts.identity(effect)
      table.insert(retained_effect_identities, identity ~= "" and identity or fingerprint.of(effect))
    else
      table.insert(removed, {
        original_effect_index = effect_index,
        type = effect and effect.type,
        target = target,
        reason = reason,
        removed_effect_fingerprint = fingerprint.of(effect or {})
      })
      log_pruned_effect(context, effect, reason, owner or "unknown")
      telemetry.count("effects_pruned", 1)
      telemetry.witness("pruned_effects", tostring(context) .. ":" .. tostring(effect and effect.type) .. ":" .. tostring(target))
    end
  end
  return kept, removed, retained_effect_order, retained_effect_identities
end

function S.prune_missing_recipe_effects(technology, technology_name)
  local effects = technology and technology.effects or {}
  local kept, removed = S.sanitize_effects(effects, technology_name, "generated")
  if #removed > 0 then technology.effects = kept end
  local removed_recipes = {}
  for _, row in ipairs(removed) do
    if row.type == "change-recipe-productivity" then table.insert(removed_recipes, tostring(row.target)) end
  end
  return {
    pruned_effect_count = #removed,
    remaining_effect_count = #kept,
    removed_recipes = removed_recipes,
    removed_effects = removed
  }
end

function S.sanitize_registered_technology_effects()
  local summary = {
    pruned_effect_count = 0,
    affected_technology_count = 0,
    emptied_technology_count = 0
  }

  for _, name in ipairs(generated_registry.sorted_names()) do
    local tech = data_raw.technology(name)
    if tech then
      local kept, removed = S.sanitize_effects(tech.effects or {}, name, "generated")
      if #removed > 0 then tech.effects = kept end
      local result = {
        pruned_effect_count = #removed,
        remaining_effect_count = #kept
      }
      if result.pruned_effect_count > 0 then
        summary.pruned_effect_count = summary.pruned_effect_count + result.pruned_effect_count
        summary.affected_technology_count = summary.affected_technology_count + 1
        if result.remaining_effect_count == 0 then
          summary.emptied_technology_count = summary.emptied_technology_count + 1
        end
      end
    end
  end

  return summary
end

local function owner_record(name)
  if generated_registry.contains(name) then
    return "generated", "more-infinite-research", true
  end
  return "external", "<unknown>", false
end

function S.sanitize_all_technology_effects(options)
  options = options or {}
  local summary = {
    schema = 1,
    pass = options.pass or "unspecified",
    pruned_effect_count = 0,
    affected_technology_count = 0,
    generated_technology_count = 0,
    external_technology_count = 0,
    emptied_technology_count = 0,
    technologies = {},
    sanitized_target_inventory_fingerprint = fingerprint.of(effect_contracts.target_inventory())
  }
  local names = {}
  for name, _ in pairs(data_raw.prototypes("technology")) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local technology = data_raw.technology(name)
    local owner, owning_mod, owning_mod_known = owner_record(name)
    local original_effects = deepcopy((technology and technology.effects) or {})
    local original_effect_count = #original_effects
    local kept, removed, retained_effect_order, retained_effect_identities = S.sanitize_effects(
      original_effects, name, owner)
    if #removed > 0 then
      technology.effects = kept
      summary.pruned_effect_count = summary.pruned_effect_count + #removed
      summary.affected_technology_count = summary.affected_technology_count + 1
      summary[owner .. "_technology_count"] = summary[owner .. "_technology_count"] + 1
      if #kept == 0 then summary.emptied_technology_count = summary.emptied_technology_count + 1 end
      table.insert(summary.technologies, {
        original_technology = name,
        original_effect_count = original_effect_count,
        original_effects_fingerprint = fingerprint.of(original_effects),
        owner_kind = owner,
        owning_mod = owning_mod,
        owning_mod_known = owning_mod_known,
        removed_effects = removed,
        retained_effect_order = retained_effect_order,
        retained_effect_identities = retained_effect_identities,
        retained_effects_fingerprint = fingerprint.of(kept),
        sanitized_effects_fingerprint = fingerprint.of(technology.effects or {})
      })
    end
  end
  return summary
end

function S.assert_target_inventory_unchanged(input_ledger, output_ledger)
  local input_fingerprint = input_ledger and input_ledger.sanitized_target_inventory_fingerprint
  local output_fingerprint = output_ledger and output_ledger.sanitized_target_inventory_fingerprint
  if type(input_fingerprint) ~= "string" or input_fingerprint ~= output_fingerprint then
    error("MIR created or removed a sanitation-covered target prototype after input sanitation.", 2)
  end
  return true
end

function S.register_generated_technology(name)
  generated_registry.register(name)
end

function S.assert_registered_technology_effects()
  for _, name in ipairs(generated_registry.sorted_names()) do
    local tech = data_raw.technology(name)
    if tech then
      S.assert_effects_allowed(tech.effects, name)
      for _, effect in ipairs(tech.effects or {}) do
        assert_effect_target_exists(effect, name)
      end
    end
  end
end

return S
