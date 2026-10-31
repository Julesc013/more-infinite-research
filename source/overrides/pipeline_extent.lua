-- Independent opt-in fluid-box extent scaling. This preserves the published
-- percentage setting, rounding, native uint32 bounds and shared-box handling.
local M = {}
local DEFAULT_EXTENT, MAX_EXTENT = 320, 4294967295
local fields = {fluid_box=true, input_fluid_box=true, output_fluid_box=true,
  fuel_fluid_box=true, oxidizer_fluid_box=true}
local percentages = {['25']=true, ['50']=true, ['75']=true, ['100']=true,
  ['125']=true, ['150']=true, ['200']=true, ['250']=true, ['300']=true,
  ['400']=true, ['500']=true, ['750']=true, ['1000']=true}

function M.multiplier(value)
  local number = tonumber(value)
  if number == nil or number ~= number or number <= 0 or number == math.huge then return 1 end
  -- Registered dropdown values and numeric portable-profile values are
  -- percentages. Historical non-dropdown strings at most ten are factors.
  if type(value) == "number" or percentages[value] or number > 10 then return number / 100 end
  return number
end

function M.apply(raw, value)
  local multiplier = M.multiplier(value)
  if multiplier == 1 then return 0 end
  if type(raw) ~= "table" then return 0 end
  -- Omitted box extents inherit this native constant, which another mod may
  -- change. Preserve explicit extents and leave the constant itself alone.
  local utilities = raw["utility-constants"]
  local defaults = type(utilities) == "table" and utilities.default
  local default_extent = type(defaults) == "table" and tonumber(defaults.default_pipeline_extent) or DEFAULT_EXTENT
  local nodes, boxes, count = {}, {}, 0
  local function apply_box(box)
    if type(box) ~= "table" or boxes[box] then return end
    boxes[box] = true
    local extent = tonumber(box.max_pipeline_extent) or default_extent
    box.max_pipeline_extent = math.max(1, math.min(MAX_EXTENT, math.floor(extent * multiplier + 0.5)))
    count = count + 1
  end
  local pending = {raw}
  nodes[raw] = true
  while #pending > 0 do
    local node = pending[#pending]
    pending[#pending] = nil
    for key, child in pairs(node) do
      if fields[key] then
        apply_box(child)
      elseif key == "fluid_boxes" and type(child) == "table" then
        for _, box in pairs(child) do apply_box(box) end
      elseif type(child) == "table" and not nodes[child] then
        nodes[child] = true
        pending[#pending + 1] = child
      end
    end
  end
  return count
end

return M
