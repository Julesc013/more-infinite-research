local function fail(message)
  error("MIR hidden setting validation failed: " .. message)
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

local hidden_stream_settings = {
  "ips-enable-research_tungsten",
  "ips-cost-base-research_tungsten",
  "ips-cost-growth-research_tungsten",
  "ips-max-level-research_tungsten",
  "ips-research-time-research_tungsten",
  "ips-enable-research_air_scrubbing_clean_filter",
  "ips-cost-base-research_air_scrubbing_clean_filter",
  "ips-cost-growth-research_air_scrubbing_clean_filter",
  "ips-max-level-research_air_scrubbing_clean_filter",
  "ips-research-time-research_air_scrubbing_clean_filter",
  "ips-enable-research_ash_separation",
  "ips-cost-base-research_ash_separation",
  "ips-cost-growth-research_ash_separation",
  "ips-max-level-research_ash_separation",
  "ips-research-time-research_ash_separation",
  "ips-enable-research_spoilage_preservation",
  "ips-cost-base-research_spoilage_preservation",
  "ips-cost-growth-research_spoilage_preservation",
  "ips-max-level-research_spoilage_preservation",
  "ips-research-time-research_spoilage_preservation"
}

for _, setting_name in ipairs(hidden_stream_settings) do
  assert_startup_setting_readable(setting_name)
end

if not (mods and mods["space-age"]) then
  local techs = data.raw.technology or {}
  for _, tech_name in ipairs({
    "recipe-prod-research_tungsten-1",
    "recipe-prod-research_spoilage_preservation-1"
  }) do
    if techs[tech_name] then
      fail("base-only hidden setting fixture expected " .. tech_name .. " to remain ungenerateable.")
    end
  end
end
