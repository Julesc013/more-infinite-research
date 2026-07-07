local M = {}

function M.exists(name)
  return mods ~= nil and mods[name] ~= nil
end

function M.all_exist(names)
  for _, name in ipairs(names or {}) do
    if not M.exists(name) then return false end
  end
  return true
end

return M
