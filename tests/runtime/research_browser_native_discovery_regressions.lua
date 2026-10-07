-- Opposing controls for the native witness's completion protocol. These small
-- copied tables establish neither engine translation nor native GUI evidence.
return function(core, adapter, native_source, fixture_source, check)
  local technology = "mir-browser-discovery-native"
  local function materialize_fixture(modern)
    local raw = {}
    local data = {raw={recipe={["iron-plate"]=modern and {categories={"smelting"}} or {category="smelting"}}},extend=function(_, rows)
      for _, row in ipairs(rows) do raw[row.type] = raw[row.type] or {}; raw[row.type][row.name] = row end
    end}
    assert(load(fixture_source, "native-discovery-data", "t", {
      data=data,math=math,string=string,table=table,ipairs=ipairs
    }))()
    return raw
  end
  local raw = materialize_fixture(false)
  local modern = materialize_fixture(true).recipe["mir-browser-discovery-recipe"]
  check(raw.recipe["mir-browser-discovery-recipe"].category == "chemistry"
    and raw.recipe["mir-browser-discovery-recipe"].categories == nil,
    "native discovery fixture retains the 2.0 recipe category")
  check(modern.category == nil and #modern.categories == 1 and modern.categories[1] == "chemistry",
    "native discovery fixture uses the observed 2.1 recipe categories")
  local library = {recipe={},item=raw.item,fluid=raw.fluid}
  for name, recipe in pairs(raw.recipe) do
    library.recipe[name] = {localised_name=recipe.localised_name,products=recipe.results}
  end
  local tech = {name=technology,localised_name=raw.technology[technology].localised_name,
    prototype={effects=raw.technology[technology].effects}}
  check(raw.fluid["mir-browser-discovery-fluid"].auto_barrel == false,
    "native fluid fixture prevents barrel unlocks from adding unrelated discovery matches")
  local function flatten(value)
    if type(value) == "string" then return value end
    if value[1] == "?" then return flatten(value[2]) end
    assert(value[1] == "")
    local parts = {}; for index=2,#value do parts[#parts+1] = flatten(value[index]) end
    return table.concat(parts)
  end
  local payload, subjects, limited = adapter.translation_request(tech, library, 128)
  local translated = flatten(payload)
  check(subjects == 34 and not limited and #translated > 1024,
    "actual native data fixture has the intended bounded recipe/item/fluid payload")
  local function scenario(player_count)
    local event, tick, result, requests, count = nil, nil, nil, {}, 0
    local players, game = {}, {tick=0,connected_players={}}
    local function verify(ok, message) count=count+1; assert(ok,message) end
    for index=1,player_count do
      local root = {valid=true,children={}}
      local search = {valid=true,text=""}
      local filter = {valid=true,tags={mir_browser="sort"}}
      local list = {valid=true,items={},tags={mir_browser_section="research-list"}}
      root.children={filter,list}
      root.mir_browser_tabs={mir_browser_research_content={mir_browser_search=search}}
      local force = {technologies={[technology]=tech},serial="original-shared-research"}
      local player = {index=index,valid=true,connected=true,locale="en",force=force,
        gui={screen={mir_research_browser=root}},list=list,query=""}
      player.request_translation=function(input) requests[index]=flatten(input); return 101 end
      local cache = core.translation_queue.new("en",1)
      core.translation_queue.reset_catalogue(cache,{technology},"separate-GUI-model")
      assert(core.translation_queue.requested(cache,technology,101,0,subjects,false))
      player.cache=cache; players[index]=player; game.connected_players[index]=player
    end
    local function update(player)
      local catalogue = {schema=1,rows={{key=technology,available=true,researched=false,
        queued=false,infinite=false,native_order="",progression=1}}}
      local found = core.query_all(catalogue,{mode=1,status=1,page=1,search=player.query},
        nil,player.cache.values,nil,player.cache.search_values)
      player.list.items = found.count == 1 and {{"","[img=technology/"..technology.."] ",tech.localised_name}} or {}
    end
    local env = {game=game,prototypes=library,core=core,pairs=pairs,ipairs=ipairs,next=next,
      type=type,string=string,defines={events={on_string_translated=17}},
      script={on_event=function(_,handler) event=handler end,on_nth_tick=function(_,handler) tick=handler end},
      remote={call=function(_,method,index,options)
        assert(method == "open")
        local player=players[index]; player.query=options.search
        player.gui.screen.mir_research_browser.mir_browser_tabs.mir_browser_research_content.mir_browser_search.text=options.search
        update(player); return true
      end}}
    local begin=assert(load(native_source,"actual-native-discovery-witness","t",env))()
    local function start() begin(core,adapter,verify,function(force) return force.serial end,function(value) result=value end) end
    local function callback(index,value,id,success)
      event{player_index=index,id=id or 101,translated=success ~= false,result=value or requests[index]}
    end
    local function gui(index)
      local player=players[index]
      assert(core.translation_queue.completed(player.cache,101,requests[index]))
      update(player)
    end
    local function poll() game.tick=game.tick+1; tick() end
    return {start=start,callback=callback,gui=gui,poll=poll,players=players,game=game,
      result=function() return result end,count=function() return count end,
      tick=function() return tick end,event=function() return event end}
  end
  local empty=scenario(0); empty.start()
  check(empty.result().status == "not-exercised-no-connected-player" and empty.result().native_players == 0
    and empty.tick() == nil and empty.event() == nil,
    "no connected player records unexercised scope and never native success")
  local pending=scenario(1); pending.start(); pending.gui(1); pending.poll()
  check(pending.result() == nil, "GUI matches alone cannot finish without the engine callback")
  pending.callback(1,nil,999); pending.poll()
  check(pending.result() == nil, "an unrelated callback ID cannot qualify the witness")
  pending.callback(1); pending.poll(); pending.poll(); pending.poll()
  local passed=pending.result()
  check(passed and passed.status == "passed-native-connected-player-translations-and-GUI"
    and passed.players[1].completed_searches == 3 and passed.players[1].payload_bytes > 1024
    and not passed.physical_input_qualified and not passed.two_client_multiplayer_qualified,
    "all three exact GUI searches plus the callback complete the recorded scope")
  check(pending.tick() == nil and pending.event() == nil,
    "successful witness removes only its own fixture subscriptions")
  local callback_only=scenario(1); callback_only.start(); callback_only.callback(1); callback_only.poll()
  check(callback_only.result() == nil, "translation alone cannot replace installed GUI search results")
  callback_only.game.tick=601
  check(not pcall(callback_only.poll) and callback_only.result() == nil,
    "deadline expiry fails without writing native success")
  local truncated=scenario(1); truncated.start()
  check(not pcall(truncated.callback,1,string.sub(translated,1,1024)) and truncated.result() == nil,
    "the original 1 KiB callback truncation cannot pass the native witness")
  local failed=scenario(1); failed.start()
  check(not pcall(failed.callback,1,nil,nil,false) and failed.result() == nil,
    "failed engine translation is a failure rather than a successful fallback")
  local malformed=scenario(1); malformed.start()
  check(not pcall(malformed.callback,1,string.rep("x",2048)) and malformed.result() == nil,
    "a long payload with missing native separators cannot pass")
  local wrong=scenario(1); wrong.start(); wrong.callback(1); wrong.gui(1)
  wrong.players[1].list.items={{"","[img=technology/unrelated] ","Other"}}; wrong.poll()
  check(wrong.result() == nil, "one unrelated native list result cannot count as the expected technology")
  local changed=scenario(1); changed.start(); changed.callback(1); changed.gui(1)
  changed.players[1].force.serial="different-research"
  check(not pcall(changed.poll) and changed.result() == nil, "shared research mutation blocks native discovery success")
  local replaced=scenario(1); replaced.start(); replaced.callback(1); replaced.gui(1)
  replaced.players[1].gui.screen.mir_research_browser.valid=false
  check(not pcall(replaced.poll) and replaced.result() == nil, "a rebuilt GUI cannot claim widget preservation")
  local disconnected=scenario(1); disconnected.start(); disconnected.players[1].connected=false
  check(not pcall(disconnected.poll) and disconnected.result() == nil,
    "a disconnected player cannot supply native translation acceptance")
  local peers=scenario(2); peers.start(); peers.callback(1); peers.gui(1); peers.gui(2)
  peers.poll(); peers.poll(); peers.poll()
  check(peers.result() == nil, "equal callback IDs in different players remain independent")
  peers.callback(2); peers.poll(); peers.poll(); peers.poll()
  check(peers.result() and peers.result().native_players == 2,
    "completion waits for each selected connected identity")
end
