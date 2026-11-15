-- Private observer selection only; identical across the entire predecessor chain.
data:extend({{type="string-setting", name="worker-default-native-scenario", setting_type="startup",
  default_value="legacy", allowed_values={"legacy","prepared-default"}, hidden=true, order="zz"}})
