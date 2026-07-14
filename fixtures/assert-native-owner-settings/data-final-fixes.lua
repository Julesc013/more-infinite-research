local function fail(message)
  error("MIR native-owner settings validation failed: " .. message)
end

local function setting(name)
  local row = settings.startup[name]
  if not row then fail("missing visible startup setting " .. name) end
  return row.value
end

local function close(left, right)
  return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) <= 0.000000001
end

local function number_text(value)
  if value == math.floor(value) then return tostring(math.floor(value)) end
  return tostring(value)
end

local streams = {
  {
    key = "research_processing_unit",
    owner = "processing-unit-productivity",
    product = "processing-unit"
  },
  {
    key = "research_plastic",
    owner = "plastic-bar-productivity",
    product = "plastic-bar"
  },
  {
    key = "research_low_density_structure",
    owner = "low-density-structure-productivity",
    product = "low-density-structure"
  },
  {
    key = "research_rocket_fuel",
    owner = "rocket-fuel-productivity",
    product = "rocket-fuel"
  }
}

local adoption_data = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-productivity-family-adoption"]
  and data.raw["mod-data"]["more-infinite-research-productivity-family-adoption"].data
if not adoption_data or adoption_data.version ~= 2 then
  fail("expected native-owner binding mod-data schema 2")
end
local signature = tostring(adoption_data.signature or "")
local expected_binding_count = 0

for _, stream in ipairs(streams) do
  local enabled = setting("ips-enable-" .. stream.key)
  local base = setting("ips-cost-base-" .. stream.key)
  local growth = setting("ips-cost-growth-" .. stream.key)
  local max_level = setting("ips-max-level-" .. stream.key)
  local research_time = setting("ips-research-time-" .. stream.key)
  local effect_percent = setting("ips-effect-per-level-" .. stream.key)
  local owner = data.raw.technology and data.raw.technology[stream.owner]
  if not owner then fail("missing native owner " .. stream.owner) end

  local unrecognized = stream.key == "research_processing_unit"
    and owner.unit.count_formula == "1000 + 100 * L"
  local cost_changed = base ~= 8000 or growth ~= 2
  local time_changed = research_time ~= 60 and research_time > 0
  local max_changed = max_level ~= 0
  local effect_changed = effect_percent ~= 10
  local safely_rejected = enabled and unrecognized and cost_changed
  local signature_prefix = "schema=2|stream=" .. stream.key .. "|owner=" .. stream.owner .. "|operation="

  if not enabled then
    if string.find(signature, signature_prefix, 1, true) then
      fail("disabled stream unexpectedly bound " .. stream.owner)
    end
  elseif safely_rejected then
    if string.find(signature, signature_prefix, 1, true) then
      fail("unsafe cost override unexpectedly bound unrecognized formula for " .. stream.owner)
    end
    if owner.unit.count_formula ~= "1000 + 100 * L" then
      fail("unsafe cost override changed unrecognized formula for " .. stream.owner)
    end
  else
    expected_binding_count = expected_binding_count + 1
    local configured = {}
    if cost_changed then table.insert(configured, "cost_model") end
    if effect_changed then table.insert(configured, "effect_per_level") end
    if max_changed then table.insert(configured, "max_level") end
    if time_changed then table.insert(configured, "research_time") end
    local operation = #configured > 0 and "configure_native_owner" or "preserve_native_owner"
    local expected_fragment = signature_prefix .. operation
      .. "|configured=" .. table.concat(configured, ",") .. "|effects=0|output="
    if not string.find(signature, expected_fragment, 1, true) then
      fail("binding signature mismatch for " .. stream.owner .. "; expected " .. expected_fragment
        .. " in " .. signature)
    end

    if unrecognized then
      if owner.unit.count_formula ~= "1000 + 100 * L" then
        fail("default settings did not preserve unrecognized formula for " .. stream.owner)
      end
    else
      local expected_base = cost_changed and base or 1000
      local expected_growth = cost_changed and growth or 1.5
      local expected_formula = number_text(expected_growth) .. "^L*" .. number_text(expected_base)
      if owner.unit.count_formula ~= expected_formula then
        fail(stream.owner .. " formula differs; expected " .. expected_formula
          .. " got " .. tostring(owner.unit.count_formula))
      end
    end

    local expected_time = time_changed and research_time or 60
    if not close(owner.unit.time, expected_time) then
      fail(stream.owner .. " research time differs")
    end
    local expected_max = max_changed and math.floor(max_level) or "infinite"
    if owner.max_level ~= expected_max then
      fail(stream.owner .. " max level differs; expected " .. tostring(expected_max)
        .. " got " .. tostring(owner.max_level))
    end

    local relevant = 0
    for _, owner_effect in ipairs(owner.effects or {}) do
      if owner_effect.type == "change-recipe-productivity" then
        local recipe = data.raw.recipe and data.raw.recipe[owner_effect.recipe]
        for _, result in ipairs((recipe and recipe.results) or {}) do
          local name = result.name or result[1]
          if name == stream.product then
            relevant = relevant + 1
            local expected_change = effect_changed and effect_percent / 100 or 0.1
            if not close(owner_effect.change, expected_change) then
              fail(stream.owner .. " relevant effect differs for " .. tostring(owner_effect.recipe))
            end
          end
        end
      end
    end
    if relevant == 0 then fail(stream.owner .. " has no relevant productivity effect") end
  end

  local generated_name = "recipe-prod-" .. stream.key .. "-1"
  if data.raw.technology[generated_name] then
    fail("native-owner setting scenario generated duplicate technology " .. generated_name)
  end
end

if tonumber(adoption_data.binding_count) ~= expected_binding_count then
  fail("expected " .. tostring(expected_binding_count) .. " bindings, got "
    .. tostring(adoption_data.binding_count))
end

local processing_owner = data.raw.technology["processing-unit-productivity"]
local unrelated_found = false
for _, owner_effect in ipairs(processing_owner.effects or {}) do
  if owner_effect.type == "ammo-damage" and owner_effect.ammo_category == "bullet"
      and close(owner_effect.modifier, 0.07) then
    unrelated_found = true
  end
end
if not unrelated_found then fail("native-owner transaction changed or removed an unrelated owner effect") end
