-- Restricted MIRSET1 codec. It moves data only; it never applies settings.
local M = {
  schema = 1,
  kind = "mir-settings-profile",
  format = 1,
  prefix = "MIRSET1:",
  codec = "canonical-json-deflate-base64",
  import_setting_name = "mir-settings-profile-import"
}

local function helpers_available(helpers)
  return helpers and helpers.json_to_table and helpers.encode_string and helpers.decode_string
end

local function starts_with(text, prefix)
  return string.sub(text, 1, #prefix) == prefix
end

local function json_escape(value)
  local escaped = {['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
    return escaped[char] or string.format("\\u%04x", string.byte(char))
  end) .. '"'
end

local function is_array(value)
  if type(value) ~= "table" then return false end
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
    count = count + 1
    if key > maximum then maximum = key end
  end
  return count == maximum
end

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function finite(value)
  return value == value and value < math.huge and value > -math.huge
end

local function encode_json(value, seen)
  local value_type = type(value)
  if value_type == "nil" then return "null" end
  if value_type == "boolean" then return value and "true" or "false" end
  if value_type == "number" then
    if not finite(value) then return nil, "profile contains a non-finite number" end
    return tostring(value)
  end
  if value_type == "string" then return json_escape(value) end
  if value_type ~= "table" then return json_escape(tostring(value)) end
  if seen[value] then return nil, "profile contains a cycle" end
  seen[value] = true
  local chunks = {}
  if is_array(value) then
    for index = 1, #value do
      local encoded, err = encode_json(value[index], seen)
      if not encoded then seen[value] = nil; return nil, err end
      chunks[#chunks + 1] = encoded
    end
    seen[value] = nil
    return "[" .. table.concat(chunks, ",") .. "]"
  end
  for _, key in ipairs(sorted_keys(value)) do
    local item = value[key]
    if item ~= nil then
      local encoded, err = encode_json(item, seen)
      if not encoded then seen[value] = nil; return nil, err end
      chunks[#chunks + 1] = json_escape(key) .. ":" .. encoded
    end
  end
  seen[value] = nil
  return "{" .. table.concat(chunks, ",") .. "}"
end

local function copy_json_value(value, seen)
  local value_type = type(value)
  if value_type == "string" or value_type == "boolean" then return value end
  if value_type == "number" then return finite(value) and value or nil end
  if value_type ~= "table" or seen[value] then return nil end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do
    local copied = copy_json_value(item, seen)
    if copied ~= nil and (type(key) == "string" or type(key) == "number") then out[key] = copied end
  end
  seen[value] = nil
  return out
end

local function normalized_for_encode(profile)
  if type(profile) ~= "table" then return nil, "profile must be a table" end
  local schema = profile.schema or M.schema
  if schema ~= M.schema then return nil, "unsupported profile schema " .. tostring(schema) end
  local kind = profile.kind or M.kind
  if kind ~= M.kind then return nil, "unsupported profile kind " .. tostring(kind) end
  if profile.settings ~= nil and type(profile.settings) ~= "table" then return nil, "profile settings must be a table" end
  local settings = {}
  for name, value in pairs(profile.settings or {}) do
    local copied = copy_json_value(value, {})
    if copied ~= nil then settings[tostring(name)] = copied end
  end
  return {
    schema = M.schema, kind = M.kind, format = M.format, codec = M.codec,
    mod = profile.mod or "more-infinite-research",
    metadata = copy_json_value(profile.metadata or {}, {}) or {}, settings = settings
  }
end

function M.encode(profile, helpers)
  if not helpers_available(helpers) then return nil, "helpers JSON/string codec is not available" end
  local canonical, err = normalized_for_encode(profile)
  if not canonical then return nil, err end
  local json, json_err = encode_json(canonical, {})
  if not json then return nil, json_err end
  local encoded = helpers.encode_string(json)
  if not encoded then return nil, "profile string encoding failed" end
  return M.prefix .. encoded
end

local function migrate_profile(profile)
  if type(profile) ~= "table" then return nil, "profile JSON decoding failed" end
  if profile.schema ~= M.schema then return nil, "unsupported profile schema " .. tostring(profile.schema) end
  if profile.kind ~= nil and profile.kind ~= M.kind then return nil, "unsupported profile kind " .. tostring(profile.kind) end
  if type(profile.settings) ~= "table" then return nil, "profile settings must be a table" end
  return {
    schema = M.schema, kind = M.kind, format = profile.format or M.format,
    codec = profile.codec or M.codec, mod = profile.mod or "more-infinite-research",
    metadata = type(profile.metadata) == "table" and profile.metadata or {}, settings = profile.settings
  }
end

function M.decode(text, helpers)
  if text == nil or text == "" then return nil, "empty" end
  if not helpers_available(helpers) then return nil, "helpers JSON/string codec is not available" end
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
  return migrate_profile(helpers.json_to_table(json))
end

function M.current_profile(options)
  options = options or {}
  local compact = options.compact == true
  local profile = {
    schema = M.schema, kind = M.kind, format = M.format, codec = M.codec,
    mod = "more-infinite-research", metadata = options.metadata or {}, settings = {}
  }
  profile.metadata.export_mode = compact and "compact" or "full"
  for _, name in ipairs(options.names or {}) do
    local value = nil
    if options.value_resolver then value = options.value_resolver(name) end
    if value ~= nil and (not compact or not (options.is_default and options.is_default(name, value))) then
      profile.settings[name] = value
    end
  end
  return profile
end

function M.count_settings(profile)
  local count = 0
  for _ in pairs((profile and profile.settings) or {}) do count = count + 1 end
  return count
end

return M
