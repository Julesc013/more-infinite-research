-- Test-only observer of the protected, completed MIR1.1 successor copies.
-- The imported fixture still owns its full independent preservation contract.
-- This imports its finite historical expectations, never MIR implementation.
local historical = require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
local KEY, INTERFACE = "mir5_library_native_input", "mir5-library-native-input"
local BROWSER = "more-infinite-research-browser"
local ROOT, FILTERS, QUERY = "mir_research_browser", "mir_library_filters", "mir_library_query"
local OTHER, OTHER_QUERY = "mir5_input_other", "mir5_input_other_query"
local GEAR, MINING = "recipe-prod-research_gears-1", "recipe-prod-research_mining_drill-1"
local IDS = {"mir-legacy-module-credit-speed-module", "mir-legacy-module-credit-productivity-module",
  "mir-legacy-module-credit-efficiency-module", "mir-legacy-cannon-credit-rocket-shooting-speed"}
local FORCES = {"player", "mir5-migration-origin-f200-110-foreign", "mir5-migration-origin-f200-110-detached"}
local tech_names, recipe_names, recipe_set = {}, {}, {}
for id, effects in pairs(historical.rows) do
  tech_names[#tech_names+1] = id
  for _, effect in ipairs(effects) do
    if effect.type == "change-recipe-productivity" then recipe_set[effect.recipe] = true end
  end
end
table.sort(tech_names)
if #tech_names ~= 31 then error("native input fixture requires the exact31-row historical contract") end
for _, id in ipairs(IDS) do tech_names[#tech_names+1] = id end
for id in pairs(recipe_set) do recipe_names[#recipe_names+1] = id end
table.sort(recipe_names)
local refs, loaded_restart = {}, false
local function fail(message) error("[mir5-library-native-input] " .. message) end
local function valid(value) return value ~= nil and value.valid ~= false end
local function close(a, b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<.000001 end
local function state()
  local value = storage[KEY]
  if type(value)~="table" or value.schema~=1 then fail("observer state is absent") end
  return value
end
local function player(index)
  local value = index and game.get_player(index)
  if not valid(value) then fail("observed player is absent") end
  return value
end
local function client_role(p)
  if p.name=="MIR5English" then return "en" end
  if p.name=="MIR5Deutsch" then return "de" end
  fail("unexpected native client name")
end
local function pair()
  local s=state();local en,de=player(s.en_index),player(s.de_index)
  if client_role(en)~="en" or client_role(de)~="de" or not en.connected or not de.connected or en.locale~="en" or de.locale~="de" or en==de
      or en.force~=game.forces.player or de.force~=en.force then fail("actual EN/DE pair differs") end
  local count=0;for _ in pairs(game.connected_players) do count=count+1 end
  if count~=2 then fail("exactly two connected native clients are required") end
  return en,de
end
local function world()
  local result={}
  for _, name in ipairs(FORCES) do
    local force=game.forces[name]
    if not valid(force) then fail("protected source force is absent") end
    local rows,recipes,queue={},{},{}
    for _, id in ipairs(tech_names) do
      local value=force.technologies[id]
      if not valid(value) then fail("protected technology is absent: "..id) end
      rows[#rows+1]={id,value.level,value.researched,value.enabled,value.visible_when_disabled,value.saved_progress or 0}
    end
    for _, id in ipairs(recipe_names) do
      local value=force.recipes[id]
      if not valid(value) then fail("protected recipe is absent: "..id) end
      recipes[#recipes+1]={id,value.productivity_bonus}
    end
    for _, value in ipairs(force.research_queue or {}) do
      if #queue>=8 then fail("source queue exceeds its finite bound") end
      queue[#queue+1]=value.name
    end
    result[#result+1]={name=name,index=force.index,rows=rows,recipes=recipes,queue=queue,
      current=force.current_research and force.current_research.name or false,progress=force.research_progress,
      mining=force.manual_mining_speed_modifier,battery=force.worker_robots_battery_modifier,
      cannon=force.get_gun_speed_modifier("cannon-shell")}
  end
  return result
end
local function assert_world()
  local s=state();local actual=world()
  for index, expected in ipairs(s.native) do
    local value=actual[index]
    if value.name~=expected.name or value.index~=expected.index or value.current~=expected.current
        or not close(value.progress,expected.progress) or not close(value.mining,expected.mining)
        or not close(value.battery,expected.battery) or not close(value.cannon,expected.cannon)
        or #value.queue~=#expected.queue then fail("native force/queue/aggregate changed") end
    for j,id in ipairs(expected.queue) do if value.queue[j]~=id then fail("native queue identity changed") end end
    for j,row in ipairs(expected.rows) do
      local current=value.rows[j]
      for k=1,5 do if current[k]~=row[k] then fail("retained native technology changed: "..row[1]) end end
      if not close(current[6],row[6]) then fail("retained saved progress changed") end
    end
    for j,row in ipairs(expected.recipes) do
      if value.recipes[j][1]~=row[1] or not close(value.recipes[j][2],row[2]) then fail("retained recipe effect changed") end
    end
  end
end
local function location(root)
  local value=valid(root) and root.location
  if type(value)~="table" or type(value.x)~="number" or type(value.y)~="number" then fail("native root location is absent") end
  return {x=value.x,y=value.y}
end
local function parts(p)
  local root=p.gui.screen[ROOT];local filters=valid(root) and root[FILTERS]
  local query=valid(filters) and filters[QUERY]
  if not valid(root) or root.type~="frame" or root.get_mod()~="more-infinite-research"
      or not valid(query) or query.type~="textfield" then fail("native Library root/query is absent or foreign") end
  return root,query
end
local function open(p,search,selected,sort)
  if remote.call(BROWSER,"open",p.index,{search=search,selected=selected,family="mir",sort=sort or "progression",visibility=1,tab="research"})~=true then fail("public Library open failed") end
end
local function personal(en,de,english_query)
  local er,eq=parts(en);local dr,dq=parts(de)
  if eq.text~=english_query or dq.text~=MINING or er==dr or eq==dq then fail("personal query/roots differ") end
  return er,eq,dr,dq
end
local function assert_retained(en,de,query)
  local er,eq,dr,dq=personal(en,de,query)
  if er~=refs.en_root or eq~=refs.en_query or dr~=refs.de_root or dq~=refs.de_query then fail("native refresh replaced a live root/query") end
  assert_world()
end
local function exclusion_probe(en,de)
  for _, p in ipairs({en,de}) do
    for _, family in ipairs({"all","external"}) do
      local ordinary=family=="all" and GEAR or "automation"
      if remote.call(BROWSER,"open",p.index,{search=ordinary,selected=ordinary,family=family,visibility=1,tab="research"})~=true then fail("ordinary positive query failed") end
      local ordinary_content=p.gui.screen[ROOT].mir_library_tabs.mir_library_research_content
      if not valid(ordinary_content.mir_library_results) or #ordinary_content.mir_library_results.items<1
          or ordinary_content.mir_library_results.selected_index<1
          or not valid(ordinary_content.mir_library_detail.mir_library_detail_title)
          or ordinary_content.mir_library_actions.mir_library_open_native.enabled~=true then fail("ordinary inspection positive control failed") end
      for _, id in ipairs(IDS) do
        if remote.call(BROWSER,"open",p.index,{search=id,selected=id,family=family,visibility=1,tab="research"})~=true then fail("private query failed") end
        local root=p.gui.screen[ROOT];local filters=valid(root) and root[FILTERS]
        local tabs=valid(root) and root.mir_library_tabs
        local content=valid(tabs) and tabs.mir_library_research_content
        local results=valid(content) and content.mir_library_results
        local detail=valid(content) and content.mir_library_detail
        local actions=valid(content) and content.mir_library_actions
        local button=valid(actions) and actions.mir_library_open_native
        if not valid(filters) or filters[QUERY].text~=id or filters.mir_library_family.selected_index~=(family=="all" and 2 or 3)
            or not valid(results) or #results.items~=0 or results.selected_index~=0
            or not valid(detail) or valid(detail.mir_library_detail_title) or not valid(detail.mir_library_detail_empty)
            or not valid(button) or button.enabled~=false then fail("imported private research/action exposed") end
      end
    end
  end
  local s=state();s.private_queries=s.private_queries+16
  assert_world()
end
local function check_imported_literals()
  for _, name in ipairs(FORCES) do
    local force=game.forces[name]
    for index,id in ipairs(IDS) do
      local value=force.technologies[id]
      if not valid(value) or value.level~=(index<4 and 2 or 1) or value.researched~=false
          or value.enabled~=false or value.visible_when_disabled~=false or value.prototype.hidden~=true then fail("imported credit baseline differs") end
    end
    for _, id in ipairs({"speed-module","productivity-module","efficiency-module"}) do
      if not close(force.recipes[id].productivity_bonus,.11) then fail("actual imported module effect differs") end
    end
  end
  local force=game.forces.player
  if force.technologies[GEAR].level~=3 or not close(force.recipes["iron-gear-wheel"].productivity_bonus,.2) then fail("completed imported gear baseline differs") end
end
local function geometry(p)
  if not valid(p) then return nil end
  local root=p.gui.screen[ROOT]
  if not valid(root) then root=p.gui.screen[OTHER] end
  if not valid(root) then return nil end
  return {location=location(root),style_maximal_width=root.style.maximal_width,display_scale=p.display_scale,display_resolution=p.display_resolution}
end
local function input_state(p)
  if not valid(p) then return false end
  local root=p.gui.screen[ROOT];local filters=valid(root) and root[FILTERS] or nil
  local query=valid(filters) and filters[QUERY] or nil
  local other=p.gui.screen[OTHER];local other_query=valid(other) and other[OTHER_QUERY] or nil
  return {library_open=valid(root)==true,
    library_query=valid(query) and query.type=="textfield" and query.text or false,
    foreign_open=valid(other)==true and p.opened==other,
    foreign_query=valid(other_query) and other_query.type=="textfield" and other_query.text or false}
end
local function report()
  local s=storage[KEY];if type(s)~="table" then return nil end
  local en=s.en_index~=nil and game.get_player(s.en_index) or nil
  local de=s.de_index~=nil and game.get_player(s.de_index) or nil
  return {schema=1,case="library-native-input-imported110",phase=s.phase,tick=game.tick,
    actual_joins=s.joins,actual_text_events=s.text_events,actual_library_closed_events=s.closed_events,
    actual_library_close_observations=s.close_observations,
    actual_drag_events=s.drag_events,actual_effect_reset_events=s.reset_events,requested_native_resets=s.requested_resets,actual_removed_events=s.removed_events,
    initial_location=s.initial_location,drag_baseline=s.drag_baseline,drag_events_before=s.drag_events_before,
    private_queries=s.private_queries,en_index=s.en_index or false,de_index=s.de_index or false,
    en_name=valid(en) and en.name or false,de_name=valid(de) and de.name or false,
    en_locale=valid(en) and en.locale or false,de_locale=valid(de) and de.locale or false,
    en_connected=valid(en) and en.connected or false,de_connected=valid(de) and de.connected or false,
    en_input=input_state(en),de_input=input_state(de),
    removed_index=s.removed_index or false,readonly_imported_probe=s.imported_probe_verified==true,
    imported_earnings=true,fixture_seeds_credit=false,load_observed=loaded_restart,
    en_geometry=s.en_index and geometry(game.get_player(s.en_index)) or nil,
    de_geometry=s.de_index and geometry(game.get_player(s.de_index)) or nil,
    original_preservation_fixture_required=true,performance_acceptance=false,release_qualification=false}
end
local function phase(expected)
  local s=state();if s.phase~=expected then fail("step out of order: "..s.phase.." expected "..expected) end
  return s
end
local function closed(expected)
  local s=state();local en=player(s.en_index)
  if s.closed_events~=expected or s.close_expected~=nil or not s.last_close or s.last_close.ordinal~=expected
      or valid(refs.en_root) or valid(refs.en_query) or valid(en.gui.screen[ROOT]) then fail("actual key did not retire the Library root/query") end
  assert_world();return en
end
local function opened_scalar(value, getter)
  local ok, result=pcall(getter)
  if not ok then return "<getter-error>" end
  if result==nil then return "<absent>" end
  if type(result)=="string" then return result end
  return "<"..type(result)..">"
end
local function opened_diagnostic(en, root)
  local opened_ok, opened=pcall(function()return en.opened end)
  if not opened_ok then return "opened_getter=<error>" end
  local equal_ok, equal=pcall(function()return opened==root end)
  local valid_ok, is_valid=pcall(function()return opened~=nil and opened.valid==true end)
  local opened_name=opened_scalar(opened,function()return opened and opened.name end)
  local opened_mod=opened_scalar(opened,function()
    local getter=opened and opened.get_mod
    return type(getter)=="function" and getter() or nil
  end)
  local root_name=opened_scalar(root,function()return root.name end)
  local root_mod=opened_scalar(root,function()
    local getter=root.get_mod
    return type(getter)=="function" and getter() or nil
  end)
  return "opened_type="..type(opened).." opened_is_root="..tostring(equal_ok and equal==true)
    .." opened_valid="..tostring(valid_ok and is_valid==true).." opened_name="..opened_name
    .." opened_mod="..opened_mod.." root_name="..root_name.." root_mod="..root_mod
end
local function arm_close(en, expected_phase)
  local s=state()
  if s.close_expected~=nil or not valid(refs.en_root) or not valid(refs.en_query) or en.opened~=refs.en_root then
    fail("declared key close has no owned opened Library: "..opened_diagnostic(en,refs.en_root))
  end
  s.close_expected={phase=expected_phase,player_index=en.index,ordinal=s.closed_events+1}
end
local function advance(step)
  local s=state()
  if step=="inspect" then
    phase("waiting-clients");local en,de=pair();assert_world();check_imported_literals()
    exclusion_probe(en,de);open(en,"",GEAR);open(de,MINING,MINING,"native")
    refs.en_root,refs.en_query,refs.de_root,refs.de_query=personal(en,de,"")
    s.initial_location=location(refs.en_root);s.imported_probe_verified=true;s.phase="text-prefix"
  elseif step=="prefix" then
    phase("text-prefix");local en,de=pair();assert_retained(en,de,"ge")
    if s.query_clicks<1 or s.text_events<1 then fail("actual query click/text events are absent") end
    s.requested_resets=s.requested_resets+1;s.expected_reset_events=s.reset_events+1
    en.force.reset_technology_effects();s.wait_tick=game.tick+60;s.phase="prefix-refresh"
  elseif step=="refresh" then
    phase("prefix-refresh");local en,de=pair()
    if game.tick<s.wait_tick or s.reset_events~=s.expected_reset_events then fail("native refresh observation is not ready") end
    assert_retained(en,de,"ge");s.phase="text-suffix"
  elseif step=="suffix" then
    phase("text-suffix");local en,de=pair();assert_retained(en,de,"gears")
    s.drag_baseline=location(refs.en_root);s.drag_events_before=s.drag_events;s.phase="drag"
  elseif step=="drag" then
    phase("drag");local en,de=pair();assert_retained(en,de,"gears")
    local point=location(refs.en_root)
    if s.drag_events<=s.drag_events_before or point.x~=s.drag_baseline.x-30 or point.y~=s.drag_baseline.y then
      fail(string.format("actual native drag differs: baseline=(%s,%s) point=(%s,%s) events_before=%s events_now=%s",
        s.drag_baseline.x,s.drag_baseline.y,point.x,point.y,s.drag_events_before,s.drag_events))
    end
    s.drag_location=point;s.phase="escape";arm_close(en,"escape")
  elseif step=="escape" then
    phase("escape");local en=closed(1);local de=player(s.de_index);local old_root,old_query=refs.en_root,refs.en_query
    open(en,"gears",GEAR);refs.en_root,refs.en_query,refs.de_root,refs.de_query=personal(en,de,"gears")
    local point=location(refs.en_root)
    if refs.en_root==old_root or refs.en_query==old_query or point.x~=s.drag_location.x or point.y~=s.drag_location.y then fail("reopen lost location or reused retired root") end
    s.phase="inventory";arm_close(en,"inventory")
  elseif step=="inventory" then
    phase("inventory");local en=closed(2)
    local other=en.gui.screen.add{type="frame",name=OTHER,direction="vertical",caption="MIR fixture focus observation"}
    other.style.width=320;other.style.height=160;other.location={x=80,y=80}
    refs.other=other;refs.other_query=other.add{type="textfield",name=OTHER_QUERY,text=""}
    en.opened=other;s.phase="foreign-prefix"
  elseif step=="foreign-prefix" then
    phase("foreign-prefix");local en=player(s.en_index)
    if en.opened~=refs.other or refs.other_query.text~="focus" or s.other_clicks<1 then fail("actual foreign GUI input is absent") end
    s.requested_resets=s.requested_resets+1;s.expected_reset_events=s.reset_events+1
    en.force.reset_technology_effects();s.wait_tick=game.tick+60;s.phase="foreign-refresh"
  elseif step=="foreign-refresh" then
    phase("foreign-refresh");local en=player(s.en_index)
    if game.tick<s.wait_tick or s.reset_events~=s.expected_reset_events or en.opened~=refs.other or valid(en.gui.screen[ROOT])
        or refs.other_query.text~="focus" then fail("native refresh stole foreign GUI focus") end
    assert_world();s.phase="foreign-suffix"
  elseif step=="foreign-suffix" then
    phase("foreign-suffix");local en=player(s.en_index)
    if en.opened~=refs.other or refs.other_query.text~="focus kept" then fail("actual foreign typing lost focus") end
    refs.other.destroy();refs.other=nil;refs.other_query=nil
    open(en,"gears",GEAR);s.phase="disconnect-de";assert_world()
  elseif step=="remove-de" then
    phase("disconnect-de");local de=player(s.de_index)
    if de.connected then fail("test German client must disconnect before removal") end
    s.removed_index=de.index;s.phase="removing-de";game.remove_offline_players({de.index})
    if s.removed_events~=1 or valid(game.get_player(s.removed_index)) or valid(refs.de_root) or valid(refs.de_query) then fail("actual offline player/root removal differs") end
    s.de_index=nil;s.phase="replacement";assert_world()
  elseif step=="replacement" then
    phase("replacement");local en,de=pair()
    if de.index==s.removed_index or s.joins~=3 then fail("actual replacement client join differs") end
    open(de,MINING,MINING,"native");personal(en,de,"gears");s.wait_tick=game.tick+60;s.phase="pre-save";assert_world()
  elseif step=="save" then
    phase("pre-save");local en,de=pair();if game.tick<s.wait_tick then fail("save render grace is incomplete") end
    personal(en,de,"gears");exclusion_probe(en,de);open(en,"gears",GEAR);open(de,MINING,MINING,"native")
    s.phase="awaiting-restart";game.server_save("mir5-library-native-input-restart")
  elseif step=="restart" then
    phase("awaiting-restart");local en,de=pair()
    if not loaded_restart or s.joins~=5 then fail("actual saved-host reconnect differs") end
    local er=personal(en,de,"gears");local point=location(er)
    if point.x~=s.drag_location.x or point.y~=s.drag_location.y then fail("saved native drag location was lost") end
    assert_world();check_imported_literals();exclusion_probe(en,de)
    open(en,"gears",GEAR);open(de,MINING,MINING,"native");s.wait_tick=game.tick+60;s.phase="completed"
  elseif step=="complete-save" then
    phase("completed");local en,de=pair();if game.tick<s.wait_tick then fail("final render grace is incomplete") end
    personal(en,de,"gears");assert_world();s.phase="delivered";game.server_save("mir5-library-native-input-complete")
  else fail("unknown fixed observation step") end
  log("[MIR5_LIBRARY_NATIVE_INPUT] "..helpers.table_to_json(report()))
  return report()
end
-- The separate0.4 observer reuses only these independent protected-save assertions.
-- Original0.1/0.2 sources and packets remain pinned by their historical records.
if script.active_mods["mir-fixture-mir5-library-native-input"] == "0.4.0" then
  require("support-exports").register({key=KEY,interface=INTERFACE,world=world,assert_world=assert_world,
    imported=check_imported_literals,historical_fixture=historical.fixture})
  return
end
remote.add_interface(INTERFACE,{report=report,advance=advance})
script.on_init(function()
  local expected=script.active_mods.base=="2.0.77" and {mir="5.0.20000",fixture="0.3.0"}
    or (script.active_mods.base=="2.1.23" and {mir="5.0.21000",fixture="0.4.0"})
  if not expected or script.active_mods["more-infinite-research"]~=expected.mir
      or script.active_mods[historical.fixture]~=expected.fixture then fail("imported native target differs") end
  local allowed={base=script.active_mods.base,["more-infinite-research"]=expected.mir,[historical.fixture]=expected.fixture,
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0",["mir-fixture-mir5-library-native-input"]="0.3.0"}
  for name,version in pairs(script.active_mods) do if allowed[name]~=version then fail("unexpected imported observer closure") end end
  for name,version in pairs(allowed) do if script.active_mods[name]~=version then fail("missing imported observer closure member") end end
  for _ in pairs(game.players) do fail("protected headless source must contain no pre-existing players") end
  if storage[KEY]~=nil then fail("observer state already exists") end
  storage[KEY]={schema=1,phase="waiting-clients",native=world(),joins=0,restart_joins={},text_events=0,closed_events=0,
    drag_events=0,reset_events=0,requested_resets=0,removed_events=0,private_queries=0,query_clicks=0,other_clicks=0,imported_probe_verified=false,close_observations={}}
  check_imported_literals()
end)
script.on_load(function()local s=storage[KEY];loaded_restart=type(s)=="table" and s.phase=="awaiting-restart";refs={} end)
script.on_event(defines.events.on_player_joined_game,function(event)
  local s=state();local p=player(event.player_index)
  if p.connected~=true then fail("actual joined client is disconnected") end
  local joined_role=client_role(p);local key=joined_role.."_index"
  if not loaded_restart and s.phase=="waiting-clients" then
    if s[key]~=nil then fail("duplicate initial client role") end
  elseif not loaded_restart and s.phase=="replacement" and joined_role=="de" then
    if s.de_index~=nil or s.removed_index==nil or p.index==s.removed_index or p.index==s.en_index then fail("replacement identity differs") end
  elseif loaded_restart and s.phase=="awaiting-restart" then
    if s[key]~=p.index or s.restart_joins[joined_role] then fail("saved client identity or restart role differs") end
    s.restart_joins[joined_role]=true
  else fail("unexpected client join role or phase") end
  s[key]=p.index
  s.joins=s.joins+1
end)
script.on_event(defines.events.on_gui_text_changed,function(event)
  local s=state();if event.player_index==s.en_index and (event.element==refs.en_query or event.element==refs.other_query) then s.text_events=s.text_events+1 end
end)
script.on_event(defines.events.on_gui_click,function(event)
  local s=state();if event.player_index~=s.en_index then return end
  if event.element==refs.en_query then s.query_clicks=s.query_clicks+1 end
  if event.element==refs.other_query then s.other_clicks=s.other_clicks+1 end
end)
script.on_event(defines.events.on_gui_location_changed,function(event)
  local s=state();if event.player_index==s.en_index and event.element==refs.en_root then s.drag_events=s.drag_events+1 end
end)
script.on_event(defines.events.on_gui_closed,function(event)
  local s=state();local armed=s.close_expected
  if not armed or event.player_index~=s.en_index or event.player_index~=armed.player_index
      or s.phase~=armed.phase or event.gui_type~=defines.gui_type.custom then return end
  -- The owning mod may have destroyed its root before this observer runs.
  -- Retain the actual custom-close event before any optional element getter;
  -- root disappearance without this armed same-player event cannot pass.
  local row={phase=s.phase,player_index=event.player_index,gui_type=event.gui_type,ordinal=armed.ordinal,
    element_present=event.element~=nil,accepted=false}
  if #s.close_observations>=8 then fail("declared close observation bound exceeded") end
  s.close_observations[#s.close_observations+1]=row
  local ok,element_valid=pcall(function()return valid(event.element)end)
  row.element_valid=ok and element_valid==true
  local same_ok,same=pcall(function()return event.element==refs.en_root end)
  row.same_root=same_ok and same==true
  local name_ok,name=pcall(function()return event.element and event.element.name end)
  row.element_name=name_ok and type(name)=="string" and name or false
  if row.element_valid and not row.same_root then return end
  local en=player(s.en_index)
  if not row.element_valid and (valid(refs.en_root) or valid(refs.en_query) or valid(en.gui.screen[ROOT])) then return end
  row.accepted=true;s.closed_events=s.closed_events+1;s.last_close=row;s.close_expected=nil
end)
script.on_event(defines.events.on_technology_effects_reset,function(event)
  local s=state();if event.force==game.forces.player then s.reset_events=s.reset_events+1 end
end)
script.on_event(defines.events.on_player_removed,function(event)
  local s=state();if s.phase~="removing-de" or event.player_index~=s.removed_index then fail("unexpected player removal") end
  s.removed_events=s.removed_events+1
end)
