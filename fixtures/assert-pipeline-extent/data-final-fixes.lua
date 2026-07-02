local DEFAULT_PIPELINE_EXTENT = 320

local function fail(message)
  error("MIR pipeline extent validation failed: " .. message)
end

local function startup_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local multiplier = tonumber(startup_setting("mir-pipeline-extent-multiplier")) or 1
if multiplier <= 1 then return end

local expected = math.floor((DEFAULT_PIPELINE_EXTENT * multiplier) + 0.5)

local function assert_extent(label, box)
  if not box then return end
  if box.max_pipeline_extent ~= expected then
    fail(label .. " max_pipeline_extent was " .. tostring(box.max_pipeline_extent)
      .. ", expected " .. tostring(expected) .. ".")
  end
end

assert_extent("pipe", data.raw.pipe and data.raw.pipe.pipe and data.raw.pipe.pipe.fluid_box)
assert_extent("pipe-to-ground", data.raw["pipe-to-ground"]
  and data.raw["pipe-to-ground"]["pipe-to-ground"]
  and data.raw["pipe-to-ground"]["pipe-to-ground"].fluid_box)
assert_extent("storage-tank", data.raw["storage-tank"]
  and data.raw["storage-tank"]["storage-tank"]
  and data.raw["storage-tank"]["storage-tank"].fluid_box)
