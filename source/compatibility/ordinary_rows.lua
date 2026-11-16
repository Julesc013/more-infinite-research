-- Read-only ordinary ingredient/product rows shared by material adapters.
-- Callers select the native product stats alias and retain route/owner policy.
local M = {}

local function entry_name(entry)
  return type(entry) == "table" and (entry.name or entry[1]) or nil
end

local function entry_amount(entry)
  return type(entry) == "table" and (entry.amount or entry[2]) or nil
end

function M.matches(actual, expected, product_stats_alias)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" then return false end
    local ignored = row.ignored_by_productivity
    if product_stats_alias == true and ignored == nil then
      ignored = row.ignored_by_stats
    end
    if (row.type or "item") ~= wanted.type
        or entry_name(row) ~= wanted.name or entry_amount(row) ~= wanted.amount
        or row.amount_min ~= nil or row.amount_max ~= nil
        or (row.probability ~= nil and row.probability ~= 1)
        or (row.independent_probability ~= nil and row.independent_probability ~= 1)
        or (row.shared_probability ~= nil and (type(row.shared_probability) ~= "table"
          or row.shared_probability.min ~= 0 or row.shared_probability.max ~= 1))
        or (row.catalyst_amount ~= nil and row.catalyst_amount ~= 0)
        or (ignored ~= nil and ignored ~= 0)
        or (row.extra_count_fraction ~= nil and row.extra_count_fraction ~= 0) then
      return false
    end
  end
  return true
end

return M
