local M = {}

function M.merge_unique(sources)
  local merged = {}
  local owners = {}
  for _, source in ipairs(sources or {}) do
    local source_name = source.name or "unnamed"
    for key, spec in pairs(source.streams or {}) do
      if merged[key] ~= nil then
        error("Duplicate MIR stream id " .. tostring(key)
          .. " declared by " .. tostring(owners[key]) .. " and " .. tostring(source_name) .. ".", 2)
      end
      merged[key] = spec
      owners[key] = source_name
    end
  end
  return merged
end

return M
