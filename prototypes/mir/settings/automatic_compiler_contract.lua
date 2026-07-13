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
M.legacy_modes = {"off", "report", "safe-attach", "exact-pack", "safe-generate"}

local legacy_presets = {
  off = {action = "disabled", create_research = false, require_reviewed_data = true},
  report = {action = "preview", create_research = false, require_reviewed_data = true},
  ["safe-attach"] = {action = "apply", create_research = false, require_reviewed_data = true},
  ["exact-pack"] = {action = "apply", create_research = true, require_reviewed_data = true},
  ["safe-generate"] = {action = "apply", create_research = true, require_reviewed_data = false}
}

local function copy_policy(values, source)
  return {
    schema = M.schema,
    action = values.action,
    create_research = values.create_research == true,
    require_reviewed_data = values.require_reviewed_data ~= false,
    source = source,
    discover = values.action ~= "disabled",
    preview = values.action == "preview",
    apply_changes = values.action == "apply"
  }
end

local function contains(values, candidate)
  for _, value in ipairs(values) do
    if value == candidate then return true end
  end
  return false
end

function M.setting_specs(orders)
  orders = orders or {}
  local targets = {requires_features = {"recipe_productivity"}, required_effect_types = {}}
  return {
    {
      type = "string-setting",
      name = M.setting_names.action,
      setting_type = "startup",
      default_value = M.defaults.action,
      allowed_values = M.actions,
      order = orders.action,
      targets = targets,
      localised_name = {"mod-setting-name." .. M.setting_names.action},
      localised_description = {"mod-setting-description." .. M.setting_names.action}
    },
    {
      type = "bool-setting",
      name = M.setting_names.create_research,
      setting_type = "startup",
      default_value = M.defaults.create_research,
      order = orders.create_research,
      targets = targets,
      localised_name = {"mod-setting-name." .. M.setting_names.create_research},
      localised_description = {"mod-setting-description." .. M.setting_names.create_research}
    },
    {
      type = "bool-setting",
      name = M.setting_names.require_reviewed_data,
      setting_type = "startup",
      default_value = M.defaults.require_reviewed_data,
      order = orders.require_reviewed_data,
      targets = targets,
      localised_name = {"mod-setting-name." .. M.setting_names.require_reviewed_data},
      localised_description = {"mod-setting-description." .. M.setting_names.require_reviewed_data}
    },
    {
      type = "string-setting",
      name = M.setting_names.legacy_mode,
      setting_type = "startup",
      default_value = M.defaults.legacy_mode,
      allowed_values = M.legacy_modes,
      order = orders.legacy_mode,
      targets = targets,
      hidden = true,
      localised_name = {"mod-setting-name." .. M.setting_names.legacy_mode},
      localised_description = {"mod-setting-description." .. M.setting_names.legacy_mode}
    }
  }
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
    return legacy
  end

  local policy = copy_policy({
    action = action,
    create_research = create_research,
    require_reviewed_data = require_reviewed_data
  }, "controls-v2")
  policy.legacy_mode = legacy_mode
  return policy
end

function M.generation_decision(policy, reviewed_authorization)
  policy = policy or M.resolve()
  if policy.action == "disabled" then
    return false, "automatic_productivity_disabled"
  end
  if policy.action == "preview" then
    return false, "automatic_productivity_preview_only"
  end
  if not policy.create_research then
    return false, "automatic_research_creation_disabled"
  end
  if policy.require_reviewed_data and not reviewed_authorization then
    return false, "reviewed_compatibility_data_required"
  end
  return true, policy.require_reviewed_data and "reviewed_compatibility_data_authorized" or "registered_family_module_authorized"
end

return M
