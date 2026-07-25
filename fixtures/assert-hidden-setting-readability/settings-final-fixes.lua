local function fail(message)
  error("MIR setting visibility validation failed: " .. message)
end

local setting_types = {
  "bool-setting",
  "int-setting",
  "double-setting",
  "string-setting"
}

local function setting_prototype(name)
  for _, prototype_type in ipairs(setting_types) do
    local prototype = data.raw[prototype_type] and data.raw[prototype_type][name]
    if prototype then return prototype end
  end
  fail("missing registered setting prototype " .. name .. ".")
end

local stream_setting_patterns = {
  "ips-enable-%s",
  "ips-cost-base-%s",
  "ips-cost-growth-%s",
  "ips-max-level-%s",
  "ips-research-time-%s",
  "ips-effect-per-level-%s"
}

local function assert_stream_hidden(stream_key, expected_hidden)
  for _, pattern in ipairs(stream_setting_patterns) do
    local name = string.format(pattern, stream_key)
    local prototype = setting_prototype(name)
    local actual_hidden = prototype.hidden == true
    if actual_hidden ~= expected_hidden then
      fail(name .. " hidden=" .. tostring(actual_hidden)
        .. ", expected " .. tostring(expected_hidden) .. ".")
    end
  end
end

for _, stream_key in ipairs({
  "research_auto_assembling_machine",
  "research_auto_lab"
}) do
  assert_stream_hidden(stream_key, true)
end

local space_age_active = mods and mods["space-age"] ~= nil
for _, stream_key in ipairs({
  "research_agricultural_growth_speed",
  "research_artificial_soil",
  "research_bacteria_cultivation",
  "research_bioflux",
  "research_breeding",
  "research_carbon",
  "research_carbon_fiber",
  "research_cargo_bay_unloading_distance",
  "research_cargo_landing_pad_count",
  "research_holmium",
  "research_ice",
  "research_lithium",
  "research_molten_metals",
  "research_quantum_processor",
  "research_spoilage_preservation",
  "research_supercapacitor",
  "research_superconductor",
  "research_thruster_fuel_productivity",
  "research_thruster_oxidizer_productivity",
  "research_tungsten"
}) do
  assert_stream_hidden(stream_key, not space_age_active)
end
