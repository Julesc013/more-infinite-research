local technology_name = "recipe-prod-research_copper-1"

local function fail(message)
  error("MIR generated maximum-level validation failed: " .. message)
end

local function clear_research(force)
  force.research_queue = nil
  if force.current_research then force.cancel_current_research() end
end

script.on_init(function()
  local maximum = settings.startup["ips-max-level-research_copper"].value
  local force = game.create_force("mir-generated-cap-fixture")
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology then fail("missing generated copper productivity technology") end
  if technology.prototype.max_level < 4294967295 then fail("prototype is not infinite") end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  local offered = {}
  while force.add_research(technology) do
    if not force.current_research or force.current_research.name ~= technology_name then
      fail("accepted level was not current research")
    end
    table.insert(offered, technology.level)
    clear_research(force)
    technology.researched = true
    if #offered > maximum + 1 then fail("research continued past the selected cap") end
  end
  if technology.level ~= maximum + 1 or technology.researched or technology.enabled then
    fail("technology did not stop after absolute level " .. tostring(maximum))
  end
  log("[mir-fixture] generated technology absolute research cap enforced maximum="
    .. tostring(maximum) .. " offered-levels=" .. table.concat(offered, ","))
end)
