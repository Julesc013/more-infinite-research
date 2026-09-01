local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

function M.snapshot(owner)
  return {
    name = owner and owner.name,
    max_level = owner and owner.max_level,
    prerequisites = deepcopy((owner and owner.prerequisites) or {}),
    unit = deepcopy((owner and owner.unit) or {}),
    effects = deepcopy((owner and owner.effects) or {})
  }
end

function M.fingerprint(snapshot)
  return fingerprint.of(snapshot or {})
end

function M.refresh_effects(plan, effects)
  local out = deepcopy(plan)
  local removed = {}
  for _, effect in ipairs(out.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe then removed[effect.recipe] = true end
  end
  local expected_effects = {}
  for _, effect in ipairs((out.expected_snapshot and out.expected_snapshot.effects) or {}) do
    if not (effect.type == "change-recipe-productivity" and removed[effect.recipe]) then
      table.insert(expected_effects, effect)
    end
  end
  for _, effect in ipairs(effects or {}) do table.insert(expected_effects, deepcopy(effect)) end
  out.effects = deepcopy(effects or {})
  out.expected_snapshot.effects = expected_effects
  if #(out.configured_fields or {}) > 0 and #out.effects > 0 then
    out.operation = "configure_and_adopt_native_owner"
  elseif #(out.configured_fields or {}) > 0 then
    out.operation = "configure_native_owner"
  elseif #out.effects > 0 then
    out.operation = "adopt_native_owner_effects"
  else
    out.operation = "preserve_native_owner"
  end
  out.output_fingerprint = M.fingerprint(out.expected_snapshot)
  return out
end

return M
