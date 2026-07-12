local technologies = data.raw.technology or {}

for technology_name, technology in pairs(technologies) do
  if string.match(technology_name, "^recipe%-prod%-research_") then
    for _, prerequisite_name in ipairs((technology and technology.prerequisites) or {}) do
      local prerequisite = technologies[prerequisite_name]
      if prerequisite and prerequisite.enabled == false then
        error("MIR validation failed: generated technology " .. technology_name
          .. " depends on disabled technology " .. prerequisite_name .. ".")
      end
    end
  end
end
