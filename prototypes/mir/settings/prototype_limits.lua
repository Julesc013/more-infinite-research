local S = {}
local setting_order = require("prototypes.mir.settings.order")

S.engine_default = "engine-default"
S.positive_power_floor_setting_name = "mir-prototype-positive-power-floor"
S.recycling_return_setting_name = "mir-recycling-return-chance"
S.self_recycling_scope_setting_name = "mir-productivity-cap-self-recycling-only"
S.unrestricted_modules_setting_name = "mir-unrestricted-modules"
S.recycling_return_balanced = "match-productivity-cap"

S.recycling_return_allowed_values = {
  S.engine_default,
  S.recycling_return_balanced,
  "percent-25",
  "percent-20",
  "percent-15",
  "percent-12-5",
  "percent-10",
  "percent-7-5",
  "percent-5",
  "percent-2-5",
  "percent-1",
  "percent-0-5",
  "percent-0-1"
}

S.recycling_return_values = {
  ["percent-25"] = 0.25,
  ["percent-20"] = 0.20,
  ["percent-15"] = 0.15,
  ["percent-12-5"] = 0.125,
  ["percent-10"] = 0.10,
  ["percent-7-5"] = 0.075,
  ["percent-5"] = 0.05,
  ["percent-2-5"] = 0.025,
  ["percent-1"] = 0.01,
  ["percent-0-5"] = 0.005,
  ["percent-0-1"] = 0.001
}

local productivity_values = {
  ["percent-25"] = 0.25,
  ["percent-50"] = 0.5,
  ["percent-75"] = 0.75,
  ["percent-100"] = 1.0,
  ["percent-125"] = 1.25,
  ["percent-150"] = 1.5,
  ["percent-200"] = 2.0,
  ["percent-250"] = 2.5,
  ["percent-400"] = 4.0,
  ["percent-500"] = 5.0,
  ["percent-750"] = 7.5,
  ["percent-1000"] = 10.0,
  ["percent-2500"] = 25.0,
  ["percent-5000"] = 50.0,
  ["percent-10000"] = 100.0,
  ["percent-25000"] = 250.0,
  ["percent-100000"] = 1000.0
}

local saving_values = {
  ["saving-25"] = -0.25,
  ["saving-50"] = -0.5,
  ["saving-75"] = -0.75,
  ["saving-90"] = -0.9,
  ["saving-95"] = -0.95,
  ["saving-99"] = -0.99,
  ["saving-999"] = -0.999,
  ["saving-9999"] = -0.9999
}

local bonus_values = {
  ["bonus-25"] = 0.25,
  ["bonus-50"] = 0.5,
  ["bonus-75"] = 0.75,
  ["bonus-100"] = 1.0,
  ["bonus-125"] = 1.25,
  ["bonus-150"] = 1.5,
  ["bonus-200"] = 2.0,
  ["bonus-250"] = 2.5,
  ["bonus-300"] = 3.0,
  ["bonus-400"] = 4.0,
  ["bonus-500"] = 5.0,
  ["bonus-750"] = 7.5,
  ["bonus-1000"] = 10.0,
  ["bonus-2500"] = 25.0,
  ["bonus-5000"] = 50.0,
  ["bonus-10000"] = 100.0,
  ["bonus-25000"] = 250.0,
  ["bonus-100000"] = 1000.0
}

S.order = {
  "productivity",
  "efficiency",
  "pollution",
  "speed_floor",
  "speed",
  "quality"
}

S.settings = {
  productivity = {
    name = "mir-prototype-productivity-cap",
    default_value = S.engine_default,
    allowed_values = {
      "percent-100000",
      "percent-25000",
      "percent-10000",
      "percent-5000",
      "percent-2500",
      "percent-1000",
      "percent-750",
      "percent-500",
      "percent-400",
      S.engine_default,
      "percent-250",
      "percent-200",
      "percent-150",
      "percent-125",
      "percent-100",
      "percent-75",
      "percent-50",
      "percent-25"
    },
    values = productivity_values,
    import_numeric_minimum = 0,
    import_numeric_maximum = 100000,
    order = setting_order.global("prototype_limits", 10)
  },

  efficiency = {
    name = "mir-prototype-efficiency-cap",
    default_value = S.engine_default,
    allowed_values = {
      "saving-9999",
      "saving-999",
      "saving-99",
      "saving-95",
      "saving-90",
      S.engine_default,
      "saving-75",
      "saving-50",
      "saving-25"
    },
    values = saving_values,
    import_numeric_minimum = -99.99,
    import_numeric_maximum = 0,
    order = setting_order.global("prototype_limits", 20)
  },

  pollution = {
    name = "mir-prototype-pollution-cap",
    default_value = S.engine_default,
    allowed_values = {
      "saving-9999",
      "saving-999",
      "saving-99",
      "saving-95",
      "saving-90",
      S.engine_default,
      "saving-75",
      "saving-50",
      "saving-25"
    },
    values = saving_values,
    import_numeric_minimum = -99.99,
    import_numeric_maximum = 0,
    order = setting_order.global("prototype_limits", 30)
  },

  speed_floor = {
    name = "mir-prototype-speed-floor",
    default_value = S.engine_default,
    allowed_values = {
      "saving-9999",
      "saving-999",
      "saving-99",
      "saving-95",
      "saving-90",
      S.engine_default,
      "saving-75",
      "saving-50",
      "saving-25"
    },
    values = saving_values,
    import_numeric_minimum = -99.99,
    import_numeric_maximum = 0,
    order = setting_order.global("prototype_limits", 35)
  },

  speed = {
    name = "mir-prototype-speed-cap",
    default_value = S.engine_default,
    allowed_values = {
      S.engine_default,
      "bonus-25000",
      "bonus-10000",
      "bonus-5000",
      "bonus-2500",
      "bonus-1000",
      "bonus-750",
      "bonus-500",
      "bonus-400",
      "bonus-300",
      "bonus-250",
      "bonus-200",
      "bonus-150",
      "bonus-125",
      "bonus-100",
      "bonus-75",
      "bonus-50",
      "bonus-25"
    },
    accepted_import_values = {"bonus-100000"},
    import_numeric_minimum = 0,
    import_numeric_maximum = 100000,
    values = bonus_values,
    order = setting_order.global("prototype_limits", 40)
  },

  quality = {
    name = "mir-prototype-quality-cap",
    default_value = S.engine_default,
    allowed_values = {
      S.engine_default,
      "bonus-25000",
      "bonus-10000",
      "bonus-5000",
      "bonus-2500",
      "bonus-1000",
      "bonus-750",
      "bonus-500",
      "bonus-400",
      "bonus-300",
      "bonus-250",
      "bonus-200",
      "bonus-150",
      "bonus-125",
      "bonus-100",
      "bonus-75",
      "bonus-50",
      "bonus-25"
    },
    accepted_import_values = {"bonus-100000"},
    import_numeric_minimum = 0,
    import_numeric_maximum = 100000,
    values = bonus_values,
    order = setting_order.global("prototype_limits", 50)
  }
}

function S.setting_prototypes()
  local out = {}

  for _, key in ipairs(S.order) do
    local spec = S.settings[key]
    table.insert(out, {
      type = "string-setting",
      name = spec.name,
      setting_type = "startup",
      default_value = spec.default_value,
      allowed_values = spec.allowed_values,
      order = spec.order,
      localised_name = {"mod-setting-name." .. spec.name},
      localised_description = {"mod-setting-description." .. spec.name}
    })
  end

  return out
end

function S.value(setting_key, raw_value)
  if raw_value == nil or raw_value == S.engine_default then
    return nil
  end

  local spec = S.settings[setting_key]
  if not spec then return nil end
  if type(raw_value) == "number" then return raw_value / 100 end
  return spec.values[tostring(raw_value)]
end

function S.recycling_return_value(raw_value, productivity_cap)
  if raw_value == nil or raw_value == S.engine_default then return nil end
  if raw_value == S.recycling_return_balanced then
    local cap = tonumber(productivity_cap)
    if cap == nil then cap = 3.0 end
    -- A +400% bonus produces five total crafts at the cap, so the safe
    -- inverse is 1 / (1 + 4), not 1 / 4. Never use this policy to improve
    -- vanilla's normal 25% recycling return.
    return math.min(0.25, 1 / (1 + math.max(0, cap)))
  end
  if type(raw_value) == "number" then return raw_value / 100 end
  return S.recycling_return_values[tostring(raw_value)]
end

return S
