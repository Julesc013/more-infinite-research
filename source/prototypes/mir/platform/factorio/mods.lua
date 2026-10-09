local M = {}

function M.exists(name)
  return mods ~= nil and mods[name] ~= nil
end

function M.version(name)
  if mods == nil then return nil end
  return mods[name]
end

function M.all_exist(names)
  for _, name in ipairs(names or {}) do
    if not M.exists(name) then return false end
  end
  return true
end

function M.snapshot()
  local out = {}
  for name, version in pairs(mods or {}) do
    out[name] = version
  end
  return out
end

return M
