local mode = data.raw["string-setting"] and data.raw["string-setting"]["mir-automatic-compiler-mode"]
if not mode then error("missing automatic compiler mode setting") end
mode.default_value = "report"
