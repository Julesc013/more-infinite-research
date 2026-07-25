local profile_codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function raw_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function setting_exists(name)
  return settings and settings.startup and settings.startup[name] ~= nil
end

local function import_state(context)
  context = context or compiler_context.current()
  return context:state_view("effective_settings_import", function()
    return {loaded = false, profile = nil, error = nil}
  end)
end

local function load_import_profile(context)
  local state = import_state(context)
  if state.loaded then return state.profile end
  state.loaded = true

  local text = raw_setting(profile_codec.import_setting_name)
  if text == nil or text == "" then return nil end

  local profile, err = profile_codec.decode(text)
  if not profile then
    state.error = err
    if log then
      log("[more-infinite-research] Ignoring invalid MIR settings profile import: " .. tostring(err))
    end
    return nil
  end

  state.profile = profile
  return state.profile
end

function M.raw(name)
  return raw_setting(name)
end

function M.get(name, context)
  local profile = load_import_profile(context)
  if profile and name ~= profile_codec.import_setting_name and setting_exists(name) then
    local imported = profile.settings and profile.settings[name]
    if imported ~= nil and settings_catalog.validate_value(name, imported) then
      return imported
    end
  end

  return raw_setting(name)
end

function M.import_status(context)
  load_import_profile(context)
  local state = import_state(context)

  if state.profile then
    local recognized, unknown, invalid = profile_codec.count_recognized_settings(state.profile)
    return {
      active = true,
      recognized = recognized,
      unknown = unknown,
      invalid = invalid,
      error = nil
    }
  end

  return {
    active = false,
    recognized = 0,
    unknown = 0,
    invalid = 0,
    error = state.error
  }
end

function M.active_profile(context)
  return deepcopy(load_import_profile(context))
end

function M.snapshot(context)
  local values = {}
  for _, name in ipairs(settings_catalog.setting_names({registered_only = true})) do
    values[name] = M.get(name, context)
  end
  local result = {
    schema = 1,
    values = values,
    import_status = M.import_status(context),
    imported_profile = M.active_profile(context)
  }
  result.settings_fingerprint = fingerprint.of({
    values = result.values,
    import_status = result.import_status,
    imported_profile = result.imported_profile
  })
  return result
end

return M
