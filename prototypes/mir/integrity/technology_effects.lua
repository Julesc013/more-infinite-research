local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local effect_safety_policy = require("prototypes.mir.domain.technology.effect_safety_policy")
local telemetry = require("prototypes.mir.report.compiler_telemetry")

local M = {}

M.assert_effect_allowed = effect_safety_policy.assert_effect_allowed
M.assert_effects_allowed = effect_safety_policy.assert_effects_allowed

function M.sanitize_effects(effects, context, owner)
  local kept, removed, retained_order, retained_identities = {}, {}, {}, {}
  for index, effect in ipairs(effects or {}) do
    local valid, reason, target = effect_contracts.target_status(effect)
    if valid then
      table.insert(kept, effect)
      table.insert(retained_order, index)
      local identity = effect_contracts.identity(effect)
      table.insert(retained_identities, identity ~= "" and identity or fingerprint.of(effect))
    else
      table.insert(removed, {
        original_effect_index = index,
        type = effect and effect.type,
        target = target,
        reason = reason,
        removed_effect_fingerprint = fingerprint.of(effect or {})
      })
      telemetry.count("effects_pruned", 1)
      telemetry.witness("pruned_effects", tostring(context) .. ":" .. tostring(effect and effect.type)
        .. ":" .. tostring(target) .. ":" .. tostring(owner or "unknown"))
    end
  end
  return kept, removed, retained_order, retained_identities
end

function M.snapshot_effects(effects)
  return deepcopy(effects or {})
end

return M
