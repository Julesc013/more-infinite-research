local function profile()
  if script.active_mods.bobplates and script.active_mods.angelssmelting then return "combined" end
  if script.active_mods.bobplates then return "bob" end
  if script.active_mods.angelssmelting then return "angel" end
  return "unsupported"
end

script.on_init(function()
  log("[mir-a06-aluminium] RUNTIME profile=" .. profile() .. " state=loaded observer=read-only")
end)
