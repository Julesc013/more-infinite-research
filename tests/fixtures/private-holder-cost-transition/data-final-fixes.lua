local c=require("contract");local v=mods[c.mir]
assert(v==c.source or v==c.target,"unbound MIR version")
c.same(c.owner_definition(),data.raw.technology[c.owner],"complete foreign owner preserved")
local t=assert(data.raw.technology[c.main],"missing shared authored identity")
assert(t.level==1 and t.max_level=="infinite" and t.upgrade==true and t.enabled~=false,"useful public progression")
local full={{type="gun-speed",ammo_category="tesla",modifier=.1},{type="gun-speed",ammo_category="electric",modifier=.1}}
local selected=v==c.source and full or {full[2]}
c.same(selected,t.effects,"actual admitted partial Tesla coverage")
for category,ids in pairs(c.holders)do
 for direction,id in pairs(ids)do
  local h=data.raw.technology[id]
  if v==c.source then assert(not h,"new holder exists in predecessor")else
   assert(h and h.hidden and h.enabled==false and h.visible_when_disabled==false and h.max_level=="infinite","private holder shape")
   local modifier=direction=="positive" and .1 or (category=="electric" and -.1 or 0)
   c.same({{type="gun-speed",ammo_category=category,modifier=modifier}},h.effects,"conditional native scalar")
  end
 end
end
