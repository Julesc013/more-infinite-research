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
  map_projection_calls = 0,
  shared_projection_bytes = 0,
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

-- Append into one canonical buffer using a cursor. Recomputing #out for
-- every token searches the growing array boundary on older Lua engines.
-- Nested records retain their complete traversal and validation.
encode = function(value, seen, path, diagnostic, root, out, count)
  local kind = type(value)
  if kind == "nil" then out[count + 1] = "null"; return count + 1 end
  if kind == "boolean" then out[count + 1] = value and "true" or "false"; return count + 1 end
  if kind == "number" then out[count + 1] = string.format("%.17g", value); return count + 1 end
  if kind == "string" then out[count + 1] = quoted_string(value); return count + 1 end
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
    count = count + 1
    out[count] = "["
    for index = 1, #value do
      if index > 1 then count = count + 1; out[count] = "," end
      local child = value[index]
      local child_path = path
      if diagnostic then
        local child_kind = type(child)
        if child_kind == "table" or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string") then
          child_path = path .. "[" .. index .. "]"
        end
      end
      count = encode(child, seen, child_path, diagnostic, root, out, count)
    end
    seen[value] = nil
    out[count + 1] = "]"
    return count + 1
  end

  count = count + 1
  out[count] = "{"
  if string_keys then
    table.sort(keys)
    for index, key in ipairs(keys) do
      if index > 1 then count = count + 1; out[count] = "," end
      local child = value[key]
      local child_path = path
      if diagnostic then
        local child_kind = type(child)
        if child_kind == "table" or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string") then
          child_path = path .. "." .. key
        end
      end
      out[count + 1] = quoted_string(key)
      out[count + 2] = ":"
      count = encode(child, seen, child_path, diagnostic, root, out, count + 2)
    end
    seen[value] = nil
    out[count + 1] = "}"
    return count + 1
  end

  table.sort(keys, function(left, right) return left.sort_key < right.sort_key end)
  for index, row in ipairs(keys) do
    if index > 1 then count = count + 1; out[count] = "," end
    local child = value[row.key]
    local child_path = path
    if diagnostic then
      local child_kind = type(child)
      if child_kind == "table" or (child_kind ~= "nil" and child_kind ~= "boolean"
        and child_kind ~= "number" and child_kind ~= "string") then
        child_path = path .. row.path
      end
    end
    out[count + 1] = row.encoded
    out[count + 2] = ":"
    count = encode(child, seen, child_path, diagnostic, root, out, count + 2)
  end
  seen[value] = nil
  out[count + 1] = "}"
  return count + 1
end

diagnose = function(root)
  encode(root, {}, "$", true, root, {}, 0)
  error("Fingerprint diagnostic traversal did not reproduce invalid input.", 3)
end

local function record_canonical_metrics(bytes)
  metrics.canonical_calls = metrics.canonical_calls + 1
  metrics.canonical_bytes = metrics.canonical_bytes + bytes
  metrics.maximum_canonical_bytes = math.max(metrics.maximum_canonical_bytes, bytes)
  if bytes > ONE_MIB then
    metrics.serializations_over_one_mib = metrics.serializations_over_one_mib + 1
  end
end

function M.canonical(value)
  local out = {}
  encode(value, {}, "$", false, value, out, 0)
  local text = table.concat(out)
  local bytes = #text
  record_canonical_metrics(bytes)
  return text
end

-- Traverse through the same canonical writer without retaining its complete
-- text. This remains a canonicalization pass for telemetry and preserves the
-- normal invalid-input diagnostics, while callers that need only a byte
-- budget do not allocate a second serialized copy of a trusted record.
function M.canonical_length(value)
  local bytes = 0
  local counting_sink = setmetatable({}, {
    __newindex = function(_, _, token)
      bytes = bytes + #token
    end
  })
  encode(value, {}, "$", false, value, counting_sink, 0)
  record_canonical_metrics(bytes)
  return bytes
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
  -- Expand sixteen applications of h' = (h * 65599 + byte) mod p into
  -- one polynomial reduction. Split the incoming 32-bit hash at 16 bits:
  -- both products and the entire sum then stay below 2^50, hence remain
  -- exact integers even on hosts whose Lua numbers are IEEE doubles.
  -- Coefficients are 65599^k mod p, with p = 4294967291; the high-word
  -- coefficient is (65536 * 65599^16) mod p. Public MIR32 bytes stay exact.
  while index + 15 <= length do
    local b1, b2, b3, b4, b5, b6, b7, b8,
      b9, b10, b11, b12, b13, b14, b15, b16 = string.byte(text, index, index + 15)
    hash = ((hash % 65536) * 995218484 + math.floor(hash / 65536) * 3560253589
      + b1 * 412560925 + b2 * 1384565098 + b3 * 3943398063 + b4 * 2768719420
      + b5 * 647177936 + b6 * 990682743 + b7 * 3942737328 + b8 * 3220614473
      + b9 * 3002971012 + b10 * 3426381976 + b11 * 506879193 + b12 * 1222258819
      + b13 * 780915824 + b14 * 8261510 + b15 * 65599 + b16) % 4294967291
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

-- A map and a smaller map projection often contain the same large owned
-- field. Encode and hash each field once, then compose the two exact MIR32
-- byte streams. No table identity or verification result is retained.
-- h(a .. b) = h(b) + (h(a) - initial) * 65599^#b (mod p).
-- Split products at 16 bits so every intermediate is below 2^49 on doubles.
local function multiply_mod(left, right)
  return ((left % 65536) * right
    + math.floor(left / 65536) * ((65536 * right) % 4294967291)) % 4294967291
end

local function power_for_length(length)
  local power, base = 1, 65599
  while length > 0 do
    if length % 2 == 1 then power = multiply_mod(power, base) end
    length = math.floor(length / 2)
    if length > 0 then base = multiply_mod(base, base) end
  end
  return power
end

local function append_fragment(hash, fragment_hash, power)
  return (fragment_hash + multiply_mod((hash - 2166136261) % 4294967291, power)) % 4294967291
end

function M.of_map_with_projection(value, projection_keys)
  if type(value) ~= "table" or type(projection_keys) ~= "table"
    or getmetatable(value) ~= nil or getmetatable(projection_keys) ~= nil then
    error("Fingerprint map projection requires a string-keyed map and key array.", 2)
  end
  -- Owned record roots and key arrays have no virtual fields. Refuse
  -- metatables rather than letting __pairs/__index define another projection.
  local keys = string_map_keys(value)
  local key_array = table_shape(projection_keys, "$", false, projection_keys)
  if not keys or not key_array then
    error("Fingerprint map projection requires a string-keyed map and key array.", 2)
  end
  local selected, selected_count = {}, 0
  for _, key in ipairs(projection_keys) do
    if type(key) ~= "string" or rawget(value, key) == nil or selected[key] then
      error("Fingerprint map projection keys must be distinct existing strings.", 2)
    end
    selected[key] = true
    selected_count = selected_count + 1
  end
  table.sort(keys)
  metrics.map_projection_calls = metrics.map_projection_calls + 1
  metrics.fingerprint_calls = metrics.fingerprint_calls + 2
  if #keys == 0 then
    record_canonical_metrics(2)
    record_canonical_metrics(2)
    local digest = hash_canonical("[]")
    return digest, digest, 2
  end

  local full_hash = (2166136261 * 65599 + 123) % 4294967291
  local projected_hash = full_hash
  local full_bytes, projected_bytes, projected_fields = 2, 2, 0
  for index, key in ipairs(keys) do
    local out = {}
    -- Keep the root in the ancestry set: a back-reference to the input map
    -- remains invalid, just as it is in the ordinary canonical traversal.
    encode(value[key], {[value] = true}, "$", false, value, out, 0)
    local fragment = quoted_string(key) .. ":" .. table.concat(out)
    local bytes = #fragment
    local fragment_hash = tonumber(string.sub(hash_canonical(fragment), 7), 16)
    local power = power_for_length(bytes)
    if index > 1 then
      full_hash = (full_hash * 65599 + 44) % 4294967291
      full_bytes = full_bytes + 1
    end
    full_hash = append_fragment(full_hash, fragment_hash, power)
    full_bytes = full_bytes + bytes
    if selected[key] then
      if projected_fields > 0 then
        projected_hash = (projected_hash * 65599 + 44) % 4294967291
        projected_bytes = projected_bytes + 1
      end
      projected_hash = append_fragment(projected_hash, fragment_hash, power)
      projected_bytes = projected_bytes + bytes
      projected_fields = projected_fields + 1
      metrics.shared_projection_bytes = metrics.shared_projection_bytes + bytes
    end
  end
  full_hash = (full_hash * 65599 + 125) % 4294967291
  record_canonical_metrics(full_bytes)
  record_canonical_metrics(projected_bytes)
  local full_digest = "mir32-" .. string.format("%08x", full_hash)
  if selected_count == 0 then return full_digest, hash_canonical("[]"), 2 end
  projected_hash = (projected_hash * 65599 + 125) % 4294967291
  return full_digest, "mir32-" .. string.format("%08x", projected_hash), projected_bytes
end

function M.metrics()
  return {
    canonical_calls = metrics.canonical_calls,
    canonical_bytes = metrics.canonical_bytes,
    fingerprint_calls = metrics.fingerprint_calls,
    hash_cache_hits = metrics.hash_cache_hits,
    hash_computations = metrics.hash_computations,
    map_projection_calls = metrics.map_projection_calls,
    shared_projection_bytes = metrics.shared_projection_bytes,
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
