local M = {}
local ONE_MIB = 1024 * 1024
local metrics = {
  canonical_calls = 0,
  canonical_bytes = 0,
  fingerprint_calls = 0,
  serializations_over_one_mib = 0,
  maximum_canonical_bytes = 0
}

local function map_key_row(key, path)
  local key_kind = type(key)
  if key_kind == "string" then
    return {key = key, sort_key = "s:" .. key, encoded = string.format("%q", key), path = "." .. key}
  end
  if key_kind == "number" then
    local encoded = string.format("%.17g", key)
    return {key = key, sort_key = "n:" .. encoded, encoded = "[" .. encoded .. "]", path = "[" .. encoded .. "]"}
  end
  error("Fingerprint map keys must be strings or numbers at " .. path
    .. " (found " .. key_kind .. " key " .. tostring(key) .. ")", 4)
end

local function table_shape(value, path)
  local count, maximum = 0, 0
  local possible_array = true
  local pending_numeric_keys = {}
  local map_keys
  for key in pairs(value) do
    count = count + 1
    if possible_array and type(key) == "number" and key >= 1 and key % 1 == 0 then
      pending_numeric_keys[#pending_numeric_keys + 1] = key
      if key > maximum then maximum = key end
    else
      if possible_array then
        possible_array = false
        map_keys = {}
        for _, numeric_key in ipairs(pending_numeric_keys) do
          map_keys[#map_keys + 1] = map_key_row(numeric_key, path)
        end
        pending_numeric_keys = nil
      end
      map_keys[#map_keys + 1] = map_key_row(key, path)
    end
  end
  if possible_array and count == maximum then return true end
  if possible_array then
    map_keys = {}
    for _, numeric_key in ipairs(pending_numeric_keys) do
      map_keys[#map_keys + 1] = map_key_row(numeric_key, path)
    end
  end
  return false, map_keys
end

local function encode(value, seen, path)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return string.format("%.17g", value) end
  if kind == "string" then return string.format("%q", value) end
  if kind ~= "table" then error("Cannot fingerprint value of type " .. kind .. " at " .. path, 3) end
  if seen[value] then error("Cannot fingerprint cyclic table at " .. path .. " (first seen at " .. seen[value] .. ")", 3) end
  seen[value] = path

  local out = {}
  local array, keys = table_shape(value, path)
  if array then
    for index = 1, #value do out[index] = encode(value[index], seen, path .. "[" .. index .. "]") end
    seen[value] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end

  table.sort(keys, function(left, right) return left.sort_key < right.sort_key end)
  for _, row in ipairs(keys) do
    table.insert(out, row.encoded .. ":" .. encode(value[row.key], seen, path .. row.path))
  end
  seen[value] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

function M.canonical(value)
  local text = encode(value, {}, "$")
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
  local hash = 2166136261
  local index = 1
  local length = #text
  -- Preserve the exact MIR32 recurrence while amortizing the Lua-to-C call
  -- used to read canonical bytes. The modulus remains applied after every
  -- byte, so this is identity-compatible with the scalar implementation.
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
  return "mir32-" .. string.format("%08x", hash)
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
    serializations_over_one_mib = metrics.serializations_over_one_mib,
    maximum_canonical_bytes = metrics.maximum_canonical_bytes
  }
end

function M.reset_metrics()
  for key in pairs(metrics) do metrics[key] = 0 end
end

return M
