data:extend({
  {
    type = "string-setting",
    name = "mir5-library-paired-browser-arm",
    setting_type = "startup",
    default_value = "mir5",
    allowed_values = {"published", "mir5"},
    order = "a"
  },
  {
    type = "bool-setting",
    name = "mir5-library-paired-browser-retained-refresh",
    setting_type = "startup",
    default_value = false,
    order = "b"
  }
})
