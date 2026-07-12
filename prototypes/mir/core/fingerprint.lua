local M = {}

local function is_array(value)
  local count, maximum = 0, 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
    if key > maximum then maximum = key end
  end
  return count == maximum
end

local function encode(value, seen)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return string.format("%.17g", value) end
  if kind == "string" then return string.format("%q", value) end
  if kind ~= "table" then error("Cannot fingerprint value of type " .. kind, 3) end
  if seen[value] then error("Cannot fingerprint cyclic table", 3) end
  seen[value] = true

  local out = {}
  if is_array(value) then
    for index = 1, #value do out[index] = encode(value[index], seen) end
    seen[value] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end

  local keys = {}
  for key, _ in pairs(value) do
    if type(key) ~= "string" then error("Fingerprint map keys must be strings", 3) end
    table.insert(keys, key)
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    table.insert(out, string.format("%q", key) .. ":" .. encode(value[key], seen))
  end
  seen[value] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

function M.canonical(value)
  return encode(value, {})
end

function M.of(value)
  local text = M.canonical(value)
  local hash = 2166136261
  for index = 1, #text do
    hash = (hash * 65599 + string.byte(text, index)) % 4294967291
  end
  return "mir32-" .. string.format("%08x", hash)
end

return M
