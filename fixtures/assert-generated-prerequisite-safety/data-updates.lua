local anchor = data.raw.technology and data.raw.technology["worker-robots-storage-3"]
if not anchor then
  error("MIR generated prerequisite safety fixture requires worker-robots-storage-3.")
end

anchor.enabled = false

local automation_science = data.raw.technology and data.raw.technology["automation-science-pack"]
if not automation_science then
  error("MIR generated prerequisite safety fixture requires automation-science-pack technology.")
end

automation_science.enabled = false

local automation_science_recipe = data.raw.recipe and data.raw.recipe["automation-science-pack"]
if not automation_science_recipe then
  error("MIR generated prerequisite safety fixture requires automation-science-pack recipe.")
end

automation_science_recipe.enabled = true
