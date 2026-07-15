local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

local RANK = {
  ["target-exclusion"] = 1,
  ["exact-deny"] = 2,
  ["exact-reviewed"] = 3,
  ["compatibility-pack-hint"] = 4,
  ["generic-structural"] = 5,
  ["low-confidence-heuristic"] = 6,
  ["unresolved-diagnostic"] = 7
}

local function validate(signal)
  if type(signal) ~= "table" or type(signal.kind) ~= "string" or not RANK[signal.kind] then
    error("Unsupported compatibility precedence signal: " .. tostring(signal and signal.kind), 3)
  end
  if type(signal.id) ~= "string" or signal.id == "" then
    error("Compatibility precedence signal id is required", 3)
  end
  if type(signal.action) ~= "string" or signal.action == "" then
    error("Compatibility precedence signal action is required: " .. signal.id, 3)
  end
end

function M.resolve(signals)
  local rows = {}
  for _, signal in ipairs(signals or {}) do
    validate(signal)
    table.insert(rows, deepcopy(signal))
  end
  if #rows == 0 then
    return {kind = "unresolved-diagnostic", id = "implicit-unresolved", action = "diagnose"}
  end

  table.sort(rows, function(a, b)
    if RANK[a.kind] ~= RANK[b.kind] then return RANK[a.kind] < RANK[b.kind] end
    return a.id < b.id
  end)

  local target = nil
  local deny = nil
  local reviewed = nil
  for _, row in ipairs(rows) do
    if row.kind == "target-exclusion" and not target then target = row end
    if row.kind == "exact-deny" and not deny then deny = row end
    if row.kind == "exact-reviewed" and deny and row.overrides_reason == deny.reason then reviewed = row end
  end
  if target then return deepcopy(target) end
  if reviewed then return deepcopy(reviewed) end
  if deny then return deepcopy(deny) end

  local winningRank = RANK[rows[1].kind]
  local winningAction = rows[1].action
  for index = 2, #rows do
    if RANK[rows[index].kind] ~= winningRank then break end
    if rows[index].action ~= winningAction then
      error("Conflicting compatibility signals at equal precedence: " .. rows[1].id .. "," .. rows[index].id, 2)
    end
  end
  return deepcopy(rows[1])
end

function M.rank(kind)
  return RANK[kind]
end

return M
