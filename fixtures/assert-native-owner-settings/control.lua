local streams = {
  {key = "research_processing_unit", owner = "processing-unit-productivity"},
  {key = "research_plastic", owner = "plastic-bar-productivity"},
  {key = "research_low_density_structure", owner = "low-density-structure-productivity"},
  {key = "research_rocket_fuel", owner = "rocket-fuel-productivity"},
  {key = "research_steel", owner = "steel-plate-productivity"}
}

local function selected_maximum(row)
  local direct = settings.startup["ips-max-level-" .. row.key]
  local maximum = direct and tonumber(direct.value) or 0
  local profile_row = settings.startup["mir-settings-profile-import"]
  local text = profile_row and tostring(profile_row.value or "") or ""
  if text ~= "" then
    local json = text
    if string.sub(text, 1, 8) == "MIRSET1:" then json = helpers.decode_string(string.sub(text, 9)) end
    local profile = json and helpers.json_to_table(json) or nil
    local imported = profile and profile.settings and profile.settings["ips-max-level-" .. row.key]
    if type(imported) == "number" and imported >= 0 and imported == math.floor(imported) then
      maximum = imported
    end
  end
  return maximum
end

local function fail(message)
  error("MIR native-owner research-cap validation failed: " .. message)
end

local function clear_research(force)
  force.research_queue = nil
  if force.current_research then force.cancel_current_research() end
end

local function assert_finite_cap(force, row, maximum_level)
  local technology = force.technologies[row.owner]
  if not technology then fail("missing native owner " .. row.owner) end
  if technology.prototype.max_level < 4294967295 then
    fail(row.owner .. " runtime prototype maximum must remain infinite for lossless capping; got "
      .. tostring(technology.prototype.max_level))
  end

  clear_research(force)
  for _, prerequisite in pairs(technology.prerequisites) do
    prerequisite.research_recursive()
  end
  local offered = {}
  while force.add_research(technology) do
    if not force.current_research or force.current_research.name ~= row.owner then
      fail(row.owner .. " did not expose its accepted level as current research")
    end
    table.insert(offered, technology.level)
    clear_research(force)
    technology.researched = true
    if #offered > maximum_level + 1 then
      fail(row.owner .. " continued offering research past the configured maximum")
    end
  end
  -- Infinite repeated technologies expose the next research level after a
  -- completion. Therefore level=max+1 with researched=false means max is the
  -- highest completed level and no additional level may be offered.
  if technology.level ~= maximum_level + 1 or technology.researched or technology.enabled then
    fail(row.owner .. " did not stop after completing the configured absolute maximum; next-level="
      .. tostring(technology.level) .. " researched=" .. tostring(technology.researched)
      .. " enabled=" .. tostring(technology.enabled)
      .. " maximum-completed=" .. tostring(maximum_level))
  end
  force.research_queue = {technology}
  if force.current_research or #force.research_queue ~= 0 then
    fail(row.owner .. " retained queued research above configured maximum " .. tostring(maximum_level))
  end

  log("[mir-fixture] native-owner research cap enforced owner=" .. row.owner
    .. " maximum=" .. tostring(maximum_level)
    .. " next-level=" .. tostring(technology.level)
    .. " offered-levels=" .. table.concat(offered, ","))
end

local function assert_infinite_cap(force, row)
  local technology = force.technologies[row.owner]
  if not technology then fail("missing native owner " .. row.owner) end
  if technology.prototype.max_level < 4294967295 then
    fail(row.owner .. " did not retain an infinite runtime prototype at max=0")
  end
  if not technology.enabled then
    fail(row.owner .. " was disabled even though max=0 requests infinite progression")
  end
  clear_research(force)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  if not force.add_research(technology) then
    fail(row.owner .. " did not offer its next level at max=0")
  end
  clear_research(force)
end

script.on_init(function()
  local force = game.create_force("mir-native-owner-cap-fixture")
  force.enable_all_prototypes()
  local asserted = 0
  for _, row in ipairs(streams) do
    local maximum_level = selected_maximum(row)
    if maximum_level > 0 then
      assert_finite_cap(force, row, math.floor(maximum_level))
      asserted = asserted + 1
    else
      assert_infinite_cap(force, row)
      asserted = asserted + 1
    end
  end
  log("[mir-fixture] all native-owner research cap contracts enforced count=" .. tostring(asserted))
end)
