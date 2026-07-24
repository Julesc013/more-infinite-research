local M = {}
local ONE_MIB = 1024 * 1024
local metrics = {
  canonical_calls = 0,
  canonical_bytes = 0,
  fingerprint_calls = 0,
  serializations_over_one_mib = 0,
  maximum_canonical_bytes = 0
}

local function is_array(value)
  local count, maximum = 0, 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
    if key > maximum then maximum = key end
  end
  return count == maximum
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
  if is_array(value) then
    for index = 1, #value do out[index] = encode(value[index], seen, path .. "[" .. index .. "]") end
    seen[value] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end

  local keys = {}
  for key, _ in pairs(value) do
    local key_kind = type(key)
    if key_kind == "string" then
      table.insert(keys, {key = key, sort_key = "s:" .. key, encoded = string.format("%q", key), path = "." .. key})
    elseif key_kind == "number" then
      local encoded = string.format("%.17g", key)
      table.insert(keys, {key = key, sort_key = "n:" .. encoded, encoded = "[" .. encoded .. "]", path = "[" .. encoded .. "]"})
    else
      error("Fingerprint map keys must be strings or numbers at " .. path
        .. " (found " .. key_kind .. " key " .. tostring(key) .. ")", 3)
    end
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

function M.of(value)
  metrics.fingerprint_calls = metrics.fingerprint_calls + 1
  local text = M.canonical(value)
  local hash = 2166136261
  for index = 1, #text do
    hash = (hash * 65599 + string.byte(text, index)) % 4294967291
  end
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
