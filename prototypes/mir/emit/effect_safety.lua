local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
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
  if not valid then
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
end

local function log_pruned_effect(technology_name, effect, reason, target, owner)
  if type(log) ~= "function" then return end
  log("[MIR] pruned dangling technology effect from "
    .. tostring(technology_name)
    .. ": owner=" .. tostring(owner)
    .. " type=" .. tostring(effect and effect.type)
    .. " target=" .. tostring(target)
    .. " reason=" .. tostring(reason))
end

function S.sanitize_effects(effects, technology_name, owner)
  local kept, removed = {}, {}
  for effect_index, effect in ipairs(effects or {}) do
    local valid, reason, target, target_field = effect_contracts.target_status(effect)
    if valid then
      table.insert(kept, effect)
    else
      table.insert(removed, {
        original_effect_index = effect_index,
        type = effect and effect.type,
        target_field = target_field,
        target = target,
        reason = reason,
        removed_effect_fingerprint = fingerprint.of(effect or {})
      })
      log_pruned_effect(technology_name, effect, reason, target, owner or "unknown")
    end
  end
  return kept, removed
end

function S.sanitize_all_technology_effects()
  local summary = {
    schema = 1,
    pruned_effect_count = 0,
    affected_technology_count = 0,
    emptied_technology_count = 0,
    technologies = {}
  }
  local names = {}
  for name, _ in pairs(data_raw.prototypes("technology")) do table.insert(names, name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local technology = data_raw.technology(name)
    local original = deepcopy((technology and technology.effects) or {})
    local kept, removed = S.sanitize_effects(
      original, name, generated_registry.contains(name) and "generated" or "external")
    if #removed > 0 then
      technology.effects = kept
      summary.pruned_effect_count = summary.pruned_effect_count + #removed
      summary.affected_technology_count = summary.affected_technology_count + 1
      if #kept == 0 then summary.emptied_technology_count = summary.emptied_technology_count + 1 end
      table.insert(summary.technologies, {
        technology = name,
        original_effect_count = #original,
        remaining_effect_count = #kept,
        removed_effects = removed
      })
    end
  end
  return summary
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
