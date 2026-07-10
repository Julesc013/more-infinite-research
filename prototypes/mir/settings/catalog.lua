local C = require("prototypes.mir.streams.registry")
local defaults = require("prototypes.mir.settings.defaults")
local pipeline_extent_settings = require("prototypes.mir.settings.pipeline_extent")
local prototype_limit_settings = require("prototypes.mir.settings.prototype_limits")
local effect_contracts = require("prototypes.mir.settings.effect_contracts")
local setting_order = require("prototypes.mir.settings.order")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}
local spec_by_name_cache = nil

M.import_setting_name = "mir-settings-profile-import"

M.base_extension_specs = {
  { key = "braking-force", sort_name = "Braking force" },
  { key = "inserter-capacity-bonus", sort_name = "Inserter capacity bonus" },
  { key = "laser-shooting-speed", sort_name = "Laser shooting speed" },
  { key = "research-speed", sort_name = "Lab research speed" },
  { key = "weapon-shooting-speed", sort_name = "Weapon shooting speed" },
  { key = "worker-robots-storage", sort_name = "Worker robot cargo size" }
}

local base_defaults = defaults.base_extensions or {}

local function copy_array(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    table.insert(out, value)
  end
  return out
end

local function clone_spec(spec)
  local out = {}
  for key, value in pairs(spec) do
    if type(value) == "table" then
      out[key] = copy_array(value)
    else
      out[key] = value
    end
  end
  return out
end

local function lookup_default(key, field, stream, fallback)
  local stream_defaults = defaults.streams and defaults.streams[key]
  if stream_defaults and stream_defaults[field] ~= nil then return stream_defaults[field] end
  if stream and stream[field] ~= nil then return stream[field] end
  local shared_defaults = defaults.shared or {}
  if shared_defaults[field] ~= nil then return shared_defaults[field] end
  return fallback
end

local function default_base_cost(key, stream)
  return lookup_default(key, "base_cost", stream, C.shared.base_cost)
end

local function default_growth_factor(key, stream)
  return lookup_default(key, "growth_factor", stream, C.shared.growth_factor)
end

local function default_max_level_setting(key, stream)
  local ml = lookup_default(key, "max_level", stream, 0)
  if ml == nil or ml == "infinite" then return 0 end
  local num = tonumber(ml)
  if not num or num <= 0 then return 0 end
  return math.floor(num)
end

local function default_research_time_setting(key, stream)
  local value = lookup_default(key, "research_time", stream, C.shared.research_time)
  if not value or value <= 0 then value = C.shared.research_time end
  return math.floor(value + 0.5)
end

local function default_enabled(key, stream)
  local value = lookup_default(key, "enabled", stream, true)
  return not not value
end

local function base_enabled(defaults_spec)
  local enabled = defaults_spec.enabled
  if enabled == nil then enabled = true end
  return not not enabled
end

local function base_number(defaults_spec, field, fallback, minimum)
  local value = tonumber(defaults_spec[field]) or fallback
  if minimum ~= nil and value < minimum then value = fallback end
  return value
end

local function base_max_level(defaults_spec)
  local value = defaults_spec.max_level
  if value == nil or value == "infinite" then return 0 end
  local num = tonumber(value)
  if not num or num <= 0 then return 0 end
  return math.floor(num + 0.5)
end

local function with_profile_export(spec)
  local out = clone_spec(spec)
  if out.name == M.import_setting_name then
    out.profile_export = false
    return out
  end
  if out.profile_export == nil then out.profile_export = true end
  return out
end

function M.global_setting_prototypes()
  local out = {
    {
      type = "bool-setting",
      name = "ips-require-space-gate",
      setting_type = "startup",
      default_value = false,
      order = setting_order.global("main", 10),
      localised_name = {"mod-setting-name.ips-require-space-gate"},
      localised_description = {"mod-setting-description.ips-require-space-gate"}
    },
    {
      type = "string-setting",
      name = "mir-science-pack-ingredient-policy",
      setting_type = "startup",
      default_value = "configured",
      allowed_values = {"configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all"},
      order = setting_order.global("main", 20),
      localised_name = {"mod-setting-name.mir-science-pack-ingredient-policy"},
      localised_description = {"mod-setting-description.mir-science-pack-ingredient-policy"}
    },
    {
      type = "string-setting",
      name = "mir-lab-incompatibility-policy",
      setting_type = "startup",
      default_value = "reduce",
      allowed_values = {"reduce", "skip", "engine-default"},
      order = setting_order.global("main", 30),
      localised_name = {"mod-setting-name.mir-lab-incompatibility-policy"},
      localised_description = {"mod-setting-description.mir-lab-incompatibility-policy"}
    },
    {
      type = "bool-setting",
      name = "mir-prefer-this-mod-for-competing-techs",
      setting_type = "startup",
      default_value = true,
      order = setting_order.global("main", 40),
      localised_name = {"mod-setting-name.mir-prefer-this-mod-for-competing-techs"},
      localised_description = {"mod-setting-description.mir-prefer-this-mod-for-competing-techs"}
    },
    {
      type = "string-setting",
      name = "mir-adjust-vanilla-weapon-speed-techs",
      setting_type = "startup",
      default_value = target_line.weapon_overlap_default(),
      allowed_values = {"off", "only-when-dedicated-tech-enabled", "always"},
      order = setting_order.global("compatibility", 10),
      localised_name = {"mod-setting-name.mir-adjust-vanilla-weapon-speed-techs"},
      localised_description = {"mod-setting-description.mir-adjust-vanilla-weapon-speed-techs"}
    },
    {
      type = "bool-setting",
      name = "mir-use-installed-space-age-icons",
      setting_type = "startup",
      default_value = false,
      order = setting_order.global("compatibility", 20),
      localised_name = {"mod-setting-name.mir-use-installed-space-age-icons"},
      localised_description = {"mod-setting-description.mir-use-installed-space-age-icons"}
    },
    {
      type = "string-setting",
      name = "mir-pipeline-extent-multiplier",
      setting_type = "startup",
      default_value = pipeline_extent_settings.default_value,
      allowed_values = pipeline_extent_settings.allowed_values,
      order = setting_order.global("compatibility", 30),
      localised_name = {"mod-setting-name.mir-pipeline-extent-multiplier"},
      localised_description = {"mod-setting-description.mir-pipeline-extent-multiplier"}
    }
  }

  for _, setting in ipairs(prototype_limit_settings.setting_prototypes()) do
    table.insert(out, setting)
  end

  table.insert(out, {
    type = "string-setting",
    name = prototype_limit_settings.recycling_return_setting_name,
    setting_type = "startup",
    default_value = prototype_limit_settings.engine_default,
    allowed_values = prototype_limit_settings.recycling_return_allowed_values,
    order = setting_order.global("prototype_limits", 15),
    localised_name = {"mod-setting-name." .. prototype_limit_settings.recycling_return_setting_name},
    localised_description = {"mod-setting-description." .. prototype_limit_settings.recycling_return_setting_name}
  })

  table.insert(out, {
    type = "bool-setting",
    name = prototype_limit_settings.self_recycling_scope_setting_name,
    setting_type = "startup",
    default_value = false,
    order = setting_order.global("prototype_limits", 17),
    localised_name = {"mod-setting-name." .. prototype_limit_settings.self_recycling_scope_setting_name},
    localised_description = {"mod-setting-description." .. prototype_limit_settings.self_recycling_scope_setting_name}
  })

  table.insert(out, {
    type = "bool-setting",
    name = prototype_limit_settings.unrestricted_modules_setting_name,
    setting_type = "startup",
    default_value = false,
    order = setting_order.global("compatibility", 35),
    localised_name = {"mod-setting-name." .. prototype_limit_settings.unrestricted_modules_setting_name},
    localised_description = {"mod-setting-description." .. prototype_limit_settings.unrestricted_modules_setting_name}
  })

  table.insert(out, {
    type = "bool-setting",
    name = prototype_limit_settings.positive_power_floor_setting_name,
    setting_type = "startup",
    default_value = false,
    order = setting_order.global("compatibility", 40),
    localised_name = {"mod-setting-name." .. prototype_limit_settings.positive_power_floor_setting_name},
    localised_description = {"mod-setting-description." .. prototype_limit_settings.positive_power_floor_setting_name}
  })

  table.insert(out, {
    type = "string-setting",
    name = M.import_setting_name,
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    order = setting_order.global("advanced", 10),
    localised_name = {"mod-setting-name." .. M.import_setting_name},
    localised_description = {"mod-setting-description." .. M.import_setting_name}
  })

  table.insert(out, {
    type = "bool-setting",
    name = "mir-debug-generation-report",
    setting_type = "startup",
    default_value = false,
    order = setting_order.global("diagnostics", 10),
    localised_name = {"mod-setting-name.mir-debug-generation-report"},
    localised_description = {"mod-setting-description.mir-debug-generation-report"}
  })
  table.insert(out, {
    type = "bool-setting",
    name = "mir-debug-recipe-matches",
    setting_type = "startup",
    default_value = false,
    order = setting_order.global("diagnostics", 20),
    localised_name = {"mod-setting-name.mir-debug-recipe-matches"},
    localised_description = {"mod-setting-description.mir-debug-recipe-matches"}
  })
  table.insert(out, {
    type = "bool-setting",
    name = "mir-debug-scripted-effects",
    setting_type = "startup",
    default_value = false,
    order = setting_order.global("diagnostics", 30),
    localised_name = {"mod-setting-name.mir-debug-scripted-effects"},
    localised_description = {"mod-setting-description.mir-debug-scripted-effects"}
  })

  local cloned = {}
  for _, spec in ipairs(out) do
    if target_line.global_setting_supported(spec.name) then
      table.insert(cloned, clone_spec(spec))
    end
  end
  return cloned
end

function M.stream_setting_specs(key, stream)
  local out = {
    {
      type = "bool-setting",
      name = "ips-enable-" .. key,
      default_value = default_enabled(key, stream)
    },
    {
      type = "int-setting",
      name = "ips-cost-base-" .. key,
      default_value = default_base_cost(key, stream),
      minimum_value = 1,
      maximum_value = 2147483647
    },
    {
      type = "double-setting",
      name = "ips-cost-growth-" .. key,
      default_value = default_growth_factor(key, stream),
      minimum_value = 1
    },
    {
      type = "int-setting",
      name = "ips-max-level-" .. key,
      default_value = default_max_level_setting(key, stream),
      minimum_value = 0,
      maximum_value = 2147483647
    },
    {
      type = "int-setting",
      name = "ips-research-time-" .. key,
      default_value = default_research_time_setting(key, stream),
      minimum_value = 0,
      maximum_value = 2147483647
    }
  }
  local effect_setting = effect_contracts.stream_setting_spec(key, stream)
  if effect_setting then table.insert(out, effect_setting) end
  return out
end

function M.base_extension_setting_specs(key)
  local defaults_spec = base_defaults[key] or {}
  local base_default = math.floor(base_number(defaults_spec, "base_cost", 0, 0) + 0.5)
  local growth_default = base_number(defaults_spec, "growth_factor", 0, 0)
  local research_time_default = math.floor(base_number(defaults_spec, "research_time", 60, 1) + 0.5)
  local out = {
    {
      type = "bool-setting",
      name = "mir-enable-" .. key,
      default_value = base_enabled(defaults_spec)
    },
    {
      type = "int-setting",
      name = "mir-cost-base-" .. key,
      default_value = base_default,
      minimum_value = 0,
      maximum_value = 2147483647
    },
    {
      type = "double-setting",
      name = "mir-cost-growth-" .. key,
      default_value = growth_default,
      minimum_value = 0
    },
    {
      type = "int-setting",
      name = "mir-max-level-" .. key,
      default_value = base_max_level(defaults_spec),
      minimum_value = 0,
      maximum_value = 2147483647
    },
    {
      type = "int-setting",
      name = "mir-research-time-" .. key,
      default_value = research_time_default,
      minimum_value = 0,
      maximum_value = 2147483647
    }
  }
  local effect_setting = effect_contracts.base_setting_spec(key)
  if effect_setting then table.insert(out, effect_setting) end
  return out
end

function M.all_specs()
  local out = {}
  for _, spec in ipairs(M.global_setting_prototypes()) do
    local profile_spec = with_profile_export(spec)
    if profile_spec.name == "mir-pipeline-extent-multiplier" then
      profile_spec.import_numeric_minimum = 0.1
      profile_spec.import_numeric_maximum = 100000
    elseif profile_spec.name == prototype_limit_settings.recycling_return_setting_name then
      profile_spec.import_numeric_minimum = 0
      profile_spec.import_numeric_maximum = 25
      profile_spec.accepted_import_values = copy_array(prototype_limit_settings.recycling_return_accepted_import_values)
    end
    for _, key in ipairs(prototype_limit_settings.order) do
      local limit_spec = prototype_limit_settings.settings[key]
      if limit_spec and limit_spec.name == profile_spec.name then
        if limit_spec.accepted_import_values then
          profile_spec.accepted_import_values = copy_array(limit_spec.accepted_import_values)
        end
        profile_spec.import_numeric_minimum = limit_spec.import_numeric_minimum
        profile_spec.import_numeric_maximum = limit_spec.import_numeric_maximum
      end
    end
    table.insert(out, profile_spec)
  end
  for key, stream in pairs(C.streams) do
    for _, spec in ipairs(M.stream_setting_specs(key, stream)) do
      table.insert(out, with_profile_export(spec))
    end
  end
  for _, base_spec in ipairs(M.base_extension_specs) do
    for _, spec in ipairs(M.base_extension_setting_specs(base_spec.key)) do
      table.insert(out, with_profile_export(spec))
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function M.spec_by_name()
  if spec_by_name_cache then return spec_by_name_cache end
  local out = {}
  for _, spec in ipairs(M.all_specs()) do
    out[spec.name] = spec
  end
  spec_by_name_cache = out
  return spec_by_name_cache
end

function M.spec(name)
  return M.spec_by_name()[name]
end

function M.default_value(name)
  local spec = M.spec(name)
  if spec then return spec.default_value end
  return nil
end

function M.setting_names(options)
  options = options or {}
  local startup = settings and settings.startup
  local out = {}
  for _, spec in ipairs(M.all_specs()) do
    if spec.profile_export ~= false and (not options.registered_only or (startup and startup[spec.name])) then
      table.insert(out, spec.name)
    end
  end
  return out
end

local function value_type_for_spec(spec)
  if spec.type == "bool-setting" then return "boolean" end
  if spec.type == "string-setting" then return "string" end
  if spec.type == "int-setting" or spec.type == "double-setting" then return "number" end
  return nil
end

local function allowed_value_map(spec)
  local out = {}
  for _, value in ipairs(spec.allowed_values or {}) do
    out[tostring(value)] = true
  end
  for _, value in ipairs(spec.accepted_import_values or {}) do
    out[tostring(value)] = true
  end
  return out
end

function M.validate_value(name, value)
  if name == M.import_setting_name then return false, "profile import setting is not importable" end

  local spec = M.spec(name)
  if not spec then return false, "unknown setting" end

  local expected = value_type_for_spec(spec)
  local numeric_dropdown_import = spec.type == "string-setting"
    and type(value) == "number"
    and spec.import_numeric_minimum ~= nil
    and spec.import_numeric_maximum ~= nil
  if expected and type(value) ~= expected and not numeric_dropdown_import then
    return false, "wrong type"
  end

  if numeric_dropdown_import then
    if value ~= value or value == math.huge or value == -math.huge then
      return false, "not finite"
    end
    if value < spec.import_numeric_minimum then return false, "below minimum" end
    if value > spec.import_numeric_maximum then return false, "above maximum" end
    return true
  end

  if spec.type == "int-setting" then
    if math.floor(value) ~= value then return false, "not an integer" end
  end

  if spec.type == "string-setting" and spec.allowed_values then
    local allowed = allowed_value_map(spec)
    if not allowed[tostring(value)] then return false, "invalid value" end
  end

  if type(value) == "number" then
    if spec.minimum_value ~= nil and value < spec.minimum_value then
      return false, "below minimum"
    end
    if spec.maximum_value ~= nil and value > spec.maximum_value then
      return false, "above maximum"
    end
  end

  return true
end

function M.is_default_value(name, value)
  local spec = M.spec(name)
  if not spec then return false end

  local default_value = spec.default_value
  if type(default_value) == "number" and type(value) == "number" then
    return default_value == value
  end
  return default_value == value
end

return M
