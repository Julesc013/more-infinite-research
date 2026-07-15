local function fail(message)
  error("MIR reduced settings surface validation failed: " .. message)
end

local function startup_setting(name)
  return settings and settings.startup and settings.startup[name] or nil
end

local function assert_startup_setting(name)
  if not startup_setting(name) then
    fail("Reduced target setting surface is missing " .. name .. ".")
  end
end

local function assert_no_startup_setting(name)
  if startup_setting(name) then
    fail("Reduced target setting surface unexpectedly includes " .. name .. ".")
  end
end

for _, name in ipairs({
  "ips-enable-research_character_reach",
  "ips-cost-base-research_character_reach",
  "mir-lab-incompatibility-policy",
  "mir-adjust-vanilla-weapon-speed-techs",
  "mir-enable-research-speed"
}) do
  assert_startup_setting(name)
end

for _, name in ipairs({
  "ips-enable-research_gears",
  "ips-enable-research_air_scrubbing_clean_filter",
  "mir-pipeline-extent-multiplier",
  "mir-prototype-productivity-cap",
  "mir-prototype-efficiency-cap",
  "mir-prototype-pollution-cap",
  "mir-prototype-speed-cap",
  "mir-prototype-quality-cap",
  "mir-prototype-positive-power-floor",
  "mir-settings-profile-import",
  "mir-use-installed-space-age-icons"
}) do
  assert_no_startup_setting(name)
end

local continuation_locale = {
  ["braking-force"] = "braking-force",
  ["research-speed"] = "research-speed",
  ["worker-robots-storage"] = "worker-robots-storage",
  ["weapon-shooting-speed"] = "weapon-shooting-speed",
  ["laser-turret-speed"] = "laser-turret-speed"
}

local function assert_localised_reference(label, value, expected_key)
  if type(value) ~= "table" then
    fail(label .. " does not have an explicit localised string.")
  end
  if value[1] ~= expected_key then
    fail(label .. " locale key was " .. tostring(value[1]) .. ", expected " .. expected_key .. ".")
  end
end

for chain_key, locale_key in pairs(continuation_locale) do
  local highest
  for name, tech in pairs(data.raw.technology or {}) do
    local level = tonumber(string.match(name, "^" .. chain_key:gsub("([^%w])", "%%%1") .. "%-(%d+)$"))
    if level and tech.max_level == "infinite" and (not highest or level > highest.level) then
      highest = {
        level = level,
        name = name,
        tech = tech
      }
    end
  end
  if highest then
    assert_localised_reference(highest.name .. " localised_name", highest.tech.localised_name, "technology-name." .. locale_key)
    assert_localised_reference(highest.name .. " localised_description", highest.tech.localised_description, "technology-description." .. locale_key)
  end
end
