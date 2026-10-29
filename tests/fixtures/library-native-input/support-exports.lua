-- Test-only native GUI/export consumer. Existing protected-save assertions
-- remain the oracle; native helpers unpack data and the public facade validates.
-- No MIR import, profile encoder, file reader/writer or gameplay mutation.
local M = {}
function M.register(context)
  local ROOT, PREFIX = "mir_research_browser", "mir_library_"
  local BROWSER, PROFILES = "more-infinite-research-browser", "more-infinite-research-settings"
  local NAME, OTHER = "mir-fixture-mir5-library-native-input", "mir_export_foreign"
  local refs, loaded = {}, false
  local actions = {
    {"en-full","en","full"},{"en-compact","en","compact"},{"en-diagnostics","en","diagnostics"},
    {"de-full","de","full"},{"de-compact","de","compact"},{"de-diagnostics","de","diagnostics"},
    {"en-foreign","en","foreign"},{"en-full-before-failure","en","full"},
    {"en-settings-failure","en","settings-failure"},{"en-diagnostics-before-failure","en","diagnostics"},
    {"en-diagnostics-failure","en","diagnostics-failure"},{"de-rejoin-full","de","full"},
    {"en-restart-full","en","full"},
  }
  local function fail(message) error("[mir-library-support-exports] " .. message) end
  local function valid(value) return value ~= nil and value.valid ~= false end
  local function state()
    local value = storage[context.key]
    if type(value)~="table" or value.schema~=1 or value.case~="library-support-exports" then fail("observer state differs") end
    return value
  end
  local function startup()
    local result,count = {},0
    for name,value in pairs(settings.startup) do
      count=count+1
      if count>2048 or type(name)~="string" then fail("startup snapshot bound exceeded") end
      local scalar=value.value
      if type(scalar)~="string" and type(scalar)~="number" and type(scalar)~="boolean" then fail("startup scalar differs") end
      result[name]=scalar
    end
    return result
  end
  local function unchanged()
    context.assert_world();context.imported()
    local current,s = startup(),state()
    for name,value in pairs(s.settings) do if current[name]~=value or type(current[name])~=type(value) then fail("startup setting changed") end end
    for name in pairs(current) do if s.settings[name]==nil then fail("startup setting added") end end
  end
  local function pair()
    local s=state();local en=game.get_player(s.en_index);local de=game.get_player(s.de_index)
    if not valid(en) or not valid(de) or not en.connected or not de.connected or en.locale~="en" or de.locale~="de"
        or en==de or en.force~=game.forces.player or de.force~=en.force then fail("actual EN/DE pair differs") end
    local count=0;for _ in pairs(game.connected_players) do count=count+1 end
    if count~=2 then fail("exactly two connected native clients required") end
    return en,de
  end
  local function owner(p)
    local root=p.gui.screen[ROOT]
    if not valid(root) or root.get_mod()~="more-infinite-research" or root.tags["more-infinite-research.library-root.v1"]~=true then fail("MIR native GUI owner differs") end
    return root
  end
  local function content(root,kind)
    local tabs=root[PREFIX.."tabs"]
    local node=valid(tabs) and tabs[PREFIX..((kind=="diagnostics" or kind=="diagnostics-failure") and "help_content" or "settings_content")]
    if not valid(node) then fail("native export content absent") end
    return node
  end
  local function preview(p,kind)
    return content(owner(p),kind)[PREFIX.."export_profile"]
  end
  local function report()
    local s=state();unchanged()
    local geometry={}
    for _,role in ipairs({"en","de"}) do
      local index=s[role.."_index"]
      local p=index and game.get_player(index) or nil
      if valid(p) then
        local root=p.gui.screen[ROOT]
        geometry[role]={index=p.index,connected=p.connected,scale=p.display_scale,resolution=p.display_resolution,
          location=valid(root) and root.location or false}
      end
    end
    return {case=s.case,phase=s.phase,cursor=s.cursor,expected=actions[s.cursor] and actions[s.cursor][1] or false,
      actual_clicks=s.clicks,actual_joins=s.joins,server_commands=s.server_commands,completed=s.completed,
      native_and_settings_unchanged=true,geometry=geometry,load_observed=loaded,
      files_require_external_readback=true,engine_log_exported=false,performance_acceptance=false,release_qualification=false}
  end
  local function prepare(action)
    local s=state();local expected=actions[s.cursor]
    if not expected or action~=expected[1] or s.phase~="ready" then fail("action order differs") end
    unchanged();local en,de=pair();local p=expected[2]=="en" and en or de
    if action=="de-rejoin-full" and s.joins<3 then fail("actual client rejoin missing") end
    if action=="en-restart-full" and (not loaded or s.joins<5) then fail("actual saved-host restart/rejoins missing") end
    local kind=expected[3]
    if kind=="foreign" then
      if valid(p.gui.screen[ROOT]) then fail("close MIR with actual native input before foreign control") end
      local foreign=p.gui.screen.add{type="frame",name=OTHER,caption="MIR export ownership control",direction="vertical"}
      foreign.location={x=80,y=80}
      refs.foreign=foreign;refs.button=foreign.add{type="button",name=PREFIX.."export_settings",caption="Foreign matching-name export control"}
      p.opened=foreign
    else
      if valid(refs.foreign) then refs.foreign.destroy() end
      local help=kind=="diagnostics" or kind=="diagnostics-failure"
      local existing=p.gui.screen[ROOT]
      if not valid(existing) or not valid(existing[PREFIX.."tabs"])
          or existing[PREFIX.."tabs"].selected_tab_index~=(help and 4 or 3) then
        if remote.call(BROWSER,"open",p.index,{tab=help and "help" or "settings"})~=true then fail("public browser open failed") end
      end
      local root=owner(p);local node=content(root,kind)
      refs.previous=node[PREFIX.."export_profile"]
      if (kind=="settings-failure" or kind=="diagnostics-failure") and not valid(refs.previous) then fail("failure control requires an existing successful preview") end
      local button_name=(kind=="compact" and "export_compact") or ((kind=="diagnostics" or kind=="diagnostics-failure") and "export_diagnostics") or "export_settings"
      refs.button=(button_name=="export_diagnostics" and node or node[PREFIX.."settings_toolbar"])[PREFIX..button_name]
      if not valid(refs.button) or refs.button.get_mod()~="more-infinite-research" then fail("actual export button absent") end
    end
    refs.player=p.index;s.pending=action;s.click_start=s.clicks;s.phase="await-click"
    unchanged();return report()
  end
  local function check(action)
    local s=state();local expected=actions[s.cursor]
    if not expected or action~=expected[1] or s.pending~=action or s.phase~="await-click" or s.clicks~=s.click_start+1 then fail("unique actual export click missing") end
    unchanged();local en,de=pair();local p=expected[2]=="en" and en or de
    local kind=expected[3];local result=report()
    if kind~="foreign" then
      local box=preview(p,kind)
      if valid(refs.previous) then fail("previous export preview was not retired") end
      if kind=="settings-failure" or kind=="diagnostics-failure" then
        if valid(box) then fail("failed export retained a preview") end
        result.native_failure_message_requires_screenshot=true
      else
        if not valid(box) or box.type~="text-box" or box.read_only~=true or type(box.text)~="string"
            or #box.text>65536 or box.text:sub(1,8)~="MIRSET1:" then fail("selectable exact profile absent for "..action) end
        local validation=remote.call(PROFILES,"validate_string",box.text)
        if validation.valid~=true or validation.invalid~=0 or validation.unknown~=0 then fail("existing public validation failed") end
        -- Independent test consumer only: engine decompression/JSON helpers.
        -- All validation remains the shipped public facade; no codec is copied.
        local decoded=helpers.json_to_table(helpers.decode_string(box.text:sub(9)))
        if type(decoded)~="table" or decoded.metadata.exported_by~=p.name
            or decoded.metadata.mir_version~=script.active_mods["more-infinite-research"] then fail("export metadata differs") end
        local count,false_count,zero_count=0,0,0
        for name,value in pairs(decoded.settings) do
          count=count+1
          if count>2048 then fail("profile settings bound exceeded") end
          if s.settings[name]~=nil and (s.settings[name]~=value or type(s.settings[name])~=type(value)) then fail("export setting value/type differs") end
          if value==false then false_count=false_count+1 end
          if type(value)=="number" and value==0 then zero_count=zero_count+1 end
        end
        if kind~="compact" and (count==0 or false_count==0 or zero_count==0) then fail("full false/zero witnesses absent") end
        result.encoded_profile=box.text;result.recognized_settings=validation.recognized
        result.settings=count;result.false_values=false_count;result.zero_values=zero_count
        result.selectable_native_text_box=true;result.exported_by=p.name
      end
    end
    s.completed[action]=true;s.cursor=s.cursor+1;s.pending=nil;s.phase="ready"
    if s.cursor>#actions then s.phase="completed";game.server_save("mir5-native-complete") end
    result.completed_action=action;result.native_and_settings_unchanged=true
    log("[MIR5_LIBRARY_SUPPORT_EXPORT] "..helpers.table_to_json(result))
    return result
  end
  local function checkpoint()
    local s=state();unchanged();pair()
    if s.cursor~=13 or s.phase~="ready" or s.server_commands~=2 then fail("pre-restart actions/server exports incomplete") end
    s.phase="await-restart";game.server_save("mir5-library-support-exports-restart")
    return report()
  end
  remote.add_interface(context.interface,{report=report,prepare=prepare,check=check,checkpoint=checkpoint})
  script.on_init(function()
    local mods=script.active_mods
    local tuple=mods.base=="2.0.77" and {mir="5.0.20000",fixture="0.3.0"}
      or (mods.base=="2.1.23" and {mir="5.0.21000",fixture="0.4.0"})
    if not tuple then fail("exact engine target differs") end
    local allowed={base=mods.base,["more-infinite-research"]=tuple.mir,[context.historical_fixture]=tuple.fixture,
      ["mir-fixture-mir5-active-mods-observer"]="0.1.0",[NAME]="0.2.0"}
    for name,version in pairs(mods) do if allowed[name]~=version then fail("unexpected export observer closure") end end
    for name,version in pairs(allowed) do if mods[name]~=version then fail("missing export observer closure") end end
    for _ in pairs(game.players) do fail("protected headless source must have no existing players") end
    if storage[context.key]~=nil then fail("observer state already exists") end
    storage[context.key]={schema=1,case="library-support-exports",phase="ready",cursor=1,native=context.world(),
      settings=startup(),clicks=0,joins=0,server_commands=0,completed={}}
    unchanged()
  end)
  script.on_load(function()
    local s=storage[context.key];loaded=type(s)=="table" and (s.phase=="await-restart" or s.phase=="completed");refs={}
  end)
  script.on_event(defines.events.on_player_joined_game,function(event)
    local s=state();local p=game.get_player(event.player_index)
    if not valid(p) or (p.locale~="en" and p.locale~="de") then fail("joined client differs") end
    local key=p.locale.."_index"
    if s[key] and s[key]~=p.index then fail("export client identity changed") end
    s[key]=p.index;s.joins=s.joins+1
    if loaded and s.phase=="await-restart" then s.phase="ready" end
    unchanged()
  end)
  script.on_event(defines.events.on_gui_click,function(event)
    if event.element~=refs.button then return end
    local s=state()
    if s.phase~="await-click" or event.player_index~=refs.player then fail("unexpected export click/player") end
    s.clicks=s.clicks+1
  end)
  script.on_event(defines.events.on_console_command,function(event)
    if event.command~="mir-settings-export" and event.command~="mir-diagnostics-export" then return end
    if event.player_index~=nil and event.player_index~=0 then fail("expected explicit server-console export") end
    local s=state();s.server_commands=s.server_commands+1;unchanged()
  end)
end
return M
