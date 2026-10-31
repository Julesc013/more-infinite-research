-- Independent post-MIR assertions for the fixture-owned F210 override witness.
-- These inspect actual native data-stage fields that Factorio's runtime API
-- does not expose (pipeline extent and receiver limit ranges).
local prefix = "mir5-override-"
local effects = {"speed", "productivity", "consumption", "pollution", "quality"}

local function fail(message) error("[mir5-override-interactions] " .. message) end
local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end
local function exact_array(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " cardinality differs") end
  for index, value in ipairs(expected) do
    if actual[index] ~= value then fail(label .. " differs at " .. index) end
  end
end
local function categories()
  local seen, out = {}, {}
  for name in pairs(data.raw["module-category"] or {}) do
    if type(name) == "string" and not seen[name] then seen[name]=true; out[#out+1]=name end
  end
  for _, value in pairs(data.raw.module or {}) do
    local name = type(value) == "table" and value.category or nil
    if type(name) == "string" and not seen[name] then seen[name]=true; out[#out+1]=name end
  end
  table.sort(out)
  return out
end
local function effect_map(value, label)
  for _, name in ipairs(effects) do if value[name] ~= true then fail(label .. " is missing " .. name) end end
  for name, enabled in pairs(value) do
    if enabled ~= true then fail(label .. " has non-true effect") end
    local known = false
    for _, expected in ipairs(effects) do if name == expected then known=true; break end end
    if not known then fail(label .. " has extra effect " .. tostring(name)) end
  end
end

local ordinary = assert(data.raw.recipe[prefix .. "ordinary"], "ordinary recipe is absent")
local recycled = assert(data.raw.recipe[prefix .. "recycling"], "recycling recipe is absent")
local parameter = assert(data.raw.recipe[prefix .. "parameter"], "parameter recipe is absent")
local machine = assert(data.raw["assembling-machine"][prefix .. "assembler"], "assembler is absent")
local pipeline = assert(data.raw["assembling-machine"][prefix .. "pipeline"], "pipeline probe is absent")
local expected_categories = categories()

if not near(ordinary.maximum_productivity, 1) then fail("ordinary productivity cap differs") end
if ordinary.energy_required ~= 0.5 or ordinary.enabled ~= true then fail("ordinary recipe unrelated fields changed") end
effect_map({speed=ordinary.allow_speed, productivity=ordinary.allow_productivity, consumption=ordinary.allow_consumption,
  pollution=ordinary.allow_pollution, quality=ordinary.allow_quality}, "ordinary recipe effects")
exact_array(ordinary.allowed_module_categories, expected_categories, "ordinary module categories")

local result = assert(recycled.results and recycled.results[1], "recycling result is absent")
if not near(recycled.maximum_productivity, 0.5) then fail("native recycling cap changed") end
if not near(result.independent_probability, 0.2) or result.probability ~= nil then fail("F210 recycling probability differs") end
if recycled.hidden ~= true or recycled.unlock_results ~= false then fail("recycling route eligibility changed") end

if parameter.parameter ~= true or parameter.allow_speed ~= false or parameter.allow_productivity ~= false
    or parameter.allow_consumption ~= false or parameter.allow_pollution ~= false or parameter.allow_quality ~= false then
  fail("parameter recipe skip differs")
end
exact_array(parameter.allowed_module_categories, {"speed"}, "parameter module categories")

exact_array(machine.allowed_effects, effects, "receiver effects")
exact_array(machine.allowed_module_categories, expected_categories, "receiver module categories")
if machine.module_slots ~= 2 or machine.crafting_speed ~= 1 or machine.energy_usage ~= "1W" then
  fail("receiver native fields differ")
end
local receiver = assert(machine.effect_receiver, "effect receiver is absent")
if not near(receiver.speed_limits and receiver.speed_limits.low, -0.5)
    or not near(receiver.speed_limits and receiver.speed_limits.high, 2)
    or not near(receiver.quality_limits and receiver.quality_limits.low, 0)
    or not near(receiver.quality_limits and receiver.quality_limits.high, 1)
    or not receiver.uses_module_effects or not receiver.uses_beacon_effects or not receiver.uses_surface_effects
    or not near(receiver.base_effect and receiver.base_effect.speed, 0) then
  fail("receiver limits or retained native fields differ")
end

local boxes = assert(pipeline.fluid_boxes, "pipeline boxes are absent")
local explicit, count = 0, 0
for index, box in ipairs(boxes) do
  count = count + 1
  if index == 1 then
    if box.max_pipeline_extent ~= 960 then fail("pipeline implicit extent differs") end
  elseif box.max_pipeline_extent == 480 then explicit = explicit + 1
  else fail("pipeline explicit extent differs") end
end
local utility = assert(data.raw["utility-constants"] and data.raw["utility-constants"].default,
  "utility constants are absent")
if utility.default_pipeline_extent ~= 640 then fail("pipeline utility default changed") end
if count < 2 or explicit ~= count - 1 then
  fail("pipeline extent positional contract differs")
end

log("[MIR5_OVERRIDE_INTERACTIONS_DATA] status=passed;ordinary-cap=1;recycling-probability=0.2;"
  .. "pipeline-implicit-extent=960;pipeline-explicit-extent=480;pipeline-utility-default=640;"
  .. "receiver-speed=-0.5,2;self-recycling-classifier=inactive")
