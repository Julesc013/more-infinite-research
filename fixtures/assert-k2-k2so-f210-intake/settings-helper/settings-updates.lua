local function override(name, value)
  for _, prototype_type in ipairs({"bool-setting", "string-setting", "int-setting", "double-setting"}) do
    local prototype = data.raw[prototype_type] and data.raw[prototype_type][name]
    if prototype then prototype.default_value = value; return end
  end
  error("MIR validation override references missing startup setting " .. name)
end
override("mir-debug-generation-report", true)
