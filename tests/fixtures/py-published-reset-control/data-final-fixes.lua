-- This is a published-MIR-only, no-write closure guard.  It admits exactly
-- the two retained F200 Py selections and deliberately changes no prototype.
local FIXTURE = "mir-fixture-mir5-integration-catalogue-upgrade"
local FOREIGN_OWNER = "mir-fixture-mir5-integration-foreign-owner"
local OBSERVER = "mir-fixture-mir5-active-mods-observer"

local function fail(message)
  error("[mir5-py-published-reset-control] " .. message)
end

local function exactly(actual, expected)
  for name, version in pairs(expected) do
    if actual[name] ~= version then return false end
  end
  for name in pairs(actual) do
    if expected[name] == nil then return false end
  end
  return true
end

local own = {
  base = "2.0.77",
  [FIXTURE] = "0.2.0",
  [FOREIGN_OWNER] = "0.2.0",
  [OBSERVER] = "0.1.0",
  ["more-infinite-research"] = "4.7.20002",
}

local profiles = {
  ["py-coal"] = {
    pycoalprocessinggraphics = "3.0.9",
    pypostprocessing = "3.0.42",
    pycoalprocessing = "3.0.44",
  },
  ["py-alienlife-hightech"] = {
    pycoalprocessinggraphics = "3.0.9",
    pypostprocessing = "3.0.42",
    pycoalprocessing = "3.0.44",
    pyfusionenergygraphics = "3.0.4",
    pyfusionenergy = "3.0.17",
    pyindustrygraphics = "3.0.3",
    pyindustry = "3.0.21",
    pypetroleumhandlinggraphics = "3.0.5",
    pypetroleumhandling = "3.0.23",
    pyraworesgraphics = "3.0.4",
    pyrawores = "3.0.25",
    pyalienlifegraphics = "3.0.12",
    pyalienlifegraphics2 = "3.0.3",
    pyalienlifegraphics3 = "3.0.4",
    pyalienlife = "3.0.67",
    pyhightechgraphics = "3.0.3",
    pyhightech = "3.0.19",
  },
}

local admitted = 0
for name, expected in pairs(profiles) do
  local closure = {}
  for mod, version in pairs(own) do closure[mod] = version end
  for mod, version in pairs(expected) do closure[mod] = version end
  if exactly(mods, closure) then admitted = admitted + 1 end
end
if admitted ~= 1 then fail("data-stage closure is not one retained Py profile") end
