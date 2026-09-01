local deepcopy = require("prototypes.mir.core.deepcopy")
local diagnostic_codes = require("prototypes.mir.domain.diagnostics.codes")

local M = {}

M.schema = 2

M.setting_names = {
  action = "mir-automatic-productivity-action",
  create_research = "mir-automatic-create-research",
  require_reviewed_data = "mir-automatic-require-reviewed-data",
  legacy_mode = "mir-automatic-compiler-mode"
}

M.defaults = {
  action = "apply",
  create_research = false,
  require_reviewed_data = true,
  legacy_mode = "safe-attach"
}

M.actions = {"disabled", "preview", "apply"}
M.creation_maturities = {"experimental", "reviewed"}
M.legacy_modes = {"off", "report", "safe-attach", "exact-pack", "safe-generate"}
M.preset_names = {"conservative", "safe", "expansive", "custom"}

M.presets = {
  conservative = {action = "preview", create_research = false, require_reviewed_data = true},
  safe = {action = "apply", create_research = false, require_reviewed_data = true},
  expansive = {action = "apply", create_research = true, require_reviewed_data = false}
}

local legacy_presets = {
  off = {action = "disabled", create_research = false, require_reviewed_data = true},
  report = {action = "preview", create_research = false, require_reviewed_data = true},
  ["safe-attach"] = {action = "apply", create_research = false, require_reviewed_data = true},
  ["exact-pack"] = {action = "apply", create_research = true, require_reviewed_data = true},
  ["safe-generate"] = {action = "apply", create_research = true, require_reviewed_data = false}
}

local function copy_policy(values, source)
  local policy = {
    schema = M.schema,
    action = values.action,
    create_research = values.create_research == true,
    require_reviewed_data = values.require_reviewed_data ~= false,
    source = source,
    discover = values.action ~= "disabled",
    preview = values.action == "preview",
    apply_changes = values.action == "apply"
  }
  return policy
end

local function contains(values, candidate)
  for _, value in ipairs(values) do
    if value == candidate then return true end
  end
  return false
end

function M.classify_preset(values)
  for _, name in ipairs({"conservative", "safe", "expansive"}) do
    local preset = M.presets[name]
    if values.action == preset.action
      and (values.create_research == true) == preset.create_research
      and (values.require_reviewed_data ~= false) == preset.require_reviewed_data
    then
      return name
    end
  end
  return "custom"
end

function M.resolve_preset(name, custom_values)
  if name == "custom" then
    if type(custom_values) ~= "table" then error("Custom automatic compiler preset requires explicit control values", 2) end
    local policy = M.resolve(custom_values)
    policy.source = "preset:custom"
    policy.preset = "custom"
    return policy
  end
  local values = M.presets[name]
  if not values then error("Unknown automatic compiler preset: " .. tostring(name), 2) end
  local policy = copy_policy(values, "preset:" .. name)
  policy.preset = name
  policy.legacy_mode = M.defaults.legacy_mode
  return policy
end

function M.descriptors(orders)
  orders = orders or {}
  local targets = {requires_features = {"recipe_productivity"}, required_effect_types = {}}
  return {
    {
      schema = 1, id = M.setting_names.action, category = "automatic-productivity",
      consequence = "Controls whether MIR skips discovery, reports decisions, or applies safety-proven attachments.",
      compatibility_consequence = "Does not weaken hard safety gates or authorize new research creation.",
      default_rationale = "Apply safe attachments automatically while leaving new technology creation opt-in.",
      presets = {conservative = "preview", safe = "apply", expansive = "apply"},
      migration = {from = M.setting_names.legacy_mode, strategy = "legacy-policy-expansion"},
      tests = {"compiler-contracts", "semantic-family-modes", "settings-profile-roundtrip"},
      documentation = {"docs/user/settings.md", "docs/reference/settings.md"},
      prototype = {
        type = "string-setting", name = M.setting_names.action, setting_type = "startup",
        default_value = M.defaults.action, allowed_values = M.actions, order = orders.action, targets = targets,
        localised_name = {"mod-setting-name." .. M.setting_names.action},
        localised_description = {"mod-setting-description." .. M.setting_names.action}
      }
    },
    {
      schema = 1, id = M.setting_names.create_research, category = "automatic-productivity",
      consequence = "Allows registered family providers to plan stable generic research when no existing MIR stream fits.",
      compatibility_consequence = "Off attaches to existing research only; on still requires maturity policy and every generation gate.",
      default_rationale = "Keep new technology creation off until the player or modpack author explicitly enables it.",
      presets = {conservative = false, safe = false, expansive = true},
      migration = {from = M.setting_names.legacy_mode, strategy = "legacy-policy-expansion"},
      tests = {"compiler-contracts", "semantic-family-generate", "settings-profile-roundtrip"},
      documentation = {"docs/user/settings.md", "docs/reference/settings.md"},
      prototype = {
        type = "bool-setting", name = M.setting_names.create_research, setting_type = "startup",
        default_value = M.defaults.create_research, order = orders.create_research, targets = targets,
        localised_name = {"mod-setting-name." .. M.setting_names.create_research},
        localised_description = {"mod-setting-description." .. M.setting_names.create_research}
      }
    },
    {
      schema = 1, id = M.setting_names.require_reviewed_data, category = "automatic-productivity",
      consequence = "Restricts creation to reviewed provider families with named exact-version compatibility evidence.",
      compatibility_consequence = "Affects creation only; experimental providers are skipped while safe existing-stream attachment remains available.",
      default_rationale = "If creation is enabled, keep experimental provider generation behind an explicit opt-in.",
      presets = {conservative = true, safe = true, expansive = false},
      migration = {from = M.setting_names.legacy_mode, strategy = "legacy-policy-expansion"},
      tests = {"compiler-contracts", "semantic-family-modes", "settings-profile-roundtrip"},
      documentation = {"docs/user/settings.md", "docs/reference/settings.md"},
      prototype = {
        type = "bool-setting", name = M.setting_names.require_reviewed_data, setting_type = "startup",
        default_value = M.defaults.require_reviewed_data, order = orders.require_reviewed_data, targets = targets,
        localised_name = {"mod-setting-name." .. M.setting_names.require_reviewed_data},
        localised_description = {"mod-setting-description." .. M.setting_names.require_reviewed_data}
      }
    },
    {
      schema = 1, id = M.setting_names.legacy_mode, category = "migration-only", deprecated = true,
      consequence = "Preserves pre-3.1.5 profiles and expands a legacy mode into the independent controls.",
      compatibility_consequence = "Hidden and used only while every replacement control remains at its default.",
      default_rationale = "Retain the released safe-attachment migration baseline for old profiles.",
      presets = {}, migration = {strategy = "read-only-hidden-bridge"},
      tests = {"compiler-contracts", "settings-profile-roundtrip", "upgrade-3-1-2-to-3-1-5-automatic-compiler"},
      documentation = {"docs/user/settings.md", "docs/reference/settings.md"},
      prototype = {
        type = "string-setting", name = M.setting_names.legacy_mode, setting_type = "startup",
        default_value = M.defaults.legacy_mode, allowed_values = M.legacy_modes, order = orders.legacy_mode,
        targets = targets, hidden = true,
        localised_name = {"mod-setting-name." .. M.setting_names.legacy_mode},
        localised_description = {"mod-setting-description." .. M.setting_names.legacy_mode}
      }
    }
  }
end

function M.setting_specs(orders)
  local specs = {}
  for _, descriptor in ipairs(M.descriptors(orders)) do table.insert(specs, deepcopy(descriptor.prototype)) end
  return specs
end

function M.resolve(values)
  values = values or {}
  local action = values.action or M.defaults.action
  local create_research = values.create_research
  local require_reviewed_data = values.require_reviewed_data
  local legacy_mode = values.legacy_mode or M.defaults.legacy_mode

  if not contains(M.actions, action) then action = M.defaults.action end
  if create_research == nil then create_research = M.defaults.create_research end
  if require_reviewed_data == nil then require_reviewed_data = M.defaults.require_reviewed_data end

  local new_controls_are_default = action == M.defaults.action
    and create_research == M.defaults.create_research
    and require_reviewed_data == M.defaults.require_reviewed_data
  if new_controls_are_default and legacy_mode ~= M.defaults.legacy_mode and legacy_presets[legacy_mode] then
    local legacy = copy_policy(legacy_presets[legacy_mode], "legacy:" .. legacy_mode)
    legacy.legacy_mode = legacy_mode
    legacy.preset = M.classify_preset(legacy)
    return legacy
  end

  local policy = copy_policy({
    action = action,
    create_research = create_research,
    require_reviewed_data = require_reviewed_data
  }, "controls-v2")
  policy.legacy_mode = legacy_mode
  policy.preset = M.classify_preset(policy)
  return policy
end

function M.generation_decision(policy, reviewed_authorization, creation_maturity)
  policy = policy or M.resolve()
  creation_maturity = creation_maturity or "reviewed"
  if not contains(M.creation_maturities, creation_maturity) then
    error("Unknown automatic family creation maturity: " .. tostring(creation_maturity), 2)
  end
  if policy.action == "disabled" then
    return false, "automatic_productivity_disabled", diagnostic_codes.get("automatic_productivity_disabled")
  end
  if policy.action == "preview" then
    return false, "automatic_productivity_preview_only", diagnostic_codes.get("automatic_productivity_preview_only")
  end
  if not policy.create_research then
    return false, "automatic_research_creation_disabled", diagnostic_codes.get("automatic_research_creation_disabled")
  end
  if policy.require_reviewed_data and creation_maturity ~= "reviewed" then
    return false, "automatic_family_not_reviewed", diagnostic_codes.get("automatic_family_not_reviewed")
  end
  local reviewed_trust = reviewed_authorization
    and reviewed_authorization.promotion_verified == true
    and (reviewed_authorization.trust_class == "mir-reviewed"
      or reviewed_authorization.trust_class == "protected-release")
  if policy.require_reviewed_data and not reviewed_trust then
    return false, "reviewed_compatibility_data_required", diagnostic_codes.get("reviewed_compatibility_data_required")
  end
  local reason = policy.require_reviewed_data and "reviewed_compatibility_data_authorized" or "registered_family_module_authorized"
  return true, reason, diagnostic_codes.get(reason)
end

return M
