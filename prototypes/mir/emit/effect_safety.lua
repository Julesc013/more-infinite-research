local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local deepcopy = require("prototypes.mir.core.deepcopy")
local effect_safety_policy = require("prototypes.mir.domain.technology.effect_safety_policy")
local technology_effects = require("prototypes.mir.integrity.technology_effects")

local S = {}

S.assert_effect_allowed = technology_effects.assert_effect_allowed
S.assert_effects_allowed = technology_effects.assert_effects_allowed

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

local function log_pruned_effect(technology_name, effect, reason, target, owner)
  if type(log) ~= "function" then return end
  log("[MIR] pruned dangling technology effect from "
    .. tostring(technology_name)
    .. ": owner="
    .. tostring(owner)
    .. " type="
    .. tostring(effect and effect.type)
    .. " target="
    .. tostring(target)
    .. " reason="
    .. tostring(reason))
end

S.sanitize_effects = technology_effects.sanitize_effects

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
    scanned_technology_count = 0,
    scanned_effect_count = 0,
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
    summary.scanned_technology_count = summary.scanned_technology_count + 1
    summary.scanned_effect_count = summary.scanned_effect_count + original_effect_count
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
  telemetry.count("sanitation_scanned_technologies", summary.scanned_technology_count)
  telemetry.count("sanitation_scanned_effects", summary.scanned_effect_count)
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
