local M = {}

M.schema = 1
M.kind = "mir-settings-profile"
M.prefix = "MIRSET1:"
M.import_setting_name = "mir-settings-profile-import"

local function starts_with(text, prefix)
  return string.sub(text, 1, #prefix) == prefix
end

local function helpers_available()
  return helpers
    and helpers.table_to_json
    and helpers.json_to_table
    and helpers.encode_string
    and helpers.decode_string
end

local function setting_value(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function is_mir_setting_name(name)
  if name == M.import_setting_name then return false end
  return starts_with(name, "ips-") or starts_with(name, "mir-")
end

function M.setting_names()
  local out = {}
  if not (settings and settings.startup) then return out end

  for name, _ in pairs(settings.startup) do
    if is_mir_setting_name(name) then
      table.insert(out, name)
    end
  end

  table.sort(out)
  return out
end

function M.encode(profile)
  if type(profile) ~= "table" then
    return nil, "profile must be a table"
  end
  if not helpers_available() then
    return nil, "helpers JSON/string codec is not available"
  end

  profile.schema = profile.schema or M.schema
  profile.kind = profile.kind or M.kind

  local json = helpers.table_to_json(profile)
  if not json then return nil, "profile JSON encoding failed" end

  local encoded = helpers.encode_string(json)
  if not encoded then return nil, "profile string encoding failed" end

  return M.prefix .. encoded
end

function M.decode(text)
  if text == nil or text == "" then return nil, "empty" end
  if not helpers_available() then
    return nil, "helpers JSON/string codec is not available"
  end

  text = tostring(text)
  local json

  if starts_with(text, M.prefix) then
    local encoded = string.sub(text, #M.prefix + 1)
    if encoded == "" then return nil, "empty" end
    json = helpers.decode_string(encoded)
    if not json then return nil, "profile string decoding failed" end
  elseif string.match(text, "^%s*{") then
    json = text
  else
    return nil, "unsupported profile format"
  end

  local profile = helpers.json_to_table(json)
  if type(profile) ~= "table" then
    return nil, "profile JSON decoding failed"
  end
  if profile.schema ~= M.schema then
    return nil, "unsupported profile schema " .. tostring(profile.schema)
  end
  if profile.kind ~= nil and profile.kind ~= M.kind then
    return nil, "unsupported profile kind " .. tostring(profile.kind)
  end
  if type(profile.settings) ~= "table" then
    return nil, "profile settings must be a table"
  end

  return profile
end

function M.current_profile(options)
  options = options or {}
  local names = options.names or M.setting_names()
  local value_resolver = options.value_resolver
  local profile = {
    schema = M.schema,
    kind = M.kind,
    mod = "more-infinite-research",
    metadata = options.metadata or {},
    settings = {}
  }

  for _, name in ipairs(names) do
    local value = value_resolver and value_resolver(name) or setting_value(name)
    if value ~= nil then
      profile.settings[name] = value
    end
  end

  return profile
end

function M.count_settings(profile)
  local count = 0
  for _, _ in pairs((profile and profile.settings) or {}) do
    count = count + 1
  end
  return count
end

function M.count_recognized_settings(profile)
  local recognized = 0
  local unknown = 0

  for name, _ in pairs((profile and profile.settings) or {}) do
    if name ~= M.import_setting_name and settings and settings.startup and settings.startup[name] then
      recognized = recognized + 1
    else
      unknown = unknown + 1
    end
  end

  return recognized, unknown
end

return M
