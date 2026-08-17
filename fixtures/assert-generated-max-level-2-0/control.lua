local setting_names = {
  "ips-max-level-research_processing_unit",
  "ips-max-level-research_plastic",
  "ips-max-level-research_low_density_structure",
  "ips-max-level-research_rocket_fuel",
  "ips-max-level-research_steel"
}
local expected_maximum = settings.startup[setting_names[1]].value
for _, setting_name in ipairs(setting_names) do
  if settings.startup[setting_name].value ~= expected_maximum then
    error("MIR Factorio 2.0 generated maximum-level validation requires one shared family cap")
  end
end
local technologies = {
  {key = "research_processing_unit", name = "recipe-prod-research_processing_unit-1"},
  {key = "research_plastic", name = "recipe-prod-research_plastic-1"},
  {key = "research_low_density_structure", name = "recipe-prod-research_low_density_structure-1"},
  {key = "research_rocket_fuel", name = "recipe-prod-research_rocket_fuel-1"},
  {key = "research_steel", name = "recipe-prod-research_steel-1"}
}

local function fail(message)
  error("MIR Factorio 2.0 generated maximum-level validation failed: " .. message)
end

local function clear_research(force)
  force.research_queue = nil
  if force.current_research then force.cancel_current_research() end
end

script.on_init(function()
  local force = game.create_force("mir-generated-cap-2-0-fixture")
  force.enable_all_prototypes()
  for _, row in ipairs(technologies) do
    local technology = force.technologies[row.name]
    if not technology then fail("missing generated technology " .. row.name) end
    if technology.prototype.max_level < 4294967295 then fail("prototype is not infinite for " .. row.name) end
    for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
    if expected_maximum == 0 then
      technology.level = 13
      if not force.add_research(technology) then fail("infinite cap rejected level 13 for " .. row.name) end
      clear_research(force)
      if not technology.enabled then fail("infinite cap disabled " .. row.name) end
    else
      local offered = {}
      while force.add_research(technology) do
        if not force.current_research or force.current_research.name ~= row.name then
          fail("accepted level was not current research for " .. row.name)
        end
        table.insert(offered, technology.level)
        clear_research(force)
        technology.researched = true
        if #offered > expected_maximum + 1 then fail("research continued past the cap for " .. row.name) end
      end
      if technology.level ~= expected_maximum + 1 or technology.researched or technology.enabled then
        fail(row.name .. " did not stop after absolute level " .. tostring(expected_maximum))
      end
    end
  end
  local imported = settings.startup["mir-settings-profile-import"].value ~= ""
  log("[mir-fixture] Factorio 2.0 five generated maximum-level caps enforced maximum="
    .. tostring(expected_maximum) .. " transport=" .. (imported and "MIRSET1" or "direct"))
end)
