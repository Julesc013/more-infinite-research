local setting=settings.startup["mir-compiler-profile"]
log("[MIR430-ABLATION] actual-profile="..tostring(setting and setting.value or "absent"))
local names={}
for name in pairs(data.raw.technology or {}) do names[#names+1]=name end
table.sort(names)
log("[MIR430-ABLATION] technology-names="..serpent.line(names))
local active={}
for name,version in pairs(mods or {}) do
  active[#active+1]=name.."@"..version
end
table.sort(active)
log("[MIR_ACTIVE_MODS] "..table.concat(active,"|"))
