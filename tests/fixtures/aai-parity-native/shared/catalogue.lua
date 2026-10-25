local source = mods["mir-fixture-mir5-aai-parity-native"] == "0.1.0"
return source
  and require("__mir-fixture-mir5-aai-parity-native__/published-4.7/catalogue")
  or require("__mir-fixture-mir5-aai-parity-native__/mir5/catalogue")
