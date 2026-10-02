local M = {}
local ONE_MIB = 1024 * 1024
local MAXIMUM_QUOTED_STRING_CACHE_ENTRIES = 4096
local quoted_string_cache = {}
local quoted_string_cache_entries = 0
local MAXIMUM_HASH_CACHE_ENTRIES = 4096
local MAXIMUM_HASH_CACHE_BYTES = 2 * ONE_MIB
local MAXIMUM_HASH_CACHE_TEXT_BYTES = 64 * 1024
local hash_cache, hash_cache_order = {}, {}
local hash_cache_first, hash_cache_entries, hash_cache_bytes = 1, 0, 0
local encode
local diagnose
local metrics = {
  canonical_calls = 0,
  canonical_bytes = 0,
  fingerprint_calls = 0,
  hash_cache_hits = 0,
  hash_computations = 0,
  serializations_over_one_mib = 0,
  maximum_canonical_bytes = 0
}

local function map_keys(value, path, diagnostic, root)
  local keys = {}
  for key in pairs(value) do
    local key_kind = type(key)
    if key_kind == "string" then
      keys[#keys + 1] = {
        key = key, sort_key = "s:" .. key, encoded = string.format("%q", key), path = "." .. key
      }
    elseif key_kind == "number" then
      local encoded = string.format("%.17g", key)
      keys[#keys + 1] = {
        key = key, sort_key = "n:" .. encoded, encoded = "[" .. encoded .. "]", path = "[" .. encoded .. "]"
      }
    else
      if not diagnostic then return diagnose(root) end
      error("Fingerprint map keys must be strings or numbers at " .. path
        .. " (found " .. key_kind .. " key " .. tostring(key) .. ")", 4)
    end
  end
  return keys
end

local function string_map_keys(value)
  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" then return nil end
    keys[#keys + 1] = key
  end
  return keys
end

local function quoted_string(value)
  local encoded = quoted_string_cache[value]
  if encoded then return encoded end
  encoded = string.format("%q", value)
  if quoted_string_cache_entries < MAXIMUM_QUOTED_STRING_CACHE_ENTRIES then
    quoted_string_cache[value] = encoded
    quoted_string_cache_entries = quoted_string_cache_entries + 1
  end
  return encoded
end

local function table_shape(value, path, diagnostic, root)
  local first_key = next(value)
  if first_key == nil then return true end
  if type(first_key) == "string" then
    local keys = string_map_keys(value)
    if keys then return false, keys, true end
    return false, map_keys(value, path, diagnostic, root)
  end
  if type(first_key) ~= "number" or first_key < 1 or first_key % 1 ~= 0 then
    return false, map_keys(value, path, diagnostic, root)
  end
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false, map_keys(value, path, diagnostic, root)
    end
    count = count + 1
    if key > maximum then maximum = key end
  end
  if count == maximum then return true end
  return false, map_keys(value, path, diagnostic, root)
end

-- Append into one canonical buffer. Nested records must keep their complete
-- traversal and validation, but need no intermediate serialized strings.
encode = function(value, seen, path, diagnostic, root, out)
  local kind = type(value)
  if kind == "nil" then out[#out + 1] = "null"; return end
  if kind == "boolean" then out[#out + 1] = value and "true" or "false"; return end
  if kind == "number" then out[#out + 1] = string.format("%.17g", value); return end
  if kind == "string" then out[#out + 1] = quoted_string(value); return end
  if kind ~= "table" then
    if not diagnostic then return diagnose(root) end
    error("Cannot fingerprint value of type " .. kind .. " at " .. path, 3)
  end
  if seen[value] then
    if not diagnostic then return diagnose(root) end
    error("Cannot fingerprint cyclic table at " .. path .. " (first seen at " .. seen[value] .. ")", 3)
  end
  seen[value] = diagnostic and path or true

  local array, keys, string_keys = table_shape(value, path, diagnostic, root)
  if array then
    out[#out + 1] = "["
    for index = 1, #value do
      if index > 1 then out[#out + 1] = "," end
      local child = value[index]
      local child_kind = type(child)
      local child_path = path
      if diagnostic and (child_kind == "table"
        or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string")) then
        child_path = path .. "[" .. index .. "]"
      end
      encode(child, seen, child_path, diagnostic, root, out)
    end
    seen[value] = nil
    out[#out + 1] = "]"
    return
  end

  out[#out + 1] = "{"
  if string_keys then
    table.sort(keys)
    for index, key in ipairs(keys) do
      if index > 1 then out[#out + 1] = "," end
      local child = value[key]
      local child_kind = type(child)
      local child_path = path
      if diagnostic and (child_kind == "table"
        or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string")) then
        child_path = path .. "." .. key
      end
      out[#out + 1] = quoted_string(key)
      out[#out + 1] = ":"
      encode(child, seen, child_path, diagnostic, root, out)
    end
    seen[value] = nil
    out[#out + 1] = "}"
    return
  end

  table.sort(keys, function(left, right) return left.sort_key < right.sort_key end)
  for index, row in ipairs(keys) do
    if index > 1 then out[#out + 1] = "," end
    local child = value[row.key]
    local child_kind = type(child)
    local child_path = path
    if diagnostic and (child_kind == "table"
      or (child_kind ~= "nil" and child_kind ~= "boolean"
        and child_kind ~= "number" and child_kind ~= "string")) then
      child_path = path .. row.path
    end
    out[#out + 1] = row.encoded
    out[#out + 1] = ":"
    encode(child, seen, child_path, diagnostic, root, out)
  end
  seen[value] = nil
  out[#out + 1] = "}"
end

diagnose = function(root)
  encode(root, {}, "$", true, root, {})
  error("Fingerprint diagnostic traversal did not reproduce invalid input.", 3)
end

function M.canonical(value)
  local out = {}
  encode(value, {}, "$", false, value, out)
  local text = table.concat(out)
  local bytes = #text
  metrics.canonical_calls = metrics.canonical_calls + 1
  metrics.canonical_bytes = metrics.canonical_bytes + bytes
  metrics.maximum_canonical_bytes = math.max(metrics.maximum_canonical_bytes, bytes)
  if bytes > ONE_MIB then
    metrics.serializations_over_one_mib = metrics.serializations_over_one_mib + 1
  end
  return text
end

local function hash_canonical(text)
  -- Canonical strings are immutable. Reuse only an exact string's digest;
  -- callers still serialize current values and perform their normal checks.
  -- Never memoize a mutable table's identity or its verification result.
  local cached = hash_cache[text]
  if cached then
    metrics.hash_cache_hits = metrics.hash_cache_hits + 1
    return cached
  end
  metrics.hash_computations = metrics.hash_computations + 1
  local hash = 2166136261
  local index = 1
  local length = #text
  -- Preserve the exact MIR32 recurrence while amortizing the Lua-to-C call
  -- used to read canonical bytes. The modulus remains applied after every
  -- byte, so this is identity-compatible with the scalar implementation.
  while index + 15 <= length do
    local b1, b2, b3, b4, b5, b6, b7, b8,
      b9, b10, b11, b12, b13, b14, b15, b16 = string.byte(text, index, index + 15)
    hash = (hash * 65599 + b1) % 4294967291
    hash = (hash * 65599 + b2) % 4294967291
    hash = (hash * 65599 + b3) % 4294967291
    hash = (hash * 65599 + b4) % 4294967291
    hash = (hash * 65599 + b5) % 4294967291
    hash = (hash * 65599 + b6) % 4294967291
    hash = (hash * 65599 + b7) % 4294967291
    hash = (hash * 65599 + b8) % 4294967291
    hash = (hash * 65599 + b9) % 4294967291
    hash = (hash * 65599 + b10) % 4294967291
    hash = (hash * 65599 + b11) % 4294967291
    hash = (hash * 65599 + b12) % 4294967291
    hash = (hash * 65599 + b13) % 4294967291
    hash = (hash * 65599 + b14) % 4294967291
    hash = (hash * 65599 + b15) % 4294967291
    hash = (hash * 65599 + b16) % 4294967291
    index = index + 16
  end
  while index + 7 <= length do
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(text, index, index + 7)
    hash = (hash * 65599 + b1) % 4294967291
    hash = (hash * 65599 + b2) % 4294967291
    hash = (hash * 65599 + b3) % 4294967291
    hash = (hash * 65599 + b4) % 4294967291
    hash = (hash * 65599 + b5) % 4294967291
    hash = (hash * 65599 + b6) % 4294967291
    hash = (hash * 65599 + b7) % 4294967291
    hash = (hash * 65599 + b8) % 4294967291
    index = index + 8
  end
  while index <= length do
    hash = (hash * 65599 + string.byte(text, index)) % 4294967291
    index = index + 1
  end
  local result = "mir32-" .. string.format("%08x", hash)
  if length <= MAXIMUM_HASH_CACHE_TEXT_BYTES then
    while hash_cache_entries >= MAXIMUM_HASH_CACHE_ENTRIES
      or hash_cache_bytes + length > MAXIMUM_HASH_CACHE_BYTES do
      local oldest = hash_cache_order[hash_cache_first]
      hash_cache[oldest] = nil
      hash_cache_order[hash_cache_first] = nil
      hash_cache_bytes = hash_cache_bytes - #oldest
      hash_cache_first = hash_cache_first % MAXIMUM_HASH_CACHE_ENTRIES + 1
      hash_cache_entries = hash_cache_entries - 1
    end
    local slot = (hash_cache_first + hash_cache_entries - 1) % MAXIMUM_HASH_CACHE_ENTRIES + 1
    hash_cache_order[slot] = text
    hash_cache[text] = result
    hash_cache_entries = hash_cache_entries + 1
    hash_cache_bytes = hash_cache_bytes + length
  end
  return result
end

function M.of(value)
  metrics.fingerprint_calls = metrics.fingerprint_calls + 1
  local text = M.canonical(value)
  return hash_canonical(text)
end

function M.of_canonical(text)
  if type(text) ~= "string" then error("Canonical fingerprint text is required.", 2) end
  metrics.fingerprint_calls = metrics.fingerprint_calls + 1
  return hash_canonical(text)
end

function M.metrics()
  return {
    canonical_calls = metrics.canonical_calls,
    canonical_bytes = metrics.canonical_bytes,
    fingerprint_calls = metrics.fingerprint_calls,
    hash_cache_hits = metrics.hash_cache_hits,
    hash_computations = metrics.hash_computations,
    hash_cache_entries = hash_cache_entries,
    hash_cache_bytes = hash_cache_bytes,
    serializations_over_one_mib = metrics.serializations_over_one_mib,
    maximum_canonical_bytes = metrics.maximum_canonical_bytes
  }
end

function M.reset_metrics()
  for key in pairs(metrics) do metrics[key] = 0 end
end

return M
