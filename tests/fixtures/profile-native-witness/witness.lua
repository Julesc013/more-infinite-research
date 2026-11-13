-- Independent native expectations from the published profile round-trip
-- obligations. This module never imports MIR code or changes a prototype.
local M = {}
local tolerance = 0.000001

local function near(actual, expected, name)
  assert(type(actual) == "number" and actual == actual and math.abs(actual) < math.huge
    and math.abs(actual - expected) <= tolerance, "profile native witness: " .. name .. "=" .. tostring(actual))
end

local function family(base)
  if base == "2.0.77" then return "f200" end
  assert(base == "2.1.23", "profile native witness: exact engine")
  return "f210"
end

local function observe(stage, base, mode, recipe, recycling, receiver, pipeline)
  assert(mode == "numeric" or mode == "aliases", "profile native witness: mode")
  local target = family(base)
  assert(recipe and recycling and #recycling == 1, "profile native witness: named recipes")
  local product = recycling[1]
  assert(product.type == "item" and product.name == "iron-ore", "profile native witness: self recycling product")
  near(product.amount, 1, "self recycling amount")
  near(product.extra_count_fraction or 0, 0, "self recycling fraction")
  local probability = target == "f210" and product.independent_probability or product.probability
  near(probability, mode == "aliases" and 0.25 or 0.1234, "self recycling probability")
  if mode == "numeric" then
    near(recipe.maximum_productivity, 43.215, "recipe productivity cap")
    if stage == "data" then near(pipeline, 395, "pipeline extent") end
  elseif stage == "data" then
    assert(pipeline == nil, "profile native witness: alias profile changed implicit pipeline extent")
  end
  local result = {stage = stage, family = target, mode = mode,
    maximum_productivity = recipe.maximum_productivity, recycling_amount = product.amount,
    recycling_probability = probability, receiver_limits_supported = target == "f210"}
  if stage == "data" then
    result.pipeline_extent = pipeline
    result.pipeline_extent_explicit = pipeline ~= nil
  end
  if target == "f210" then
    assert(receiver, "profile native witness: receiver")
    local expected = {consumption_limits = {low = -0.8325}, pollution_limits = {low = -0.91125},
      speed_limits = {low = -0.755, high = mode == "aliases" and 1000 or 12.345},
      quality_limits = {high = mode == "aliases" and 1000 or 6.789}}
    if mode == "aliases" then expected = {speed_limits = {high = 1000}, quality_limits = {high = 1000}} end
    result.receiver = {}
    for name, limits in pairs(expected) do
      assert(receiver[name], "profile native witness: " .. name)
      result.receiver[name] = {}
      for side, value in pairs(limits) do
        near(receiver[name][side], value, name .. "." .. side)
        result.receiver[name][side] = receiver[name][side]
      end
    end
  end
  return result
end

function M.data(raw, base, mode)
  local machine = assert(raw["assembling-machine"]["assembling-machine-2"])
  return observe("data", base, mode, raw.recipe["iron-gear-wheel"],
    assert(raw.recipe["iron-ore-recycling"]).results,
    raw["assembling-machine"]["assembling-machine-1"].effect_receiver,
    assert(machine.fluid_boxes[1]).max_pipeline_extent)
end

function M.runtime(prototypes, base, mode)
  local receiver
  if family(base) == "f210" then receiver = prototypes.entity["assembling-machine-1"].effect_receiver end
  return observe("runtime", base, mode, prototypes.recipe["iron-gear-wheel"],
    assert(prototypes.recipe["iron-ore-recycling"]).products, receiver)
end

function M.line(value)
  assert(value.stage == "data", "profile native witness: data log only")
  local text = "[MIR_PROFILE_NATIVE_DATA] family=" .. value.family .. ";mode=" .. value.mode
    .. ";pipeline=" .. (value.pipeline_extent and string.format("%.17g", value.pipeline_extent) or "implicit")
    .. ";productivity=" .. (value.maximum_productivity and string.format("%.17g", value.maximum_productivity) or "implicit")
    .. ";recycling=" .. string.format("%.17g", value.recycling_probability)
  if value.receiver then
    for _, name in ipairs({"consumption_limits", "pollution_limits", "speed_limits", "quality_limits"}) do
      for _, side in ipairs({"low", "high"}) do
        local number = value.receiver[name] and value.receiver[name][side]
        if number ~= nil then text = text .. ";" .. name .. "." .. side .. "=" .. string.format("%.17g", number) end
      end
    end
  end
  return text
end

return M
