local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

function M.remove_technology_and_prereq_refs(tech_name)
  if not tech_name then return end

  local technologies = data_raw.prototypes("technology")
  technologies[tech_name] = nil

  for _, tech in pairs(technologies) do
    local prerequisites = tech.prerequisites
    if prerequisites then
      local out = {}
      local changed = false
      for _, prereq in ipairs(prerequisites) do
        if prereq == tech_name then
          changed = true
        else
          table.insert(out, prereq)
        end
      end
      if changed then
        tech.prerequisites = #out > 0 and out or nil
      end
    end
  end
end

return M
