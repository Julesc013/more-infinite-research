local M = {}

local function same(left, right, seen)
  if left == right then return true end
  if type(left) ~= type(right) or type(left) ~= "table" then return false end
  local matches = seen[left]
  if matches and matches[right] then return true end
  matches = matches or {}
  seen[left] = matches
  matches[right] = true
  for key, value in pairs(left) do
    if not same(value, right[key], seen) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

function M.same(left, right)
  return same(left, right, {})
end

return M
