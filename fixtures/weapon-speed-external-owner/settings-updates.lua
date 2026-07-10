local preference = data.raw["bool-setting"] and data.raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"]
if not preference then
  error("MIR external weapon owner fixture could not find the competing-technology preference setting.")
end
preference.default_value = false
