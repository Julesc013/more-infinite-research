-- Passive observer for the real German localized-search path from the
-- accepted fresh R09 state. The governed actor supplies every desktop action;
-- this fixture only records public GUI and native facts on the next tick.
local FIXTURE = "mir-fixture-library-localized-search-native"
local MIR = "more-infinite-research"
local VERSION = script.active_mods[FIXTURE]
local ROOT, PREFIX = "mir_research_browser", "mir_library_"
local SHORTCUT = "mir-research-browser"
local INITIAL_QUERY = "recipe-prod-research_mining_drill-1"
local LOCALIZED_QUERY = "Eisenzahnrad"
local TARGET_ID = "recipe-prod-research_gears-1"
local TARGET_PREFIX = "[img=technology/recipe-prod-research_gears-1] "
-- Keep this exact UTF-8 public caption independent of the test host's source
-- decoder; Factorio's localized list item supplies the same bytes.
local TARGET_CAPTION = "Eisenzahnrad-Produktivit" .. string.char(195, 164) .. "t"
local MAX_EVENTS, MAX_SNAPSHOTS, MAX_TEXT_EVENTS, MAX_READY_TICKS = 48, 10, 32, 1800
local PHASE_PATH = {
  initial = "00-initial", ["setup-closed"] = "01-setup-closed", open = "02-open",
  ["help-tab"] = "03-help-tab", ["research-tab"] = "04-research-tab", ["query-click"] = "05-query-click",
  cleared = "06-cleared", ["localized-query"] = "07-localized-query", closed = "08-closed",
  reopen = "09-reopen"
}

local function fail(message)
  error("[MIR localized Library search] " .. message)
end

local function valid(value)
  return value ~= nil and value.valid == true
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not same(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function exact_active_mods()
  if VERSION ~= "0.1.0" then fail("exact active-mod selection required") end
  local expected = {
    base = "2.1.24", [MIR] = "5.0.21017", [FIXTURE] = "0.1.0",
    ["mir-fixture-mir5-api-alpha"] = "0.1.0", ["mir-fixture-mir5-api-beta"] = "0.1.0",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0"
  }
  local rows, count = {}, 0
  for name, version in pairs(script.active_mods) do
    if type(name) ~= "string" or type(version) ~= "string" or expected[name] ~= version then
      fail("exact active-mod selection required")
    end
    count = count + 1
    rows[#rows + 1] = name .. "@" .. version
  end
  if count ~= 6 then fail("exact active-mod selection required") end
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then fail("exact active-mod selection required") end
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

local function state()
  local current = storage.mir_localized_search_native
  if current == nil then
    current = {
      schema = 1, phase = "await-join", events = {joined = 0, shortcut = 0, tab_click = 0,
        tab_selected = 0, query_click = 0, clear = 0, text = 0, close = 0},
      event_log = {}, snapshots = {}, written = {}, active_mods_reported = false
    }
    storage.mir_localized_search_native = current
  end
  if type(current) ~= "table" or current.schema ~= 1 then fail("observer state differs") end
  return current
end

local function player_for(index)
  if type(index) ~= "number" then return nil end
  local player = game.get_player(index)
  if not valid(player) or player.connected ~= true then return nil end
  return player
end

local function record_event(kind, facts)
  local current = state()
  if #current.event_log >= MAX_EVENTS then fail("too many observed GUI events") end
  facts.kind, facts.tick = kind, game.tick
  current.event_log[#current.event_log + 1] = facts
end

local function schedule(stage_name, deadline)
  local current = state()
  if current.pending ~= nil then fail("multiple unsettled GUI events") end
  current.pending = {stage = stage_name, tick = game.tick + 1, deadline = deadline}
end

local function begin_tab_pair(stage_name, tab_index, tab_name, next_phase)
  local current = state()
  if current.tab_pair ~= nil then fail("prior tab pair remains unsettled") end
  current.tab_pair = {stage = stage_name, index = tab_index, name = tab_name, clicked = false, selected = false}
  current.phase = next_phase
end

local function settle_tab_pair()
  local current, pair = state(), state().tab_pair
  if pair == nil then fail("tab pair differs") end
  if pair.clicked and pair.selected then
    schedule(pair.stage)
    current.tab_pair = nil
    current.phase = "settling-" .. pair.stage
  end
end

local function technology_row(technology)
  if not valid(technology) or type(technology.name) ~= "string" or type(technology.level) ~= "number"
      or type(technology.researched) ~= "boolean" or type(technology.enabled) ~= "boolean" then
    fail("fresh native technology unavailable")
  end
  return {name = technology.name, level = technology.level, researched = technology.researched,
    enabled = technology.enabled}
end

local function native_frame(player)
  local force = player.force
  local gear = force and force.technologies and force.technologies[TARGET_ID] or nil
  local recipe = force and force.recipes and force.recipes["iron-gear-wheel"] or nil
  local queue = force and force.research_queue or nil
  if not valid(force) or type(queue) ~= "table" or #queue ~= 0 or force.current_research ~= nil
      or not finite(force.research_progress) or force.research_progress ~= 0
      or not finite(force.worker_robots_storage_bonus) or recipe == nil
      or not finite(recipe.productivity_bonus) then
    fail("fresh native frame differs")
  end
  local row = technology_row(gear)
  if row.name ~= TARGET_ID or row.level ~= 3 or row.researched ~= false or row.enabled ~= true
      or math.abs(recipe.productivity_bonus - 0.2) > 0.000001 then
    fail("fresh earned provider frame differs")
  end
  return {force = force.name, gear = row, gear_productivity = recipe.productivity_bonus,
    current = false, progress = force.research_progress, queue = {},
    worker_robots_storage_bonus = force.worker_robots_storage_bonus}
end

local function owned(element, name, parent, kind)
  if not valid(element) or element.name ~= name or element.parent ~= parent
      or (kind ~= nil and element.type ~= kind) or type(element.get_mod) ~= "function"
      or element.get_mod() ~= MIR then
    fail("owned localized-search GUI path differs")
  end
  return element
end

local function readable_style(style, field)
  if style == nil then fail("style unavailable") end
  local ok, value = pcall(function() return style[field] end)
  if not ok or (value ~= nil and not finite(value)) then fail("style field unavailable") end
  return value
end

local function geometry(player, root)
  local location, style = root.location, root.style
  if type(location) ~= "table" or not finite(location.x) or not finite(location.y)
      or not finite(player.display_scale) or player.display_scale <= 0
      or type(player.display_resolution) ~= "table" then
    fail("root geometry unavailable")
  end
  return {x = location.x, y = location.y, minimal_width = readable_style(style, "minimal_width"),
    maximal_width = readable_style(style, "maximal_width"),
    minimal_height = readable_style(style, "minimal_height"),
    maximal_height = readable_style(style, "maximal_height"), display_scale = player.display_scale,
    display_width = player.display_resolution.width, display_height = player.display_resolution.height}
end

local function root_tree(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  if not valid(root) or root.type ~= "frame" or type(root.get_mod) ~= "function" or root.get_mod() ~= MIR
      or player.opened ~= root then
    fail("owned localized-search root differs")
  end
  local tabs = owned(root[PREFIX .. "tabs"], PREFIX .. "tabs", root, "tabbed-pane")
  return root, tabs
end

local function research_tree(player)
  local root, tabs = root_tree(player)
  local page = owned(tabs[PREFIX .. "research_page"], PREFIX .. "research_page", tabs, "scroll-pane")
  local filters = owned(page[PREFIX .. "filters"], PREFIX .. "filters", page, "flow")
  local query = owned(filters[PREFIX .. "query"], PREFIX .. "query", filters, "textfield")
  if tabs.selected_tab_index ~= 1 or page.visible ~= true or type(query.text) ~= "string" then
    fail("Research localized-search view unavailable")
  end
  return root, tabs, page, query
end

local function tab_structure(tabs)
  local style = tabs.style
  return {name = tabs.name, type = tabs.type, minimal_width = readable_style(style, "minimal_width"),
    maximal_width = readable_style(style, "maximal_width"), minimal_height = readable_style(style, "minimal_height"),
    maximal_height = readable_style(style, "maximal_height")}
end

local function record_shell(row, player, root, tabs, live_identity)
  row.geometry, row.tab_bar, row.tab_bar_index = geometry(player, root), tab_structure(tabs), tabs.index
  if type(row.tab_bar_index) ~= "number" or row.tab_bar_index <= 0 then fail("tab-bar index unavailable") end
  local current = state()
  if current.geometry == nil then
    current.geometry, current.tab_bar = row.geometry, row.tab_bar
  elseif not same(current.geometry, row.geometry) then
    fail("root geometry was not retained")
  elseif not same(current.tab_bar, row.tab_bar) then
    fail("tab-bar structure was not retained")
  end
  if live_identity then
    if current.live_tab_bar_index == nil then current.live_tab_bar_index = row.tab_bar_index
    elseif current.live_tab_bar_index ~= row.tab_bar_index then fail("tab-bar identity changed before close") end
  end
end

local function result_row(page)
  local content = owned(page[PREFIX .. "research_content"], PREFIX .. "research_content", page)
  local list_pane = owned(content[PREFIX .. "list_pane"], PREFIX .. "list_pane", content, "flow")
  local results = owned(list_pane[PREFIX .. "results"], PREFIX .. "results", list_pane, "list-box")
  local items = results.items
  if type(items) ~= "table" or #items ~= 1 then fail("localized result count differs") end
  local item = items[1]
  if type(item) ~= "table" or #item ~= 3 or item[1] ~= "" or item[2] ~= TARGET_PREFIX
      or item[3] ~= TARGET_CAPTION then
    fail("localized result differs")
  end
  return {count = #items, icon = item[2], caption = item[3]}
end

local function write_phase(player, row)
  local current = state()
  local path = PHASE_PATH[row.stage]
  if path == nil or current.written[path] then fail("phase output differs") end
  if helpers == nil or type(helpers.table_to_json) ~= "function" or type(helpers.write_file) ~= "function" then
    fail("phase output helpers unavailable")
  end
  helpers.write_file("mir-library-localized-search-native/" .. path .. ".json", helpers.table_to_json({
    schema = 1, fixture = FIXTURE, version = VERSION, active_mods = current.active_mods,
    player = {index = player.index, name = player.name, locale = player.locale},
    phase = row.stage, next_phase = current.phase, complete = current.phase == "complete", events = current.events,
    event_log = current.event_log, snapshot = row, snapshots = current.snapshots,
    native_snapshot_unchanged = current.native ~= nil
  }), false, player.index)
  current.written[path] = true
end

local function record_snapshot(stage_name)
  local current = state()
  local player = player_for(current.player_index)
  if player == nil then fail("localized-search player unavailable") end
  local native = native_frame(player)
  if current.native == nil then current.native = native
  elseif not same(current.native, native) then fail("native fresh frame changed") end
  local row = {stage = stage_name, tick = game.tick, native = native}
  if stage_name == "setup-closed" or stage_name == "closed" then
    local screen = player.gui and player.gui.screen
    if screen and valid(screen[ROOT]) then fail("Library root should be retired") end
    if player.opened ~= nil then fail("Library close did not retire public root") end
  elseif stage_name == "help-tab" then
    local root, tabs = root_tree(player)
    if tabs.selected_tab_index ~= 4 then fail("Help tab was not selected") end
    record_shell(row, player, root, tabs, true)
  else
    local root, tabs, page, query = research_tree(player)
    -- The initial Library shell predates the real setup-close/reopen sequence.
    -- Its native GUI index may therefore differ from the new shell.  Identity is
    -- retained only within the real open -> Help -> Research -> query sequence.
    local live = stage_name ~= "initial" and stage_name ~= "reopen"
    record_shell(row, player, root, tabs, live)
    row.query = query.text
    if stage_name == "initial" or stage_name == "open" or stage_name == "research-tab"
        or stage_name == "query-click" then
      if row.query ~= INITIAL_QUERY then fail("pre-existing query differs") end
    elseif stage_name == "cleared" then
      if row.query ~= "" then fail("query did not clear") end
    elseif stage_name == "localized-query" or stage_name == "reopen" then
      if row.query ~= LOCALIZED_QUERY then fail("localized query was not retained") end
    end
    if stage_name == "localized-query" or stage_name == "reopen" then row.result = result_row(page) end
  end
  if #current.snapshots >= MAX_SNAPSHOTS then fail("too many GUI snapshots") end
  current.snapshots[#current.snapshots + 1] = row
  return player, row
end

local function settle(event)
  local current, pending = state(), state().pending
  if pending == nil or event.tick < pending.tick then return end
  local player = player_for(current.player_index)
  if player == nil then fail("localized-search player unavailable") end
  if pending.stage == "initial" and player.locale ~= "de" then
    if event.tick >= pending.deadline then fail("German locale did not become ready") end
    return
  end
  current.pending = nil
  local written_player, row = record_snapshot(pending.stage)
  if pending.stage == "initial" then current.phase = "await-setup-close"
  elseif pending.stage == "setup-closed" then current.phase = "await-open"
  elseif pending.stage == "open" then begin_tab_pair("help-tab", 4, PREFIX .. "tab_help", "await-help-click")
  elseif pending.stage == "help-tab" then begin_tab_pair("research-tab", 1, PREFIX .. "tab_research", "await-research-click")
  elseif pending.stage == "research-tab" then current.phase = "await-query-click"
  elseif pending.stage == "query-click" then current.phase = "await-clear"
  elseif pending.stage == "cleared" then current.phase = "await-localized-query"
  elseif pending.stage == "localized-query" then current.phase = "await-close"
  elseif pending.stage == "closed" then current.phase = "await-reopen"
  elseif pending.stage == "reopen" then current.phase = "complete"
  else fail("unknown deferred stage") end
  write_phase(written_player, row)
end

local function on_join(event)
  local current = state()
  local player = player_for(event and event.player_index)
  if current.phase ~= "await-join" or player == nil or player.name ~= "MIR5Deutsch" then
    fail("localized-search client role differs")
  end
  current.player_index, current.events.joined = player.index, current.events.joined + 1
  record_event("joined", {player_index = player.index, name = player.name, locale = player.locale})
  schedule("initial", game.tick + MAX_READY_TICKS)
  current.phase = "settling-initial"
end

local function on_shortcut(event)
  local current = state()
  if event == nil or event.player_index ~= current.player_index or event.prototype_name ~= SHORTCUT then return end
  if current.phase ~= "await-open" and current.phase ~= "await-reopen" then fail("shortcut event out of order") end
  current.events.shortcut = current.events.shortcut + 1
  record_event("shortcut", {player_index = event.player_index, prototype_name = event.prototype_name})
  schedule(current.phase == "await-open" and "open" or "reopen")
  current.phase = current.phase == "await-open" and "settling-open" or "settling-reopen"
end

local function on_click(event)
  local current = state()
  if event == nil or event.player_index ~= current.player_index then fail("localized-search click role differs") end
  local player = player_for(current.player_index)
  if player == nil then fail("localized-search player unavailable") end
  local root, tabs = root_tree(player)
  local query = nil
  if current.phase == "await-query-click" then
    local _, _, _, observed_query = research_tree(player)
    query = observed_query
  end
  local element = event.element
  if current.phase == "await-help-click" or current.phase == "await-research-click" then
    local pair = current.tab_pair
    if pair == nil or pair.clicked or not valid(element) or element ~= tabs[pair.name] then
      fail("tab click differs")
    end
    current.events.tab_click = current.events.tab_click + 1
    pair.clicked = true
    record_event("tab-click", {player_index = event.player_index, stage = pair.stage, element = element.name})
    settle_tab_pair()
  elseif current.phase == "await-query-click" then
    if element ~= query then fail("query click differs") end
    current.events.query_click = current.events.query_click + 1
    record_event("query-click", {player_index = event.player_index, element = element.name})
    schedule("query-click")
    current.phase = "settling-query-click"
  else
    fail("localized-search click out of order")
  end
end

local function on_tab_selected(event)
  local current = state()
  if event == nil or event.player_index ~= current.player_index then fail("tab selection role differs") end
  local player = player_for(current.player_index)
  if player == nil then fail("localized-search player unavailable") end
  local _, tabs = root_tree(player)
  if event.element ~= tabs then fail("tab selection differs") end
  if current.phase == "await-help-click" or current.phase == "await-research-click" then
    local pair = current.tab_pair
    if pair == nil or pair.selected or tabs.selected_tab_index ~= pair.index then
      fail("tab selection differs")
    end
    current.events.tab_selected = current.events.tab_selected + 1
    pair.selected = true
    record_event("tab-selected", {player_index = event.player_index, stage = pair.stage, tab_index = tabs.selected_tab_index})
    settle_tab_pair()
  else
    fail("tab selection out of order")
  end
end

local function query_prefix(value)
  return type(value) == "string" and string.sub(LOCALIZED_QUERY, 1, #value) == value
end

local function on_text(event)
  local current = state()
  if event == nil or event.player_index ~= current.player_index then fail("localized-search text role differs") end
  local player = player_for(current.player_index)
  local _, _, _, query = research_tree(player)
  if event.element ~= query then fail("localized-search text element differs") end
  local text = query.text
  if current.phase == "await-clear" then
    if text ~= "" then fail("query did not clear") end
    current.events.clear = current.events.clear + 1
    record_event("clear", {player_index = event.player_index, text = text})
    schedule("cleared")
    current.phase = "settling-cleared"
  elseif current.phase == "await-localized-query" then
    if not query_prefix(text) then fail("localized query text differs") end
    current.events.text = current.events.text + 1
    if current.events.text > MAX_TEXT_EVENTS then fail("too many localized text events") end
    record_event("localized-text", {player_index = event.player_index, text = text})
    if text == LOCALIZED_QUERY then
      schedule("localized-query")
      current.phase = "settling-localized-query"
    end
  elseif current.phase == "settling-localized-query" and text == LOCALIZED_QUERY then
    current.events.text = current.events.text + 1
    if current.events.text > MAX_TEXT_EVENTS then fail("too many localized text events") end
    record_event("localized-text", {player_index = event.player_index, text = text})
  else
    fail("localized-search text out of order")
  end
end

local function on_closed(event)
  local current = state()
  if event == nil or event.player_index ~= current.player_index then fail("localized-search close role differs") end
  if current.phase ~= "await-setup-close" and current.phase ~= "await-close" then
    fail("localized-search close out of order")
  end
  current.events.close = current.events.close + 1
  record_event("closed", {player_index = event.player_index, gui_type = event.gui_type,
    element_valid = valid(event.element)})
  schedule(current.phase == "await-setup-close" and "setup-closed" or "closed")
  current.phase = current.phase == "await-setup-close" and "settling-setup-closed" or "settling-closed"
end

script.on_init(function()
  local active = exact_active_mods()
  local current = state()
  current.active_mods = active
  if not current.active_mods_reported then
    log("[MIR_ACTIVE_MODS] " .. active)
    current.active_mods_reported = true
  end
end)
script.on_event(defines.events.on_player_joined_game, on_join)
script.on_event(defines.events.on_lua_shortcut, on_shortcut)
script.on_event(defines.events.on_gui_click, on_click)
script.on_event(defines.events.on_gui_selected_tab_changed, on_tab_selected)
script.on_event(defines.events.on_gui_text_changed, on_text)
script.on_event(defines.events.on_gui_closed, on_closed)
script.on_event(defines.events.on_tick, settle)
remote.add_interface("mir5-library-localized-search-native", {
  report = function() return state() end
})
