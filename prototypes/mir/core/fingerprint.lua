local M = {}
local ONE_MIB = 1024 * 1024
local MIR32_MODULUS = 4294967291
local MIR32_MULTIPLIER = 65599
local MIR32_RADIX = 65536
local MIR32_RADIX_MODULUS = 5
local MAXIMUM_QUOTED_STRING_CACHE_ENTRIES = 4096
local quoted_string_cache = {}
local quoted_string_cache_entries = 0
local encode
local diagnose
local metrics = {
  canonical_calls = 0,
  canonical_bytes = 0,
  fingerprint_calls = 0,
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

encode = function(value, seen, path, diagnostic, root)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return string.format("%.17g", value) end
  if kind == "string" then return quoted_string(value) end
  if kind ~= "table" then
    if not diagnostic then return diagnose(root) end
    error("Cannot fingerprint value of type " .. kind .. " at " .. path, 3)
  end
  if seen[value] then
    if not diagnostic then return diagnose(root) end
    error("Cannot fingerprint cyclic table at " .. path .. " (first seen at " .. seen[value] .. ")", 3)
  end
  seen[value] = diagnostic and path or true

  local out = {}
  local array, keys, string_keys = table_shape(value, path, diagnostic, root)
  if array then
    for index = 1, #value do
      local child = value[index]
      local child_kind = type(child)
      local child_path = path
      if diagnostic and (child_kind == "table"
        or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string")) then
        child_path = path .. "[" .. index .. "]"
      end
      out[index] = encode(child, seen, child_path, diagnostic, root)
    end
    seen[value] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end

  if string_keys then
    table.sort(keys)
    for _, key in ipairs(keys) do
      local child = value[key]
      local child_kind = type(child)
      local child_path = path
      if diagnostic and (child_kind == "table"
        or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string")) then
        child_path = path .. "." .. key
      end
      out[#out + 1] = quoted_string(key) .. ":" .. encode(child, seen, child_path, diagnostic, root)
    end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
  end

  table.sort(keys, function(left, right) return left.sort_key < right.sort_key end)
  for _, row in ipairs(keys) do
    local child = value[row.key]
    local child_kind = type(child)
    local child_path = path
    if diagnostic and (child_kind == "table"
      or (child_kind ~= "nil" and child_kind ~= "boolean"
        and child_kind ~= "number" and child_kind ~= "string")) then
      child_path = path .. row.path
    end
    out[#out + 1] = row.encoded .. ":" .. encode(child, seen, child_path, diagnostic, root)
  end
  seen[value] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

diagnose = function(root)
  encode(root, {}, "$", true, root)
  error("Fingerprint diagnostic traversal did not reproduce invalid input.", 3)
end

local function record_canonical_bytes(bytes)
  metrics.canonical_calls = metrics.canonical_calls + 1
  metrics.canonical_bytes = metrics.canonical_bytes + bytes
  metrics.maximum_canonical_bytes = math.max(metrics.maximum_canonical_bytes, bytes)
  if bytes > ONE_MIB then
    metrics.serializations_over_one_mib = metrics.serializations_over_one_mib + 1
  end
end

function M.canonical(value)
  local text = encode(value, {}, "$", false, value)
  record_canonical_bytes(#text)
  return text
end

local function hash_canonical(text)
  local hash = 2166136261
  local index = 1
  local length = #text
  -- Preserve the exact MIR32 recurrence while amortizing the Lua-to-C call
  -- used to read canonical bytes. The modulus remains applied after every
  -- byte, so this is identity-compatible with the scalar implementation.
  while index + 15 <= length do
    local b1, b2, b3, b4, b5, b6, b7, b8,
      b9, b10, b11, b12, b13, b14, b15, b16 = string.byte(text, index, index + 15)
    hash = (hash * MIR32_MULTIPLIER + b1) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b2) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b3) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b4) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b5) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b6) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b7) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b8) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b9) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b10) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b11) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b12) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b13) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b14) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b15) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b16) % MIR32_MODULUS
    index = index + 16
  end
  while index + 7 <= length do
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(text, index, index + 7)
    hash = (hash * MIR32_MULTIPLIER + b1) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b2) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b3) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b4) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b5) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b6) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b7) % MIR32_MODULUS
    hash = (hash * MIR32_MULTIPLIER + b8) % MIR32_MODULUS
    index = index + 8
  end
  while index <= length do
    hash = (hash * MIR32_MULTIPLIER + string.byte(text, index)) % MIR32_MODULUS
    index = index + 1
  end
  return "mir32-" .. string.format("%08x", hash)
end

local function multiply_mod32(left, right)
  local left_low = left % MIR32_RADIX
  local left_high = (left - left_low) / MIR32_RADIX
  local right_low = right % MIR32_RADIX
  local right_high = (right - right_low) / MIR32_RADIX
  local middle = left_low * right_high + left_high * right_low
  local middle_low = middle % MIR32_RADIX
  local middle_high = (middle - middle_low) / MIR32_RADIX
  return (
    left_low * right_low
    + middle_low * MIR32_RADIX
    + (middle_high + left_high * right_high) * MIR32_RADIX_MODULUS
  ) % MIR32_MODULUS
end

local function segment_transition(text)
  local factor, constant = 1, 0
  for index = 1, #text do
    factor = (factor * MIR32_MULTIPLIER) % MIR32_MODULUS
    constant = (constant * MIR32_MULTIPLIER + string.byte(text, index)) % MIR32_MODULUS
  end
  return {factor = factor, constant = constant, bytes = #text}
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

function M.of_canonical_segments(segments)
  if type(segments) ~= "table" then error("Canonical fingerprint segments are required.", 2) end
  local transitions, hash, bytes = {}, 2166136261, 0
  for index, segment in ipairs(segments) do
    if type(segment) ~= "string" then
      error("Canonical fingerprint segment " .. tostring(index) .. " must be a string.", 2)
    end
    local transition = transitions[segment]
    if not transition then
      transition = segment_transition(segment)
      transitions[segment] = transition
    end
    hash = (multiply_mod32(hash, transition.factor) + transition.constant) % MIR32_MODULUS
    bytes = bytes + transition.bytes
  end
  record_canonical_bytes(bytes)
  metrics.fingerprint_calls = metrics.fingerprint_calls + 1
  return "mir32-" .. string.format("%08x", hash)
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
