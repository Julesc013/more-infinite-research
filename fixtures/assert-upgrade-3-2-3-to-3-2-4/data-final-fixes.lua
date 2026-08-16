local version = mods["more-infinite-research"]
local function fail(message)
  error("MIR 3.2.3 to 3.2.4 research-cost validation failed: " .. message)
end

local old_settings = {
  ["ips-cost-base-research_gears"] = {type = "int-setting", value = 4321},
  ["ips-cost-growth-research_gears"] = {type = "double-setting", value = 1.25},
  ["mir-cost-base-worker-robots-storage"] = {type = "int-setting", value = 2345},
  ["mir-cost-growth-worker-robots-storage"] = {type = "double-setting", value = 1.1}
}

for name, row in pairs(old_settings) do
  local setting = data.raw[row.type] and data.raw[row.type][name]
  if not setting or setting.default_value ~= row.value then
    fail("existing setting changed or disappeared: " .. name)
  end
end

local stream_increment = data.raw["int-setting"]["ips-cost-linear-increment-research_gears"]
local continuation_increment = data.raw["int-setting"]["mir-cost-linear-increment-worker-robots-storage"]
if version == "3.2.3" then
  if stream_increment or continuation_increment then fail("linear increment setting existed in source package") end
elseif version == "3.2.4" then
  if not stream_increment or stream_increment.default_value ~= 0 then
    fail("stream linear increment default is not zero")
  end
  if not continuation_increment or continuation_increment.default_value ~= 0 then
    fail("base-continuation linear increment default is not zero")
  end
else
  fail("unexpected MIR version " .. tostring(version))
end

local technology = data.raw.technology["recipe-prod-research_gears-1"]
if not technology or not technology.unit then fail("gears productivity technology is missing") end
if technology.unit.count_formula ~= "4321*1.25^(L-1)" then
  fail("default-zero increment changed the existing gears formula: "
    .. tostring(technology.unit.count_formula))
end
