local M = {}
local ONE_MIB = 1024 * 1024
local metrics = {
  canonical_calls = 0,
  canonical_bytes = 0,
  fingerprint_calls = 0,
  serializations_over_one_mib = 0,
  maximum_canonical_bytes = 0
}

local function map_keys(value, path)
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
      error("Fingerprint map keys must be strings or numbers at " .. path
        .. " (found " .. key_kind .. " key " .. tostring(key) .. ")", 4)
    end
  end
  return keys
end

local function table_shape(value, path)
  local first_key = next(value)
  if first_key == nil then return true end
  if type(first_key) ~= "number" or first_key < 1 or first_key % 1 ~= 0 then
    return false, map_keys(value, path)
  end
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false, map_keys(value, path)
    end
    count = count + 1
    if key > maximum then maximum = key end
  end
  if count == maximum then return true end
  return false, map_keys(value, path)
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
    for index = 1, #value do
      local child = value[index]
      local child_kind = type(child)
      local child_path = path
      if child_kind == "table"
        or (child_kind ~= "nil" and child_kind ~= "boolean"
          and child_kind ~= "number" and child_kind ~= "string") then
        child_path = path .. "[" .. index .. "]"
      end
      out[index] = encode(child, seen, child_path)
    end
    seen[value] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end

  table.sort(keys, function(left, right) return left.sort_key < right.sort_key end)
  for _, row in ipairs(keys) do
    local child = value[row.key]
    local child_kind = type(child)
    local child_path = path
    if child_kind == "table"
      or (child_kind ~= "nil" and child_kind ~= "boolean"
        and child_kind ~= "number" and child_kind ~= "string") then
      child_path = path .. row.path
    end
    out[#out + 1] = row.encoded .. ":" .. encode(child, seen, child_path)
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
