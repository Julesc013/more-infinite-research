local schema = require("prototypes.lib.mir.schema")

local P = {}

P.schema_version = schema.capability_policy

P.defaults = {
  mode = "observe",
  min_confidence = {
    identity = 0.95,
    family = 0.90,
    science = 1.00,
    lab = 1.00,
    owner = 0.95,
    loop_safety = 0.95,
    total = 0.92
  },
  owner_policy = "skip_conflict",
  science = "derive_from_unlocks",
  deny_risk_flags = {
    "recycling_loop",
    "catalyst_or_self_return",
    "cleaning_or_recovery_loop",
    "voiding_or_destruction",
    "matter_or_transmutation",
    "hidden_internal"
  }
}

P.capabilities = {
  ["logistics-loader-manufacturing"] = {
    schema_version = schema.capability_policy,
    mode = "safe",
    min_confidence = {
      identity = 0.95,
      family = 0.90,
      science = 1.00,
      lab = 1.00,
      owner = 0.95,
      loop_safety = 0.95,
      total = 0.92
    },
    require_entity_type = {"loader", "loader-1x1"},
    require_recipe_output_placeable = true,
    owner_policy = "skip_conflict",
    science = "derive_from_unlocks",
    deny_risk_flags = P.defaults.deny_risk_flags
  },
  ["mining-drill-manufacturing"] = {
    schema_version = schema.capability_policy,
    mode = "safe",
    min_confidence = {
      identity = 0.95,
      family = 0.90,
      science = 1.00,
      lab = 1.00,
      owner = 0.95,
      loop_safety = 0.95,
      total = 0.92
    },
    require_entity_type = {"mining-drill"},
    require_recipe_output_placeable = true,
    owner_policy = "skip_conflict",
    science = "derive_from_unlocks",
    deny_risk_flags = P.defaults.deny_risk_flags
  },
  ["native-modifier-ownership"] = {
    schema_version = schema.capability_policy,
    mode = "observe",
    min_confidence = {
      owner = 1.00,
      total = 1.00
    },
    owner_policy = "prefer_existing",
    emit_mir_owner = false,
    deny_risk_flags = {
      "duplicate_native_modifier_owner"
    }
  }
}

function P.for_capability(id)
  return P.capabilities[id] or P.defaults
end

return P
