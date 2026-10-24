-- Historical startup settings for the direct-research target adapters.  The
-- reduced F013/F014 path keeps its observed direct-only surface.  F015+ also
-- keeps the named global and base-continuation settings which its published
-- settings stage exposed.  Their emitted continuations remain a separate
-- selected-target data-stage responsibility.
local direct = require("research.native_direct_definitions")
local contracts = require("compatibility.historical_direct")

local M = {}

local DIRECT_FIELDS = {
  {key="enabled", prefix="ips-enable-", type="bool-setting"},
  {key="base_cost", prefix="ips-cost-base-", type="int-setting", minimum_value=1, maximum_value=2147483647},
  {key="linear_increment", prefix="ips-cost-linear-increment-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="growth_factor", prefix="ips-cost-growth-", type="double-setting", minimum_value=1, maximum_value=1000},
  {key="max_level", prefix="ips-max-level-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="research_time", prefix="ips-research-time-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="effect_percent", prefix="ips-effect-per-level-", type="double-setting", minimum_value=0.01, maximum_value=1000000},
}

local BASE_FIELDS = {
  {key="enabled", prefix="mir-enable-", type="bool-setting"},
  {key="base_cost", prefix="mir-cost-base-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="linear_increment", prefix="mir-cost-linear-increment-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="growth_factor", prefix="mir-cost-growth-", type="double-setting", minimum_value=0, maximum_value=1000},
  {key="max_level", prefix="mir-max-level-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="research_time", prefix="mir-research-time-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="effect_percent", prefix="mir-effect-per-level-", type="double-setting", minimum_value=0.01, maximum_value=1000000},
}

local BASE_LOCALE = {
  enabled="mir-enable-base-tech",
  base_cost="mir-cost-base",
  linear_increment="mir-cost-linear-increment",
  growth_factor="mir-cost-growth",
  max_level="mir-max-level",
  research_time="mir-research-time",
  effect_percent="mir-effect-per-level",
}

local DIRECT_INTEGER_EFFECTS = {
  research_character_reach = true,
  research_inventory_capacity = true,
}

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("MIR historical direct setting has a cycle", 3) end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

-- The full historical surface is constructed only for F015+.  F013/F014 do
-- not gain an inferred setting just because a later package happened to use
-- the same direct-family identity.
local function complete_surface(contract)
  if contract.numeric_cost then return nil end
  return {
    options = {
      {
        name="mir-compiler-profile", type="string-setting", setting_type="startup", default_value="full",
        allowed_values={"full", "classic"}, hidden=true, order="a-000-compiler-profile",
        localised_name={"mod-setting-name.mir-compiler-profile"},
        localised_description={"mod-setting-description.mir-compiler-profile"},
      },
      {
        name="ips-require-space-gate", type="bool-setting", setting_type="startup", default_value=false, order="a-0-010",
        localised_name={"mod-setting-name.ips-require-space-gate"},
        localised_description={"mod-setting-description.ips-require-space-gate"},
      },
      {
        name="mir-science-pack-ingredient-policy", type="string-setting", setting_type="startup", default_value="configured",
        allowed_values={"configured", "space", "space-and-promethium", "space-age-progression", "official-progression",
          "mod-progression", "all-official", "all"},
        order="a-0-020", localised_name={"mod-setting-name.mir-science-pack-ingredient-policy"},
        localised_description={"mod-setting-description.mir-science-pack-ingredient-policy"},
      },
      {
        name="mir-lab-incompatibility-policy", type="string-setting", setting_type="startup", default_value="reduce",
        allowed_values={"reduce", "skip", "engine-default"}, order="a-0-030",
        localised_name={"mod-setting-name.mir-lab-incompatibility-policy"},
        localised_description={"mod-setting-description.mir-lab-incompatibility-policy"},
      },
      {
        name="mir-prefer-this-mod-for-competing-techs", type="bool-setting", setting_type="startup", default_value=true, order="a-0-040",
        localised_name={"mod-setting-name.mir-prefer-this-mod-for-competing-techs"},
        localised_description={"mod-setting-description.mir-prefer-this-mod-for-competing-techs"},
      },
      {
        name="mir-adjust-vanilla-weapon-speed-techs", type="string-setting", setting_type="startup",
        default_value="only-when-dedicated-tech-enabled",
        allowed_values={"off", "only-when-dedicated-tech-enabled", "always"}, order="a-1-010",
        localised_name={"mod-setting-name.mir-adjust-vanilla-weapon-speed-techs"},
        localised_description={"mod-setting-description.mir-adjust-vanilla-weapon-speed-techs"},
      },
      {
        name="mir-debug-generation-report", type="bool-setting", setting_type="startup", default_value=false, order="a-8-010",
        localised_name={"mod-setting-name.mir-debug-generation-report"},
        localised_description={"mod-setting-description.mir-debug-generation-report"},
      },
      {
        name="mir-debug-recipe-matches", type="bool-setting", setting_type="startup", default_value=false, order="a-8-020",
        localised_name={"mod-setting-name.mir-debug-recipe-matches"},
        localised_description={"mod-setting-description.mir-debug-recipe-matches"},
      },
    },
    base_extensions = {
      {
        key="inserter-capacity-bonus", locale={"technology-name.inserter-capacity-bonus"},
        order="b-000-inserter-capacity-bonus-base-inserter-capacity-bonus-",
        defaults={enabled=true, base_cost=200, linear_increment=0, growth_factor=3.333333333333,
          max_level=0, research_time=60, effect_percent=4},
        integer_effect=true, enabled_note={"mod-setting-description.mir-note-inserter-capacity"},
      },
      {
        key="braking-force", locale={"technology-name.braking-force"},
        order="b-050-braking-force-base-braking-force-",
        defaults={enabled=true, base_cost=115, linear_increment=0, growth_factor=1.333333333333,
          max_level=0, research_time=60, effect_percent=15},
      },
      {
        key="research-speed", locale={"technology-name.research-speed"},
        order="b-050-lab-research-speed-base-research-speed-",
        defaults={enabled=true, base_cost=60, linear_increment=0, growth_factor=1.5,
          max_level=0, research_time=120, effect_percent=60},
      },
      {
        key="laser-shooting-speed", locale={"technology-name.laser-shooting-speed"},
        order="b-050-laser-shooting-speed-base-laser-shooting-speed-",
        defaults={enabled=true, base_cost=60, linear_increment=0, growth_factor=1.5,
          max_level=0, research_time=120, effect_percent=50},
      },
      {
        key="weapon-shooting-speed", locale={"technology-name.weapon-shooting-speed"},
        order="b-050-weapon-shooting-speed-base-weapon-shooting-speed-",
        defaults={enabled=true, base_cost=60, linear_increment=0, growth_factor=1.5,
          max_level=0, research_time=120, effect_percent=40},
      },
      {
        key="worker-robots-storage", locale={"technology-name.worker-robots-storage"},
        order="b-050-worker-robot-cargo-size-base-worker-robots-storage-",
        defaults={enabled=true, base_cost=200, linear_increment=0, growth_factor=1.5,
          max_level=0, research_time=60, effect_percent=1},
        integer_effect=true,
      },
    },
  }
end

local function field_for_direct(key, field)
  local out = copy(field)
  if field.key == "effect_percent" and DIRECT_INTEGER_EFFECTS[key] then
    out.type, out.minimum_value = "int-setting", 1
  end
  return out
end

local function field_for_base(group, field)
  local out = copy(field)
  if field.key == "effect_percent" and group.integer_effect then
    out.type, out.minimum_value = "int-setting", 1
  end
  return out
end

local function direct_locale(key)
  return {"technology-name.more-infinite-research." .. key}
end

local function append_direct_prototypes(out, contract)
  for _, key in ipairs(contract.settings) do
    local definition = direct.definition(key)
    for index, base_field in ipairs(DIRECT_FIELDS) do
      local field = field_for_direct(key, base_field)
      out[#out + 1] = {
        type=field.type, name=field.prefix .. key, setting_type="startup",
        default_value=definition.defaults[field.key], minimum_value=field.minimum_value,
        maximum_value=field.maximum_value, order=definition.setting_order .. (index - 1),
        localised_name={"mod-setting-name." .. field.prefix .. "stream", direct_locale(key)},
        localised_description={"mod-setting-description." .. field.prefix .. "stream", direct_locale(key)},
      }
    end
  end
end

local function append_base_prototypes(out, surface)
  for _, group in ipairs(surface.base_extensions) do
    for index, base_field in ipairs(BASE_FIELDS) do
      local field = field_for_base(group, base_field)
      local locale = BASE_LOCALE[field.key]
      local name = {"mod-setting-name." .. locale, copy(group.locale)}
      local description = {"mod-setting-description." .. locale, copy(group.locale)}
      if field.key == "enabled" and group.enabled_note then
        description = {"", description, "\n\n", copy(group.enabled_note)}
      end
      out[#out + 1] = {
        type=field.type, name=field.prefix .. group.key, setting_type="startup",
        default_value=group.defaults[field.key], minimum_value=field.minimum_value,
        maximum_value=field.maximum_value, order=group.order .. (index - 1),
        localised_name=name, localised_description=description,
      }
    end
  end
end

function M.prototypes(target)
  local contract, out = contracts.for_target(target), {}
  local surface = complete_surface(contract)
  if surface then
    for _, option in ipairs(surface.options) do out[#out + 1] = copy(option) end
  end
  append_direct_prototypes(out, contract)
  if surface then append_base_prototypes(out, surface) end
  return out
end

function M.defaults(target)
  local contract, streams = contracts.for_target(target), {}
  for _, key in ipairs(contract.settings) do streams[key] = copy(direct.definition(key).defaults) end
  return streams
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function valid(field, value)
  if field.type == "bool-setting" then return type(value) == "boolean" end
  if field.type == "string-setting" then
    if type(value) ~= "string" then return false end
    for _, allowed in ipairs(field.allowed_values or {}) do if value == allowed then return true end end
    return false
  end
  if not finite(value) then return false end
  if field.type == "int-setting" and value ~= math.floor(value) then return false end
  if field.minimum_value ~= nil and value < field.minimum_value then return false end
  return field.maximum_value == nil or value <= field.maximum_value
end

local function value_from(startup, name, default_value)
  local entry = startup and startup[name]
  local value = entry and entry.value
  if value == nil then return default_value end
  return value
end

local function resolve_direct_streams(contract, startup, values)
  for _, key in ipairs(contract.settings) do
    local definition, stream, configured = direct.definition(key), {}, {}
    for _, base_field in ipairs(DIRECT_FIELDS) do
      local field = field_for_direct(key, base_field)
      local name = field.prefix .. key
      local value = value_from(startup, name, definition.defaults[field.key])
      if not valid(field, value) then error("MIR invalid historical direct setting " .. name, 2) end
      configured[field.key] = value ~= definition.defaults[field.key]
      if field.key == "research_time" and value == 0 then value = definition.defaults.research_time end
      stream[field.key] = value
    end
    stream.configured = configured
    values.streams[key] = stream
  end
end

local function resolve_complete_surface(surface, startup, values)
  for _, option in ipairs(surface.options) do
    local value = value_from(startup, option.name, option.default_value)
    if not valid(option, value) then error("MIR invalid historical option " .. option.name, 2) end
    values.options[option.name] = value
  end
  for _, group in ipairs(surface.base_extensions) do
    local stream, configured = {}, {}
    for _, base_field in ipairs(BASE_FIELDS) do
      local field = field_for_base(group, base_field)
      local name = field.prefix .. group.key
      local value = value_from(startup, name, group.defaults[field.key])
      if not valid(field, value) then error("MIR invalid historical base setting " .. name, 2) end
      configured[field.key] = value ~= group.defaults[field.key]
      -- A zero continuation time is the published inherit sentinel.  Keep it
      -- literal here; the base-continuation constructor owns its named source.
      stream[field.key] = value
    end
    stream.configured = configured
    values.base_extensions[group.key] = stream
  end
end

-- Resolve only the selected target's authored setting surface.  Direct
-- research consumes `streams`; base-continuation integration consumes the
-- separately named `base_extensions` values and options.
function M.resolve(target, startup)
  local contract = contracts.for_target(target)
  local values = {streams={}, options={}, base_extensions={}}
  resolve_direct_streams(contract, startup, values)
  local surface = complete_surface(contract)
  if surface then resolve_complete_surface(surface, startup, values) end
  return values
end

return M
