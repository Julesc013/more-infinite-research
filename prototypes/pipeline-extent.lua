local P = {}

local DEFAULT_PIPELINE_EXTENT = 320

local FLUID_BOX_FIELDS = {
  fluid_box = true,
  input_fluid_box = true,
  output_fluid_box = true,
  fuel_fluid_box = true,
  oxidizer_fluid_box = true
}

local function startup_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function pipeline_extent_multiplier()
  local value = tonumber(startup_setting("mir-pipeline-extent-multiplier")) or 1
  if value < 1 then return 1 end
  return value
end

local function scaled_extent(current, multiplier)
  local base = tonumber(current) or DEFAULT_PIPELINE_EXTENT
  local scaled = math.floor((base * multiplier) + 0.5)
  if scaled < 1 then return 1 end
  return scaled
end

local function apply_to_fluid_box(box, multiplier, seen_boxes)
  if type(box) ~= "table" then return 0 end
  if seen_boxes[box] then return 0 end
  seen_boxes[box] = true

  box.max_pipeline_extent = scaled_extent(box.max_pipeline_extent, multiplier)
  return 1
end

local function apply_to_fluid_boxes(value, multiplier, seen_boxes)
  if type(value) ~= "table" then return 0 end

  local count = 0
  for _, box in pairs(value) do
    count = count + apply_to_fluid_box(box, multiplier, seen_boxes)
  end
  return count
end

local function scan_table(value, multiplier, seen_nodes, seen_boxes)
  if type(value) ~= "table" then return 0 end
  if seen_nodes[value] then return 0 end
  seen_nodes[value] = true

  local count = 0
  for key, child in pairs(value) do
    if FLUID_BOX_FIELDS[key] then
      count = count + apply_to_fluid_box(child, multiplier, seen_boxes)
    elseif key == "fluid_boxes" then
      count = count + apply_to_fluid_boxes(child, multiplier, seen_boxes)
    elseif type(child) == "table" then
      count = count + scan_table(child, multiplier, seen_nodes, seen_boxes)
    end
  end

  return count
end

function P.apply()
  local multiplier = pipeline_extent_multiplier()
  if multiplier <= 1 then return end

  local count = 0
  local seen_nodes = {}
  local seen_boxes = {}

  for _, prototypes in pairs(data.raw or {}) do
    for _, prototype in pairs(prototypes or {}) do
      count = count + scan_table(prototype, multiplier, seen_nodes, seen_boxes)
    end
  end

  log("[more-infinite-research] Applied pipeline extent multiplier "
    .. tostring(multiplier)
    .. " to "
    .. tostring(count)
    .. " fluid boxes.")
end

return P
