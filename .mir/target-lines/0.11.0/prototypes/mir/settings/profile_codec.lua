local settings_catalog = require("prototypes.mir.settings.catalog")

local M = {}

M.schema = 1
M.kind = "mir-settings-profile"
M.format = 1
M.prefix = "MIRSET1:"
M.import_setting_name = settings_catalog.import_setting_name
M.codec = "canonical-json-deflate-base64"

local function starts_with(text, prefix)
  return string.sub(text, 1, #prefix) == prefix
end

local function helpers_available()
  return helpers
    and helpers.json_to_table
    and helpers.encode_string
    and helpers.decode_string
end

local function setting_value(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function setting_exists(name)
  return settings and settings.startup and settings.startup[name] ~= nil
end

local function json_escape(value)
  local escape_map = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t"
  }
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    return escape_map[char] or string.format("\\u%04x", string.byte(char))
  end) .. '"'
end

local encode_json

local function is_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  local max = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
    count = count + 1
    if key > max then max = key end
  end
  return count == max
end

local function sorted_keys(value)
  local keys = {}
  for key, _ in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

encode_json = function(value)
  local value_type = type(value)
  if value_type == "nil" then return "null" end
  if value_type == "boolean" then return value and "true" or "false" end
  if value_type == "number" then return tostring(value) end
  if value_type == "string" then return json_escape(value) end
  if value_type ~= "table" then return json_escape(tostring(value)) end

  if is_array(value) then
    local chunks = {}
    for index = 1, #value do
      table.insert(chunks, encode_json(value[index]))
    end
    return "[" .. table.concat(chunks, ",") .. "]"
  end

  local chunks = {}
  for _, key in ipairs(sorted_keys(value)) do
    local item = value[key]
    if item ~= nil then
      table.insert(chunks, json_escape(key) .. ":" .. encode_json(item))
    end
  end
  return "{" .. table.concat(chunks, ",") .. "}"
end

local function copy_json_value(value)
  local value_type = type(value)
  if value_type == "string" or value_type == "number" or value_type == "boolean" then
    return value
  end
  if value_type ~= "table" then return nil end

  local out = {}
  for key, item in pairs(value) do
    local copied = copy_json_value(item)
    if copied ~= nil and (type(key) == "string" or type(key) == "number") then
      out[key] = copied
    end
  end
  return out
end

local function normalized_profile(profile)
  if type(profile) ~= "table" then
    return nil, "profile must be a table"
  end

  local schema = profile.schema or M.schema
  if schema ~= M.schema then
    return nil, "unsupported profile schema " .. tostring(schema)
  end

  local kind = profile.kind or M.kind
  if kind ~= M.kind then
    return nil, "unsupported profile kind " .. tostring(kind)
  end

  if profile.settings ~= nil and type(profile.settings) ~= "table" then
    return nil, "profile settings must be a table"
  end

  local settings_out = {}
  for name, value in pairs(profile.settings or {}) do
    local copied = copy_json_value(value)
    if copied ~= nil then
      settings_out[tostring(name)] = copied
    end
  end

  return {
    schema = M.schema,
    kind = M.kind,
    format = M.format,
    codec = M.codec,
    mod = profile.mod or "more-infinite-research",
    metadata = copy_json_value(profile.metadata or {}) or {},
    settings = settings_out
  }
end

function M.setting_names()
  return settings_catalog.setting_names({ registered_only = true })
end

function M.encode(profile)
  if not helpers_available() then
    return nil, "helpers JSON/string codec is not available"
  end

  local canonical, err = normalized_profile(profile)
  if not canonical then return nil, err end

  local json = encode_json(canonical)
  local encoded = helpers.encode_string(json)
  if not encoded then return nil, "profile string encoding failed" end

  return M.prefix .. encoded
end

local function migrate_profile(profile)
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

  profile.kind = M.kind
  profile.format = profile.format or M.format
  profile.codec = profile.codec or M.codec
  profile.metadata = type(profile.metadata) == "table" and profile.metadata or {}
  return profile
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
  return migrate_profile(profile)
end

function M.current_profile(options)
  options = options or {}
  local names = options.names or M.setting_names()
  local value_resolver = options.value_resolver
  local compact = options.compact == true
  local profile = {
    schema = M.schema,
    kind = M.kind,
    format = M.format,
    codec = M.codec,
    mod = "more-infinite-research",
    metadata = options.metadata or {},
    settings = {}
  }

  if compact then
    profile.metadata.export_mode = "compact"
  else
    profile.metadata.export_mode = "full"
  end

  for _, name in ipairs(names) do
    local value = value_resolver and value_resolver(name) or setting_value(name)
    if value ~= nil and (not compact or not settings_catalog.is_default_value(name, value)) then
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

function M.profile_status(profile)
  local status = {
    recognized = 0,
    unknown = 0,
    invalid = 0
  }

  for name, value in pairs((profile and profile.settings) or {}) do
    if name == M.import_setting_name or not setting_exists(name) or not settings_catalog.spec(name) then
      status.unknown = status.unknown + 1
    else
      local valid = settings_catalog.validate_value(name, value)
      if valid then
        status.recognized = status.recognized + 1
      else
        status.invalid = status.invalid + 1
      end
    end
  end

  return status
end

function M.count_recognized_settings(profile)
  local status = M.profile_status(profile)
  return status.recognized, status.unknown, status.invalid
end

return M
