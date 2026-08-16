data:extend({{
  type = "string-setting",
  name = "mir-upgrade-archetype",
  setting_type = "startup",
  default_value = "space-age-native-owner",
  allowed_values = {
    "base-default",
    "space-age-native-owner",
    "automatic-family-creation",
    "base-continuations",
    "mod-set-configuration-change"
  },
  hidden = true,
  order = "zzz-mir-upgrade-archetype"
}})
