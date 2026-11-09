-- Scenario (__level__) observer: existing MIR default -> explicit preparation -> Ferrum.
-- No MIR imports/private storage access. Setup/selection/supply are administrative;
-- every worker4+, preservation and useful continuation completion requires real labs.
local KEY, LAB = "mir_ferrum_transition_native", "mir-fixture-ferrum-worker-transition-lab"
local C, P, N = "worker-robots-storage-4", "mir-worker-storage-preservation-4", "worker-robots-storage-6"
local S, CAL = "mir-ferrum-transition-sentinel", "mir-ferrum-transition-count-6"
local BASE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack"}
local DEFAULT = {table.unpack(BASE)}; DEFAULT[#DEFAULT + 1] = "electromagnetic-science-pack"
local FOREIGN = {table.unpack(BASE)}; FOREIGN[#FOREIGN + 1] = "ferrum-robotics-science-pack"
local PUBLIC = {table.unpack(FOREIGN)}; PUBLIC[#PUBLIC + 1] = "electromagnetic-science-pack"
local ROWS = {"worker-robots-storage-1", "worker-robots-storage-2", "worker-robots-storage-3",
  C, P, "worker-robots-storage-5", N, "worker-robots-storage-7", "worker-robots-storage-8", S, CAL}
local TUPLES = {
  ["2.1.23"]={mir="5.0.21012",ferrum="0.1.5",planets="2.4.0",spider="2.9.87",recycler=true,modifier_hidden=true},
  ["2.0.77"]={mir="5.0.20012",ferrum="0.0.5",planets="1.18.0",spider="2.9.86",recycler=false,modifier_hidden=false}
}
local loaded, administrative, transferring = false, false, false
local function check(ok, message) if not ok then error("[mir-ferrum-transition] " .. message, 2) end end
local function tuple()
  local selected=TUPLES[script.active_mods.base]; check(selected,"exact supported engine tuple"); return selected
end
local function same(a, b, path)
  path = path or "$"; check(type(a) == type(b), "frame type " .. path)
  if type(a) == "table" then
    for k, v in pairs(a) do same(v, b[k], path .. "/" .. tostring(k)) end
    for k in pairs(b) do check(a[k] ~= nil, "frame extra " .. path .. "/" .. tostring(k)) end
  elseif type(a) == "number" then check(math.abs(a - b) < 1e-9, "frame number " .. path)
  else check(a == b, "frame value " .. path) end
end
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function sorted(v) local out = {table.unpack(v)}; table.sort(out); return out end
local function names(v) local out = {}; for _, t in pairs(v) do out[#out + 1] = t.name end; return sorted(out) end
local function facts(t)
  if not t then return false end
  return {level=t.level, researched=t.researched, enabled=t.enabled, visible=t.visible_when_disabled,
    saved=t.saved_progress, count=t.research_unit_count, first=t.prototype.level, maximum=t.prototype.max_level,
    hidden=t.prototype.hidden, effects=copy(t.prototype.effects), formula=t.prototype.research_unit_count_formula or false,
    time=t.prototype.research_unit_energy, science=copy(t.prototype.research_unit_ingredients),
    prerequisites=names(t.prerequisites), creator=prototypes.get_history("technology", t.name).created}
end
local function frame(f)
  local rows, q = {}, {}; for _, id in ipairs(ROWS) do rows[id] = facts(f.technologies[id]) end
  for _, t in ipairs(f.research_queue or {}) do q[#q + 1] = t.name end
  return {index=f.index, bonus=f.worker_robots_storage_bonus, lab_bonus=f.laboratory_speed_modifier,
    current=f.current_research and f.current_research.name or false, progress=f.research_progress, queue=q, rows=rows}
end
local function frames()
  local out, count = {}, 0
  for name, f in pairs(game.forces) do out[name]=frame(f); count=count+1 end
  check(count <= 16, "bounded forces"); return out
end
local function marker(stage)
  local s = storage[KEY]
  log("[MIR_FERRUM_TRANSITION_NATIVE] " .. helpers.table_to_json({stage=stage, phase=s.phase, tick=game.tick,
    mods=script.active_mods, frames=frames(), ordinary=s.ordinary, consumption=s.consumption,
    administrative_events=s.administrative_events, transfer_events=s.transfer_events,
    price=game.difficulty_settings.technology_price_multiplier, physical_robot_delivery=false}))
end
local function closure(provider)
  local selected, base=tuple(),script.active_mods.base
  local expected = {base=base, ["space-age"]=base, quality=base, ["elevated-rails"]=base,
    ["more-infinite-research"]=selected.mir, [LAB]="0.1.0",
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
  if selected.recycler then expected.recycler=base end
  if provider then expected["planet-ferrum"], expected.PlanetsLib, expected["spider-launcher"] = selected.ferrum, selected.planets, selected.spider end
  same(script.active_mods, expected, "mods")
  check(game.difficulty_settings.technology_price_multiplier == 1, "matching map price1")
  check(settings.startup["mir-max-level-worker-robots-storage"].value == 8
    and settings.startup["mir-enable-worker-robots-storage"].value == true, "matching cap8/enabled")
end
local function science(t, expected)
  local ids, seen = {}, {}
  for _, item in ipairs(t.prototype.research_unit_ingredients) do
    check(item.amount == 1 and not seen[item.name], "science amount/duplicate")
    seen[item.name]=true; ids[#ids+1]=item.name
  end
  same(sorted(ids), sorted(expected), "science")
end
local function effect(t)
  local e=t.prototype.effects
  check(#e==1 and e[1].type=="worker-robot-storage" and e[1].modifier==1, "native effect")
  -- Exact installed SDK representations. Never insert/normalize this member.
  if tuple().modifier_hidden then check(e[1].hidden==false,"F210 native effect hidden")
  else check(e[1].hidden==nil,"F200 native effect hidden must remain absent") end
end
local function default_contract(t)
  check(t and t.prototype.level==4 and t.prototype.max_level==4294967295
    and t.prototype.research_unit_count_formula=="675*1.5^(L-4)"
    and t.prototype.research_unit_energy==3600 and t.prototype.hidden==(t.name==P), "default native contract")
  science(t, DEFAULT); effect(t)
  same(names(t.prerequisites), sorted({"worker-robots-storage-2", "worker-robots-storage-3", table.unpack(DEFAULT)}), "default prerequisites")
  check(prototypes.get_history("technology",t.name).created=="more-infinite-research", "default creation custody")
end
local function foreign_contracts()
  local f=game.forces.player
  for _, row in ipairs({{C,4,675,{"worker-robots-storage-3","ferrum-robotics-science-pack"}},
      {"worker-robots-storage-5",5,1012,{C}}}) do
    local t=f.technologies[row[1]]
    check(t and t.level==row[2] and t.prototype.level==row[2] and t.prototype.max_level==row[2] and t.research_unit_count==row[3]
      and not t.prototype.research_unit_count_formula and t.prototype.research_unit_energy==3600, "finite native contract")
    science(t, FOREIGN); effect(t); same(names(t.prerequisites), sorted(row[4]), "finite prerequisites")
    check(prototypes.get_history("technology",t.name).created=="planet-ferrum", "finite creation custody")
  end
  local t, cal=f.technologies[N], f.technologies[CAL]
  check(t and t.prototype.level==6 and t.prototype.max_level==4294967295
    and t.prototype.research_unit_count_formula=="1518.75*1.5^(L-6)"
    and t.prototype.research_unit_energy==3600 and not t.prototype.hidden, "public6 native contract")
  science(t, PUBLIC); effect(t)
  same(names(t.prerequisites), sorted({C,"worker-robots-storage-5",table.unpack(DEFAULT)}), "public6 prerequisites")
  check(prototypes.get_history("technology",N).created=="more-infinite-research", "public6 custody")
  check(cal.prototype.level==6 and cal.prototype.max_level==6 and cal.prototype.research_unit_count_formula=="1518.75"
    and cal.prototype.research_unit_energy==3600 and #cal.prototype.effects==0 and cal.prototype.hidden
    and not cal.enabled and not cal.researched and cal.saved_progress==0, "literal calibration stays uninvested")
  check(not f.technologies["worker-robots-storage-7"] and not f.technologies["worker-robots-storage-8"] , "no overlapping public tails")
  if t.level==6 and not t.researched then check(t.research_unit_count==cal.research_unit_count, "native fractional calibration") end
end
local function queue(f, ids)
  local q={}; for _, id in ipairs(ids) do q[#q+1]=f.technologies[id] end; f.research_queue=q
  local actual={}; for _, t in ipairs(f.research_queue) do actual[#actual+1]=t.name end
  same(actual, ids, "queue assignment")
end
local function stopped(r)
  check(r.lab.valid and r.lab.disabled_by_script, "lab must remain stopped")
end
local function stop(r)
  r.lab.disabled_by_script=true
end
local function empty(r)
  stopped(r); r.lab.get_inventory(defines.inventory.lab_input).clear(); r.work=nil
end
local function feed(r)
  local t=r.lab.force.current_research; check(t and r.work and t.name==r.work.id, "native current lab work")
  local p=r.lab.force.research_progress
  if p>r.work.initial and p<1 then r.work.progress_seen=true end
  local inv=r.lab.get_inventory(defines.inventory.lab_input)
  for _, i in ipairs(t.research_unit_ingredients) do
    check(r.work.inserted[i.name]~=nil, "lab science changed")
    local amount=math.min(200, r.work.budget[i.name]-r.work.inserted[i.name])
    if amount>0 then r.work.inserted[i.name]=r.work.inserted[i.name]+inv.insert{name=i.name,count=amount,quality="normal"} end
  end
  r.lab.disabled_by_script=false
end
local function begin(r, id, keep_queue)
  empty(r)
  if not keep_queue then queue(r.lab.force,{id}) end
  local f=r.lab.force; check(f.current_research and f.current_research.name==id, "selected actual lab research")
  local t=f.technologies[id]; local budget, inserted={},{}
  check(t.research_unit_count>0 and t.research_unit_count==math.floor(t.research_unit_count), "native integer count")
  for _, i in ipairs(t.research_unit_ingredients) do budget[i.name]=t.research_unit_count*i.amount; inserted[i.name]=0 end
  r.work={id=id, initial=f.research_progress, units=t.research_unit_count, budget=budget, inserted=inserted, progress_seen=false}
end
local function admin_prerequisites(t)
  check(not administrative and not transferring, "administrative window collision"); administrative=true
  local ok, why=pcall(function() for _, p in pairs(t.prerequisites) do p.research_recursive() end end)
  administrative=false; check(ok, "administrative prerequisite setup failed: "..tostring(why))
end
local function source_intent()
  local s=storage[KEY]; local a,b,u=game.forces.player,game.forces["worker-suspended"],game.forces["worker-uninvested"]
  check(a.technologies[C].level==8 and not a.technologies[C].researched and a.current_research.name==C
    and a.research_progress>=.35 and a.research_progress<.5, "source paid current8")
  same(frame(a).queue,{C,S},"source player queue")
  check(b.technologies[C].level==7 and not b.technologies[C].researched and b.technologies[C].saved_progress>=.27
    and b.technologies[C].saved_progress<.4 and b.current_research.name==S and b.research_progress>0, "source suspended7")
  same(frame(b).queue,{S},"source suspended queue")
  check(u.technologies[C].level==4 and not u.technologies[C].researched and not u.technologies[C].enabled
    and u.current_research.name==S and u.research_progress>0, "source uninvested flag/current")
  check(s.ordinary.player[C]==4 and s.ordinary["worker-suspended"][C]==3 and not s.ordinary["worker-uninvested"], "source4/3 ordinary counts")
  check(a.worker_robots_storage_bonus==7 and b.worker_robots_storage_bonus==6 and u.worker_robots_storage_bonus==3, "source native benefit")
end
local function check_prepared()
  local s=storage[KEY]; same(s.ordinary,s.source_ordinary,"no transfer lab earnings")
  for name, old in pairs(s.source) do
    local now=frame(game.forces[name]); local c,h=old.rows[C],now.rows[P]
    local pending=old.current==C or c.saved>0
    for _, id in ipairs(old.queue) do if id==C then pending=true end end
    check(h.level==c.level+(c.researched and 1 or 0) and not h.researched
      and h.enabled==(pending and c.enabled or false) and h.visible==c.visible, "prepared level/flags")
    local contract=copy(c); contract.level,contract.researched,contract.enabled,contract.visible,contract.saved,contract.count=nil,nil,nil,nil,nil,nil
    local private=copy(h); private.level,private.researched,private.enabled,private.visible,private.saved,private.count=nil,nil,nil,nil,nil,nil
    contract.hidden=private.hidden; same(private,contract,"prepared full private contract")
    check(now.rows[C].level==4 and not now.rows[C].researched and now.rows[C].saved==0
      and now.rows[C].enabled==c.enabled and now.rows[C].visible==c.visible, "prepared canonical reset/flags")
    local q={}; for i,id in ipairs(old.queue) do q[i]=id==C and P or id end
    same(now.queue,q,"prepared order"); same(now.rows[S],old.rows[S],"prepared unrelated")
    check(now.current==(old.current==C and P or old.current), "prepared current mapping")
    same(now.progress,old.progress,"prepared current amount"); same(now.bonus,old.bonus,"prepared benefit")
    if old.current==C then same(h.count,c.count,"prepared native price") else same(h.saved,c.saved,"prepared saved work") end
    default_contract(game.forces[name].technologies[P])
  end
  for name in pairs(game.forces) do check(s.source[name]~=nil,"prepared force set changed") end
end
local function provider_entry()
  local s=storage[KEY]; closure(true); foreign_contracts()
  for name, old in pairs(s.prepared) do
    local now=frame(game.forces[name]); same(now.rows[P],old.rows[P],"provider private"); same(now.rows[S],old.rows[S],"provider unrelated")
    same(now.queue,old.queue,"provider queue"); same(now.current,old.current,"provider current")
    same(now.progress,old.progress,"provider progress"); same(now.bonus,old.bonus,"provider benefit")
    for _, id in ipairs({C,"worker-robots-storage-5"}) do
      local t=now.rows[id]; check(t.creator=="planet-ferrum" and not t.researched and t.saved==0, "foreign finite must enter unearned")
    end
    check(now.rows[C].enabled==old.rows[C].enabled and now.rows[C].visible==old.rows[C].visible, "finite4 original flags")
    check(now.rows[N].level==6 and not now.rows[N].researched and now.rows[N].saved==0, "public6 must enter unearned")
    for _, id in ipairs({"worker-robots-storage-1","worker-robots-storage-2","worker-robots-storage-3"}) do same(now.rows[id],old.rows[id],"native predecessor") end
  end
  for name in pairs(game.forces) do check(s.prepared[name]~=nil,"provider force set changed") end
end
local function restore_unrelated(f)
  local old=storage[KEY].prepared[f.name]; local ids={}
  for _, id in ipairs(old.queue) do if id~=P then ids[#ids+1]=id end end
  queue(f,ids)
  if old.current~=P then f.research_progress=old.progress end
  f.technologies[S].saved_progress=old.rows[S].saved
end
local function final_frame()
  local s=storage[KEY]; local now=frames()
  for name, before in pairs(s.provider_entry) do
    local expected=copy(before)
    if name=="player" or name=="worker-suspended" then
      local h=now[name].rows[P]
      check(h.level+(h.researched and 1 or 0)==before.rows[P].level+1 and not h.enabled and h.saved==0, "one retired private completion")
      local preserved=copy(before.rows[P])
      preserved.level,preserved.researched,preserved.enabled,preserved.saved,preserved.count=h.level,h.researched,false,0,h.count
      same(h,preserved,"unchanged private contract/flags"); expected.rows[P]=preserved; expected.bonus=before.bonus+1
      local q={}; for _,id in ipairs(before.queue) do if id~=P then q[#q+1]=id end end
      expected.queue=q; expected.current=q[1] or false
      if before.current==P then expected.progress=0 end
      if name=="player" then
        check(now[name].rows[C].researched and now[name].rows["worker-robots-storage-5"].researched
          and now[name].rows[N].level+(now[name].rows[N].researched and 1 or 0)==7, "ordinary useful public endpoint")
        for _,id in ipairs({C,"worker-robots-storage-5",N}) do
          local row=copy(before.rows[id]); row.level,row.researched,row.count=now[name].rows[id].level,now[name].rows[id].researched,now[name].rows[id].count
          same(now[name].rows[id],row,"only ordinary earned target fields"); expected.rows[id]=row
        end
        expected.bonus=expected.bonus+3
      end
    end
    same(now[name],expected,"final conserved frame/"..name)
  end
  for name in pairs(now) do check(s.provider_entry[name]~=nil,"final force set changed") end
  same(s.ordinary.player,{[C]=5,[P]=1,["worker-robots-storage-5"]=1,[N]=1},"player ordinary counts")
  same(s.ordinary["worker-suspended"],{[C]=3,[P]=1},"suspended ordinary counts")
end
script.on_init(function()
  game.difficulty_settings.technology_price_multiplier=1; game.speed=16; closure(false)
  storage[KEY]={phase="source",labs={},ordinary={},consumption={},administrative_events={},transfer_events={}}
  local s=storage[KEY]
  for i,name in ipairs({"player","worker-suspended","worker-uninvested"}) do
    local f=game.forces[name] or game.create_force(name); default_contract(f.technologies[C]); default_contract(f.technologies[P])
    local private=f.technologies[P]
    check(private.level==4 and not private.researched and not private.enabled and private.saved_progress==0
      and private.visible_when_disabled==false,"empty disabled private source")
    admin_prerequisites(f.technologies[C])
    check(f.technologies[C].level==4 and not f.technologies[C].researched and f.worker_robots_storage_bonus==3, "administrative baseline only")
    f.technologies[C].visible_when_disabled=name~="worker-suspended"
    if name=="worker-uninvested" then f.technologies[C].enabled=false end
    local pos={i*16,0}; local tiles={}
    for x=pos[1]-3,pos[1]+3 do for y=-3,3 do tiles[#tiles+1]={name="grass-1",position={x,y}} end end
    game.surfaces.nauvis.set_tiles(tiles)
    local lab=game.surfaces.nauvis.create_entity{name="mir-ferrum-transition-lab",position=pos,force=f}
    check(lab and lab.valid and f.laboratory_speed_modifier==0, "native lab/baseline")
    lab.disabled_by_script=true
    local r={lab=lab,phase=name=="worker-uninvested" and "sentinel" or "earn",goal=name=="player" and 4 or 3}; s.labs[name]=r
    begin(r,name=="worker-uninvested" and S or C)
  end
  marker("source-init")
end)
script.on_load(function() loaded=true end) -- Local reconnect only.
script.on_configuration_changed(function(event)
  loaded=false; local s=storage[KEY]
  check(s.phase=="prepared-saved", "provider requires closed prepared source")
  s.pre_mir_entry=frames(); marker("level-pre-MIR-configuration")
  closure(true)
  for _, name in ipairs({"planet-ferrum","PlanetsLib","spider-launcher"}) do
    local c=event.mod_changes[name]; check(c and c.old_version==nil and c.new_version==script.active_mods[name], "actual provider dependency addition")
  end
  for name,c in pairs(event.mod_changes) do
    check(name=="planet-ferrum" or name=="PlanetsLib" or name=="spider-launcher" or c.old_version==c.new_version, "other mod changed")
  end
  s.phase="provider-configuration-pending"
end)
commands.add_command("mir-ferrum-transition-probe","Disposable exact worker transition qualification",function(c)
  check(not c.player_index,"server-only fixture command"); local s=storage[KEY]
  if c.parameter=="begin-prepare" then
    check(s.phase=="source-saved" and not administrative and not transferring,"prepare window order")
    source_intent(); same(frames(),s.source,"protected original before transfer")
    transferring=true; s.phase="prepare-open"; marker("prepare-window-open")
  elseif c.parameter=="check-prepare-once" then
    check(s.phase=="prepare-open" and transferring and not s.first_prepare,"first prepare check order")
    check_prepared(); s.first_prepare=frames(); marker("prepare-once-verified")
  elseif c.parameter=="prepared" then
    check(s.phase=="prepare-open" and transferring and s.first_prepare,"prepared command order"); check_prepared()
    same(frames(),s.first_prepare,"idempotent second actual preparation"); transferring=false
    s.prepared=frames(); s.closed=frames(); s.phase="prepared-saved"; marker("prepared-save"); game.server_save("mir-ferrum-transition-prepared")
  elseif c.parameter=="run-provider" then
    check(s.phase=="provider-ready","provider command order"); closure(true); foreign_contracts()
    local f=game.forces["worker-suspended"]; local before=s.prepared[f.name]
    same(frame(f).queue,{S,P},"actual resume append"); same(f.research_progress,before.progress,"actual resume keeps unrelated current")
    same(f.technologies[P].saved_progress,before.rows[P].saved,"actual resume keeps private partial")
    -- Controlled queue selection suspends unrelated current work, then restores
    -- it after the ordinary private/foreign/public endpoints. No earned setters.
    for _,name in ipairs({"player","worker-suspended"}) do local r=s.labs[name]; r.phase="private"; begin(r,P) end
    s.phase="provider-running"; marker("provider-resume-observed")
  else error("unknown fixture command") end
end)
script.on_event(defines.events.on_research_finished,function(e)
  local s=storage[KEY]; if not s then return end
  local id,name=e.research.name,e.research.force.name
  log("[MIR_FERRUM_TRANSITION_EVENT] "..helpers.table_to_json({tick=game.tick,id=id,force=name,phase=s.phase,
    by_script=e.by_script,level=e.research.level,researched=e.research.researched,
    current=e.research.force.current_research and e.research.force.current_research.name or false,
    progress=e.research.force.research_progress,queue=frame(e.research.force).queue}))
  check(id~=CAL,"calibration must never be researched")
  local worker=id==P or id==S or id:match("^worker%-robots%-storage%-[4-9]$")
  if transferring then
    check((id==C or id==P) and type(e.by_script)=="boolean","unexpected transfer event")
    check(#s.transfer_events<256,"bounded transfer events"); s.transfer_events[#s.transfer_events+1]={id=id,force=name,by_script=e.by_script}; return
  elseif administrative then
    check(not worker and e.by_script==true and e.research.prototype.max_level<4294967295,"scripted worker grant")
    check(#s.administrative_events<512,"bounded administrative events"); s.administrative_events[#s.administrative_events+1]={id=id,force=name}; return
  end
  check(e.by_script==false,"ordinary lab provenance")
  local r=s.labs[name]; check(r and r.work and id==r.work.id,"unexpected/duplicate completion")
  check(s.phase=="source" and id==C or s.phase=="provider-running" and (id==P or name=="player" and (id==C or id=="worker-robots-storage-5" or id==N)),"ordinary phase")
  check(r.work.progress_seen,"intermediate ordinary progress missing")
  local inv=r.lab.get_inventory(defines.inventory.lab_input); local consumed={}
  for pack,budget in pairs(r.work.budget) do
    consumed[pack]=r.work.inserted[pack]-inv.get_item_count(pack)
    check(consumed[pack]>0 and consumed[pack]<=budget,"required science was not consumed")
    if r.work.initial==0 then check(consumed[pack]==budget,"full ordinary science consumption") end
  end
  stop(r); s.consumption[#s.consumption+1]={force=name,id=id,initial=r.work.initial,native_units=r.work.units,items=consumed}
  s.ordinary[name]=s.ordinary[name] or {}; s.ordinary[name][id]=(s.ordinary[name][id] or 0)+1
  r.finished=id; r.finished_tick=game.tick; r.phase="completion-pending"; marker("ordinary-finished")
end)
script.on_event(defines.events.on_tick,function()
  local s=storage[KEY]; check(s,"scenario state missing")
  if loaded then
    loaded=false; check(s.phase=="source-saved" or s.phase=="prepared-saved" or s.phase=="destination-saved","cold phase")
    closure(s.phase=="destination-saved"); same(frames(),s.closed,"immutable cold frame")
    for _,r in pairs(s.labs) do stopped(r); check(r.lab.get_inventory(defines.inventory.lab_input).is_empty(),"cold lab inventory") end
    if s.phase=="destination-saved" then foreign_contracts(); final_frame() end
    marker(s.phase.."-cold"); return
  end
  if s.phase=="provider-configuration-pending" then
    provider_entry(); same(frames(),s.pre_mir_entry,"entry before/after MIR configuration")
    s.provider_entry=frames(); s.phase="provider-ready"; marker("provider-ready"); return
  end
  if s.phase=="source" then
    local all=true
    for name,r in pairs(s.labs) do
      local f=r.lab.force
      if r.phase=="completion-pending" and game.tick>r.finished_tick then
        stopped(r); local paid=s.ordinary[name][C]; local t=f.technologies[C]
        check(paid>0 and paid<=r.goal and t.level+(t.researched and 1 or 0)==4+paid,"source paid endpoint")
        queue(f,paid==r.goal and name=="player" and {C,S} or {C}); begin(r,C,true)
        check(t.level==4+paid and not t.researched,"source queued next level")
        r.phase=paid==r.goal and "partial" or "earn"
      end
      if r.phase=="partial" and f.research_progress>=(name=="player" and .35 or .27) then
        stop(r)
        if name=="worker-suspended" then begin(r,S); r.phase="sentinel" else r.phase="ready"; empty(r) end
      elseif r.phase=="sentinel" and f.research_progress>=.01 then stop(r); r.phase="ready"; empty(r) end
      if r.phase~="ready" then all=false; if r.phase~="completion-pending" then feed(r) end end
    end
    if all then
      source_intent(); s.source=frames(); s.source_ordinary=copy(s.ordinary); s.closed=frames(); s.phase="source-saved"
      marker("source-save"); game.server_save("mir-ferrum-transition-source")
    end
  elseif s.phase=="provider-running" then
    for _,name in ipairs({"player","worker-suspended"}) do
      local r=s.labs[name]; local f=r.lab.force
      if r.phase=="completion-pending" and game.tick>r.finished_tick then
        stopped(r); local id=r.finished
        if id==P then
          local before=s.prepared[name]; local t=f.technologies[P]
          check(t.level+(t.researched and 1 or 0)==before.rows[P].level+1 and not t.enabled and t.saved_progress==0
            and f.worker_robots_storage_bonus==before.bonus+1,"private native retirement")
          restore_unrelated(f); empty(r)
          if name=="player" then admin_prerequisites(f.technologies[C]); begin(r,C); r.phase="foreign"
          else r.phase="ready" end
        elseif id==C then check(f.technologies[C].researched,"ordinary finite4"); begin(r,"worker-robots-storage-5"); r.phase="foreign"
        elseif id=="worker-robots-storage-5" then check(f.technologies[id].researched,"ordinary finite5"); begin(r,N); r.phase="public"
        else check(id==N,"unexpected public endpoint"); restore_unrelated(f); empty(r); r.phase="ready" end
      end
      if r.phase~="ready" and r.phase~="completion-pending" then feed(r) end
    end
    if s.labs.player.phase=="ready" and s.labs["worker-suspended"].phase=="ready" then
      final_frame(); foreign_contracts(); s.phase="destination-saved"; s.closed=frames(); marker("destination-save")
      game.server_save("mir-ferrum-transition-destination")
    end
  end
end)
