if mods and mods["more-infinite-research"] == "1.8.1" then
  local setting = data.raw["string-setting"]
    and data.raw["string-setting"]["mir-adjust-vanilla-weapon-speed-techs"]
  if not setting then error("missing weapon overlap setting in MIR 1.8.1") end
  setting.default_value = "always"
end
