-- Selected native witness, consumed by the existing browser harness. It waits
-- for real engine translation callbacks and the installed MIR GUI results.
-- A headless map cannot qualify these cases merely by executing the Lua model.
return function(core, adapter, check, snapshot, finish)
  local technology = "mir-browser-discovery-native"
  local searches = {"préparation témoin", "matière témoin ultime", "fluide témoin"}
  local deadline, records = game.tick + 600, {}
  local function find(element, tag, value)
    if not (element and element.valid) then return nil end
    if element.tags and element.tags[tag] == value then return element end
    for _, child in pairs(element.children or {}) do
      local found = find(child, tag, value)
      if found then return found end
    end
  end
  local function open(record)
    local player = record.player
    check(remote.call("more-infinite-research-browser", "open", player.index, {
      tab="research",family="all",mode=1,status=1,sort="progression",
      search=searches[record.phase],selected=technology
    }), "native localized discovery opens for its connected player")
    local root = player.gui.screen.mir_research_browser
    local search = root.mir_browser_tabs.mir_browser_research_content.mir_browser_search
    if record.root then
      check(record.root.valid and record.root == root and record.search.valid
        and record.search == search and record.filter.valid
        and record.filter == find(root,"mir_browser","sort"),
        "native localized searches preserve the root, search and filter objects")
    else
      record.root, record.search, record.filter = root, search, find(root,"mir_browser","sort")
      check(record.filter ~= nil, "native discovery owns an existing sort control")
    end
    check(search.text == searches[record.phase], "native localized search preserves its text")
  end
  for _, player in pairs(game.connected_players) do
    check(player.valid and player.connected, "native translation witness requires a connected player")
    local tech = player.force.technologies[technology]
    check(tech ~= nil, "native discovery technology is present in the actual force")
    local payload, subjects, limited = adapter.translation_request(tech, prototypes, 128)
    check(subjects == 34 and not limited, "native recipe exposes all item and fluid discovery subjects")
    local cache = core.translation_queue.new(player.locale, 1)
    core.translation_queue.reset_catalogue(cache, {technology}, "native-discovery-witness")
    local id = player.request_translation(payload)
    check(core.translation_queue.requested(cache, technology, id, game.tick, subjects, limited),
      "engine accepts the composed native translation request")
    local record = {player=player,id=id,cache=cache,phase=1,before=snapshot(player.force),started=game.tick}
    records[player.index] = record
    open(record)
  end
  if next(records) == nil then
    finish({status="not-exercised-no-connected-player",players={},native_players=0})
    return
  end
  script.on_event(defines.events.on_string_translated, function(event)
    local record = records[event.player_index]
    if not record or event.id ~= record.id then return end
    check(not record.translated, "native witness consumes its callback once")
    check(event.translated and type(event.result) == "string" and #event.result > 1024
      and #event.result <= core.translation_queue.discovery_text_limit,
      "real engine callback retains the composed payload beyond 1 KiB")
    check(core.translation_queue.completed(record.cache, event.id, event.result)
      and not record.cache.discovery_limited,
      "real engine LocalisedString separators decode without a limited fallback")
    local index = record.cache.search_values[technology]
    for _, term in ipairs(searches) do
      check(type(index) == "string" and string.find(index, term, 1, true) ~= nil,
        "engine callback contains the localized recipe/item/fluid term: " .. term)
    end
    record.translated, record.payload_bytes = true, #event.result
  end)
  script.on_nth_tick(1, function()
    check(game.tick <= deadline, "native localized discovery completes within its bounded tick window")
    local complete, observations = true, {}
    for index, record in pairs(records) do
      local player = record.player
      check(player.valid and player.connected, "native discovery player stays connected")
      check(record.root.valid and player.gui.screen.mir_research_browser == record.root
        and record.search.valid and record.filter.valid,
        "native asynchronous discovery retains its original GUI objects")
      check(snapshot(player.force) == record.before, "native discovery preserves shared research and queue state")
      if record.phase <= #searches then
        local list = find(record.root, "mir_browser_section", "research-list")
        local item = list and list.items[1]
        if record.translated and list and #list.items == 1 and type(item) == "table"
            and item[2] == "[img=technology/" .. technology .. "] " then
          check(record.search.valid and record.search.text == searches[record.phase],
            "installed MIR discovers the exact native technology through its localized subject")
          record.phase = record.phase + 1
          if record.phase <= #searches then open(record) end
        end
      end
      if record.phase <= #searches then complete = false end
      observations[#observations + 1] = {player_index=index,locale=player.locale,
        payload_bytes=record.payload_bytes,completed_searches=record.phase-1,
        elapsed_ticks=game.tick-record.started,technology=technology}
    end
    if complete then
      script.on_event(defines.events.on_string_translated, nil)
      script.on_nth_tick(1, nil)
      finish({status="passed-native-connected-player-translations-and-GUI",players=observations,
        native_players=#observations,searches=searches,physical_input_qualified=false,
        two_client_multiplayer_qualified=false})
    end
  end)
end
