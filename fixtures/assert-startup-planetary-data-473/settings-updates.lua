-- Explicitly select the unfamiliar lab input through the supported all-pack
-- policy; the repair must retain it rather than silently omit it.
data.raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value = "all"
