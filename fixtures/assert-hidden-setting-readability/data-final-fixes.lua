local function fail(message)
  error("MIR setting registration validation failed: " .. message)
end

local function assert_startup_setting_readable(name)
  local setting = settings and settings.startup and settings.startup[name]
  if not setting then
    fail("missing startup setting " .. name .. ".")
  end

  if setting.value == nil then
    fail("startup setting " .. name .. " has no readable value.")
  end
end

local governed_stream_keys = {
  "research_tungsten",
  "research_lithium",
  "research_holmium",
  "research_thruster_fuel_productivity",
  "research_thruster_oxidizer_productivity",
  "research_breeding",
  "research_agricultural_growth_speed",
  "research_cargo_bay_unloading_distance",
  "research_cargo_landing_pad_count",
  "research_spoilage_preservation",
  "research_air_scrubbing_clean_filter",
  "research_ash_separation"
}

local stream_setting_patterns = {
  "ips-enable-%s",
  "ips-cost-base-%s",
  "ips-cost-growth-%s",
  "ips-max-level-%s",
  "ips-research-time-%s"
}

for _, stream_key in ipairs(governed_stream_keys) do
  for _, setting_pattern in ipairs(stream_setting_patterns) do
    assert_startup_setting_readable(string.format(setting_pattern, stream_key))
  end
end

if not (mods and mods["space-age"]) then
  local techs = data.raw.technology or {}
  for _, tech_name in ipairs({
    "recipe-prod-research_tungsten-1",
    "recipe-prod-research_lithium-1",
    "recipe-prod-research_holmium-1",
    "recipe-prod-research_thruster_fuel_productivity-1",
    "recipe-prod-research_thruster_oxidizer_productivity-1",
    "recipe-prod-research_breeding-1",
    "recipe-prod-research_agricultural_growth_speed-1",
    "recipe-prod-research_cargo_bay_unloading_distance-1",
    "recipe-prod-research_cargo_landing_pad_count-1",
    "recipe-prod-research_spoilage_preservation-1"
  }) do
    if techs[tech_name] then
      fail("base-only setting fixture expected " .. tech_name .. " to remain ungenerateable.")
    end
  end
end
