local KEY="sourceb_native_owner_fallback_r01"
local OWNER,PRIVATE="recipe-prod-research_steel-1","steel-plate-productivity"
local FOREIGN="native-owner-settings-control"
local SCIENCE={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
local cold=false
local function fail(s) error("[native-owner-settings] "..s) end
local function close(a,b) return type(a)=="number" and math.abs(a-b)<1e-7 end
local function same(a,b,path)
  if type(a)~=type(b) then fail(path.." type") end
  if type(a)=="table" then
    for k,v in pairs(a) do same(v,b[k],path.."."..tostring(k)) end
    for k in pairs(b) do if a[k]==nil then fail(path.." extra") end end
  elseif type(a)=="number" then if not close(a,b) then fail(path.." value") end
  elseif a~=b then fail(path.." value") end
end
local function closure()
  same({base="2.1.23",quality="2.1.23",recycler="2.1.23",["elevated-rails"]="2.1.23",["space-age"]="2.1.23",
    ["more-infinite-research"]="5.0.21011",["mir-fixture-native-owner-fallback"]="0.2.0"},script.active_mods,"mods")
  for key,value in pairs({["ips-cost-base-research_steel"]=2,["ips-cost-linear-increment-research_steel"]=3,
      ["ips-cost-growth-research_steel"]=1.25,["ips-research-time-research_steel"]=1,["ips-effect-per-level-research_steel"]=17}) do
    if settings.startup[key].value~=value then fail("actual selected setting "..key) end
  end
end
local function shape(f)
  local t=f.technologies[OWNER];if not t or not t.valid then fail("native owner absent") end
  local p=t.prototype
  if p.max_level~=4294967295 or p.research_unit_count_formula~="(2+3*(L-1))*1.25^(L-1)"
      or not close(p.research_unit_energy,60) then fail("actual native cost/time/progression") end
  if #p.research_unit_ingredients~=4 or #p.effects~=1 or p.hidden==true then fail("public residual shape") end
  for i,name in ipairs(SCIENCE)do local x=p.research_unit_ingredients[i];if x.name~=name or x.amount~=1 then fail("fallback science")end end
  local e=p.effects[1];if e.type~="change-recipe-productivity" or e.recipe~="mir-fixture-adopt-steel-plate" or not close(e.change,.17) then fail("only uncovered reward") end
  local n=f.technologies[PRIVATE];local np=n.prototype
  if n.level~=1 or n.researched~=false or n.saved_progress~=0 or np.max_level~=4294967295
      or np.research_unit_count_formula~="1000 + 100 * L^2" or not close(np.research_unit_energy,3600) or #np.effects~=3 then fail("foreign native shape") end
  for i,recipe in ipairs({"steel-plate","casting-steel"})do local x=np.effects[i];if x.type~="change-recipe-productivity" or x.recipe~=recipe or not close(x.change,.1)then fail("foreign native recipe effect")end end
  local x=np.effects[3];if x.type~="ammo-damage" or x.ammo_category~="bullet" or not close(x.modifier,.07)then fail("foreign native bullet effect")end

end
local function snapshot(f)
  shape(f);local t=f.technologies[OWNER];local p=f.technologies[PRIVATE];local q={}
  for i,x in ipairs(f.research_queue or {}) do q[i]=x.name end
  return {name=f.name,index=f.index,level=t.level,researched=t.researched,enabled=t.enabled,visible=t.visible_when_disabled,
    saved=t.saved_progress,current=f.current_research and f.current_research.name or false,progress=f.research_progress,
    steel=f.recipes["steel-plate"].productivity_bonus,casting=f.recipes["casting-steel"].productivity_bonus,
    bullet=f.get_ammo_damage_modifier("bullet"),uncovered=f.recipes["mir-fixture-adopt-steel-plate"].productivity_bonus,private={enabled=p.enabled,visible=p.visible_when_disabled,level=p.level,saved=p.saved_progress,hidden=p.prototype.hidden},queue=q,mining=f.mining_drill_productivity_bonus,lab_speed=f.laboratory_speed_modifier}
end
local function verify(s)
  closure();same(s.expected,snapshot(game.forces.player),"earned native state")
  same(s.foreign,snapshot(game.forces[FOREIGN]),"foreign unchanged")
  if s.completions~=1 or not s.lab.valid or s.lab.disabled_by_script~=true or s.lab.active~=false then fail("one stopped native completion") end
  local inv=s.lab.get_inventory(defines.inventory.lab_input)
  for _,name in ipairs(SCIENCE) do if inv.get_item_count(name)~=4 then fail("actual two-science cost") end end
end
local function marker(stage,s)
  local counts={};if s.lab then for _,name in ipairs(SCIENCE) do counts[name]=s.lab.get_inventory(defines.inventory.lab_input).get_item_count(name) end end
  log("[MIR5_NATIVE_OWNER_FALLBACK] "..helpers.table_to_json({status="passed",stage=stage,actor_role="ordinary",
    actual={player=snapshot(game.forces.player),foreign=snapshot(game.forces[FOREIGN])},actual_lab_completions=s.completions,
    completion=s.completion,remaining_science=counts,selected_settings={base=2,increment=3,growth=1.25,time=1,effect=17},
    native_cost_formula="(2+3*(L-1))*1.25^(L-1)",no_acceleration_override=true}))
end
script.on_init(function() if storage[KEY] then fail("storage collision") end;storage[KEY]={phase="pending"} end)
script.on_load(function() cold=true end)
script.on_configuration_changed(function() fail("fresh scenario must not change configuration") end)
script.on_event(defines.events.on_research_finished,function(e)
  local s=storage[KEY];if not s or s.phase=="pending" then return end
  if s.phase~="running" or not e or not e.research or e.research.name~=OWNER
      or e.research.force~=game.forces.player or e.by_script~=false or s.completions~=0 then fail("unexpected native completion") end
  s.lab.disabled_by_script=true;s.completions=1;s.completion={name=e.research.name,by_script=e.by_script,tick=game.tick}
end)
script.on_event(defines.events.on_tick,function()
  local s=storage[KEY];if not s then fail("storage absent") end
  if s.phase=="pending" then
    closure();local f=game.forces.player;shape(f)
    if f.technologies[OWNER].level~=1 or f.recipes["steel-plate"].productivity_bonus~=0
        or f.recipes["casting-steel"].productivity_bonus~=0 or f.get_ammo_damage_modifier("bullet")~=0 then fail("fresh earned state") end
    for _,name in ipairs(SCIENCE) do f.technologies[name].researched=true end
    local control=game.create_force(FOREIGN);control.technologies[OWNER].enabled=false;control.technologies[OWNER].visible_when_disabled=false
    s.foreign=snapshot(control)
    if s.foreign.level~=1 or s.foreign.steel~=0 or s.foreign.casting~=0 or s.foreign.bullet~=0 then fail("unearned foreign control") end
    s.expected=snapshot(f);s.expected.level=2;s.expected.uncovered=.17
    local surface=game.create_surface("sourceb-native-owner-settings-lab",{width=64,height=64});local tiles={}
    for x=-3,3 do for y=-3,3 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end;surface.set_tiles(tiles)
    local lab=surface.create_entity{name="lab",position={0,0},force=f};if not lab or not lab.valid then fail("real lab creation") end
    lab.disabled_by_script=true;local inv=lab.get_inventory(defines.inventory.lab_input)
    for _,name in ipairs(SCIENCE) do if inv.insert{name=name,count=6}~=6 then fail("science supply") end end
    if not f.add_research(OWNER) then fail("native queue admission") end
    s.lab=lab;s.started=game.tick;s.completions=0;s.phase="running";lab.energy=100000000;lab.disabled_by_script=false
  elseif s.phase=="running" then
    if game.tick-s.started>1000 then fail("native completion timeout") end
    if s.completions==0 then s.lab.energy=100000000
    else verify(s);s.phase="complete";marker("complete",s);game.server_save("sourceb-native-owner-fallback-complete") end
  elseif cold then
    if s.phase~="complete" then fail("cold incomplete state") end
    verify(s);marker("cold-complete",s)
  end
  cold=false
end)
