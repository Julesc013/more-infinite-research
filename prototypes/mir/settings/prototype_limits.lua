local S = {}
local setting_order = require("prototypes.mir.settings.order")

S.engine_default = "engine-default"
S.positive_power_floor_setting_name = "mir-prototype-positive-power-floor"

S.order = {
  "productivity",
  "efficiency",
  "pollution",
  "speed",
  "quality"
}

S.settings = {
  productivity = {
    name = "mir-prototype-productivity-cap",
    default_value = S.engine_default,
    allowed_values = {
      "percent-100000",
      "percent-10000",
      "percent-2500",
      "percent-1000",
      "percent-500",
      "percent-400",
      S.engine_default,
      "percent-250",
      "percent-200",
      "percent-100",
      "percent-75",
      "percent-50"
    },
    values = {
      ["percent-50"] = 0.5,
      ["percent-75"] = 0.75,
      ["percent-100"] = 1.0,
      ["percent-200"] = 2.0,
      ["percent-250"] = 2.5,
      ["percent-400"] = 4.0,
      ["percent-500"] = 5.0,
      ["percent-1000"] = 10.0,
      ["percent-2500"] = 25.0,
      ["percent-10000"] = 100.0,
      ["percent-100000"] = 1000.0
    },
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
      "saving-50"
    },
    values = {
      ["saving-50"] = -0.5,
      ["saving-75"] = -0.75,
      ["saving-90"] = -0.9,
      ["saving-95"] = -0.95,
      ["saving-99"] = -0.99,
      ["saving-999"] = -0.999,
      ["saving-9999"] = -0.9999
    },
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
      "saving-50"
    },
    values = {
      ["saving-50"] = -0.5,
      ["saving-75"] = -0.75,
      ["saving-90"] = -0.9,
      ["saving-95"] = -0.95,
      ["saving-99"] = -0.99,
      ["saving-999"] = -0.999,
      ["saving-9999"] = -0.9999
    },
    order = setting_order.global("prototype_limits", 30)
  },

  speed = {
    name = "mir-prototype-speed-cap",
    default_value = S.engine_default,
    allowed_values = {
      S.engine_default,
      "bonus-10000",
      "bonus-1000",
      "bonus-500",
      "bonus-400",
      "bonus-250",
      "bonus-200",
      "bonus-100",
      "bonus-75",
      "bonus-50"
    },
    accepted_import_values = {"bonus-100000"},
    values = {
      ["bonus-50"] = 0.5,
      ["bonus-75"] = 0.75,
      ["bonus-100"] = 1.0,
      ["bonus-200"] = 2.0,
      ["bonus-250"] = 2.5,
      ["bonus-400"] = 4.0,
      ["bonus-500"] = 5.0,
      ["bonus-1000"] = 10.0,
      ["bonus-10000"] = 100.0,
      ["bonus-100000"] = 1000.0
    },
    order = setting_order.global("prototype_limits", 40)
  },

  quality = {
    name = "mir-prototype-quality-cap",
    default_value = S.engine_default,
    allowed_values = {
      S.engine_default,
      "bonus-10000",
      "bonus-1000",
      "bonus-500",
      "bonus-400",
      "bonus-250",
      "bonus-200",
      "bonus-100",
      "bonus-75",
      "bonus-50"
    },
    accepted_import_values = {"bonus-100000"},
    values = {
      ["bonus-50"] = 0.5,
      ["bonus-75"] = 0.75,
      ["bonus-100"] = 1.0,
      ["bonus-200"] = 2.0,
      ["bonus-250"] = 2.5,
      ["bonus-400"] = 4.0,
      ["bonus-500"] = 5.0,
      ["bonus-1000"] = 10.0,
      ["bonus-10000"] = 100.0,
      ["bonus-100000"] = 1000.0
    },
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
  return spec.values[tostring(raw_value)]
end

return S
