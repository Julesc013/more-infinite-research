local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local effect_safety_policy = require("prototypes.mir.domain.technology.effect_safety_policy")

local M = {}

M.assert_effect_allowed = effect_safety_policy.assert_effect_allowed
M.assert_effects_allowed = effect_safety_policy.assert_effects_allowed

-- Zero is an exact no-change value for native additive modifiers. Other
-- effect forms retain their existing contracts and runtime qualification;
-- this predicate is not a native usefulness or saturation proof.
function M.has_possible_research_effects(effects)
  for _, effect in ipairs(effects or {}) do
    -- Numeric-looking extra fields do not define these effects' semantics.
    if effect.type == "nothing" or effect.type == "give-item"
      or (type(effect.type) == "string" and effect.type:sub(1, 7) == "unlock-") then
      return true
    end
    local value = effect.modifier
    if effect.type == "change-recipe-productivity" then value = effect.change end
    if type(value) ~= "number" or value ~= 0 then return true end
  end
  return false
end

function M.sanitize_effects(effects, context, owner, target_inventory, observer)
  local kept, removed, retained_order, retained_identities = {}, {}, {}, {}
  for index, effect in ipairs(effects or {}) do
    local valid, reason, target = effect_contracts.target_status(effect, target_inventory)
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
      if observer then observer(context, effect, target, owner) end
    end
  end
  return kept, removed, retained_order, retained_identities
end

function M.snapshot_effects(effects)
  return deepcopy(effects or {})
end

return M
