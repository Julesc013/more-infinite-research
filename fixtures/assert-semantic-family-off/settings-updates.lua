local action = data.raw["string-setting"] and data.raw["string-setting"]["mir-automatic-productivity-action"]
if not action then error("missing automatic productivity action setting") end
action.default_value = "disabled"
