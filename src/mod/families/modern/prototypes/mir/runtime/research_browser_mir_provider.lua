-- MIR projection adapter. It publishes bounded scalar enrichment facts and
-- never returns a compiler object or Factorio userdata to the portable core.
local M = {schema = 1, catalogue_limit = 30000}

local function mod_data(name)
  local prototype = prototypes.mod_data and prototypes.mod_data[name]
  return prototype and prototype.data or {}
end

function M.snapshot()
  local caps, families, details, known = {}, {}, {}, {}
  local count = 0
  local function admit(name)
    if type(name) ~= "string" then return false end
    if not known[name] then
      if count >= M.catalogue_limit then return false end
      known[name], count = true, count + 1
    end
    return true
  end
  for _, binding in ipairs(mod_data("more-infinite-research-maximum-level-policy").bindings or {}) do
    if admit(binding.technology) and type(binding.selected) == "number" and binding.selected > 0 then caps[binding.technology] = binding.selected end
  end
  for _, row in ipairs(mod_data("more-infinite-research-generation-plan").rows or {}) do
    if admit(row.technology_id) and type(row.stream_id) == "string" then
      families[row.technology_id] = row.stream_id
      details[row.technology_id] = {family = row.stream_id, action = type(row.action) == "string" and row.action or "external"}
    end
  end
  return {schema = M.schema, kind = "mir-research-enrichment", caps = caps, families = families, details = details}
end

return M
