-- Passive observer for one real personal-view Library interaction.  The
-- governed native actor supplies mouse and keyboard input; this fixture only
-- records resulting public GUI and native state after MIR has handled each
-- event on the following tick.
local FIXTURE = "mir-fixture-library-personal-view-input"
local VERSION = "0.1.5"
local MIR = "more-infinite-research"
local MIR_VERSION = "5.0.21016"
local ROOT = "mir_research_browser"
local PREFIX = "mir_library_"
local SHORTCUT = "mir-research-browser"
local MAX_EVENTS = 32
local MAX_QUEUE = 128
local MAX_SNAPSHOTS = 40
local MAX_INITIAL_READY_TICKS = 1800

local function fail(message)
  error("[MIR personal-view input] " .. message)
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function valid(value)
  return value ~= nil and value.valid == true
end

local function equal(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do
    if not equal(value, right[key]) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy(child) end
  return result
end

local function state()
  if storage.mir_personal_view_input == nil then
    storage.mir_personal_view_input = {
      phase = "await-join",
      events = {setup = 0, shortcut = 0, tab = 0, tab_click = 0, click = 0, text = 0, close = 0},
      event_log = {},
      snapshots = {},
      written = {},
      active_mods_reported = false
    }
  end
  return storage.mir_personal_view_input
end

local function record_event(kind, facts)
  local current = state()
  if #current.event_log >= MAX_EVENTS then fail("too many observed GUI events") end
  facts.kind, facts.tick = kind, game.tick
  current.event_log[#current.event_log + 1] = facts
end

local function active_mods()
  local required = {base = "2.1.24", [MIR] = MIR_VERSION, [FIXTURE] = VERSION}
  local rows, count = {}, 0
  for name, version in pairs(script.active_mods) do
    if type(name) ~= "string" or type(version) ~= "string" or required[name] ~= version then
      fail("exact active-mod selection required")
    end
    count = count + 1
    rows[#rows + 1] = name .. "@" .. version
  end
  if count ~= 3 then fail("exact active-mod selection required") end
  for name, version in pairs(required) do
    if script.active_mods[name] ~= version then fail("exact active-mod selection required") end
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

local function player_for(index)
  if type(index) ~= "number" then return nil end
  local player = game.get_player(index)
  if not valid(player) or player.connected ~= true then return nil end
  return player
end

local function technology_snapshot(technology)
  if not valid(technology) or type(technology.name) ~= "string" or type(technology.level) ~= "number"
    or type(technology.researched) ~= "boolean" or type(technology.enabled) ~= "boolean" then
    fail("research technology unavailable")
  end
  return {name = technology.name, level = technology.level, researched = technology.researched,
    enabled = technology.enabled}
end

local function native_snapshot(player)
  local force = player.force
  if force == nil or force.valid == false then fail("player force unavailable") end
  local queue = force.research_queue
  if type(queue) ~= "table" or #queue > MAX_QUEUE then fail("research queue unavailable or oversized") end
  local rows = {}
  for index, technology in ipairs(queue) do
    rows[index] = technology_snapshot(technology)
  end
  local current = force.current_research
  local bonus = force.worker_robots_storage_bonus
  if not finite(bonus) then fail("worker storage bonus unavailable") end
  local progress = force.research_progress
  if not finite(progress) then fail("research progress unavailable") end
  return {
    force = force.name,
    current = current and technology_snapshot(current) or false,
    progress = progress,
    queue = rows,
    worker_robots_storage_bonus = bonus
  }
end

local function readable_style(style, field)
  if style == nil then fail("style unavailable") end
  local ok, value = pcall(function() return style[field] end)
  if not ok or (value ~= nil and not finite(value)) then fail("style field unavailable") end
  return value
end

local function geometry(player, root)
  local location, style = root.location, root.style
  if type(location) ~= "table" then fail("root geometry unavailable") end
  local row = {
    x = location.x, y = location.y, minimal_width = readable_style(style, "minimal_width"),
    maximal_width = readable_style(style, "maximal_width"),
    minimal_height = readable_style(style, "minimal_height"),
    maximal_height = readable_style(style, "maximal_height")
  }
  if not finite(row.x) or not finite(row.y) then
    fail("root geometry unavailable")
  end
  if not finite(player.display_scale) or player.display_scale <= 0
    or type(player.display_resolution) ~= "table"
    or not finite(player.display_resolution.width) or player.display_resolution.width <= 0
    or not finite(player.display_resolution.height) or player.display_resolution.height <= 0 then
    fail("display geometry unavailable")
  end
  row.display_scale = player.display_scale
  row.display_width = player.display_resolution.width
  row.display_height = player.display_resolution.height
  return row
end

local function library_tree(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  if not valid(root) or root.type ~= "frame" or type(root.get_mod) ~= "function" or root.get_mod() ~= MIR then
    fail("owned Library root absent")
  end
  local tabs = root[PREFIX .. "tabs"]
  if not valid(tabs) or tabs.type ~= "tabbed-pane" or tabs.name ~= PREFIX .. "tabs" then
    fail("Library tab bar unavailable")
  end
  return root, tabs
end

local function research_tree(player)
  local root, tabs = library_tree(player)
  local page = tabs[PREFIX .. "research_page"]
  local filters = valid(page) and page[PREFIX .. "filters"] or nil
  local query = valid(filters) and filters[PREFIX .. "query"] or nil
  if tabs.selected_tab_index ~= 1 or not valid(page) or page.type ~= "scroll-pane" or page.visible ~= true
    or not valid(filters) or not valid(query) or query.type ~= "textfield" or type(query.text) ~= "string" then
    fail("Research personal view unavailable")
  end
  return root, query
end

local function tab_bar_structure(tabs)
  local result = {name = tabs.name, type = tabs.type}
  local style = tabs.style
  for _, field in ipairs({"minimal_width", "maximal_width", "minimal_height", "maximal_height"}) do
    result[field] = readable_style(style, field)
  end
  return result
end

local function record_open_shell(row, player, root, tabs)
  row.geometry = geometry(player, root)
  row.tab_bar = tab_bar_structure(tabs)
  row.tab_bar_index = tabs.index
  if type(row.tab_bar_index) ~= "number" or row.tab_bar_index <= 0 then fail("tab-bar index unavailable") end
  row.tab_index = tabs.selected_tab_index
  local current = state()
  if current.open_geometry == nil then
    current.open_geometry, current.tab_bar, current.tab_bar_index = row.geometry, row.tab_bar, row.tab_bar_index
  elseif not equal(current.open_geometry, row.geometry) then
    fail("root geometry was not retained")
  elseif not equal(current.tab_bar, row.tab_bar) then
    fail("tab-bar identity or geometry was not retained")
  elseif row.stage ~= "reopen" and current.tab_bar_index ~= row.tab_bar_index then
    fail("tab-bar identity changed before close")
  end
end

local function schedule(stage_name, deadline)
  local current = state()
  if current.pending ~= nil then
    if current.pending.stage == "text" and stage_name == "text" then return end
    fail("multiple unsettled GUI events")
  end
  current.pending = {stage = stage_name, tick = game.tick + 1, deadline = deadline}
end

local function before_first_shortcut(current)
  return current.events.shortcut == 0
    and (current.phase == "settling-initial" or current.phase == "await-open")
end

local function mir_gui_element(element)
  if not valid(element) or type(element.name) ~= "string" then return false end
  return element.name == ROOT or string.sub(element.name, 1, #PREFIX) == PREFIX
end

local function record_setup_event(kind, event, include_element)
  local current = state()
  current.events.setup = current.events.setup + 1
  local facts = {player_index = event.player_index, gui_type = event.gui_type}
  if include_element then
    local element = event.element
    facts.element_valid = valid(element)
    facts.element_name = valid(element) and element.name or false
  end
  record_event(kind, facts)
end

local function write_phase(player, row)
  local current = state()
  if helpers == nil or type(helpers.table_to_json) ~= "function" or type(helpers.write_file) ~= "function" then
    fail("phase output helpers unavailable")
  end
  local name = string.format("mir-library-personal-view-input/%02d-%s.json", #current.snapshots, row.stage)
  if current.written[name] then fail("phase output already written") end
  helpers.write_file(name, helpers.table_to_json({
    schema = 1,
    fixture = FIXTURE,
    version = VERSION,
    active_mods = current.active_mods,
    phase = current.phase,
    complete = current.phase == "complete",
    events = current.events,
    event_log = current.event_log,
    snapshot = row,
    snapshots = current.snapshots,
    native_snapshot_unchanged = current.native ~= nil
  }), false, player.index)
  current.written[name] = true
end

local function record_snapshot(stage_name)
  local current = state()
  local player = player_for(current.player_index)
  if player == nil then fail("observed player unavailable") end
  local native = native_snapshot(player)
  if current.native == nil then current.native = native
  elseif not equal(current.native, native) then fail("native research state changed") end
  local row = {stage = stage_name, tick = game.tick, native = native}
  if stage_name == "initial" or stage_name == "closed" then
    local screen = player.gui and player.gui.screen
    local root = screen and screen[ROOT]
    if valid(root) then fail("Library root should be retired") end
    if stage_name == "initial" and player.opened ~= nil then fail("player UI is not usable") end
    if stage_name == "closed" and player.opened ~= nil and player.opened == root then fail("Library root remained opened") end
    if stage_name == "initial" then
      if type(player.controller_type) ~= "number" or player.controller_type == defines.controllers.cutscene then
        fail("player controller is not usable")
      end
      row.controller_type = player.controller_type
    end
  elseif stage_name == "help-tab" then
    local root, tabs = library_tree(player)
    if player.opened ~= root or tabs.selected_tab_index ~= 4 then fail("Help tab was not selected") end
    record_open_shell(row, player, root, tabs)
  else
    local root, query = research_tree(player)
    local tabs = root[PREFIX .. "tabs"]
    if player.opened ~= root then fail("Library root is not opened") end
    row.query = query.text
    record_open_shell(row, player, root, tabs)
    if (stage_name == "open" or stage_name == "research-tab") and row.query ~= "" then
      fail("initial query is not empty")
    end
    if stage_name == "reopen" and row.query ~= "gear" then fail("query was not retained") end
  end
  if #current.snapshots >= MAX_SNAPSHOTS then fail("too many GUI snapshots") end
  current.snapshots[#current.snapshots + 1] = row
  return player, row
end

local function begin_observation(player, origin)
  local current = state()
  if current.phase ~= "await-join" then return false end
  if player == nil then fail("observed player unavailable") end
  record_event(origin, {player_index = player.index})
  current.player_index = player.index
  schedule("initial", game.tick + MAX_INITIAL_READY_TICKS)
  current.phase = "settling-initial"
  return true
end

local function bootstrap_singleplayer_load()
  local current = state()
  if current.phase ~= "await-join" then return end
  if game.is_multiplayer() then return end
  local players = game.connected_players
  if players == nil or #players ~= 1 then return end
  local joined = players[1]
  if not valid(joined) or joined.connected ~= true or type(joined.index) ~= "number" then return end
  local player = player_for(joined.index)
  if player == nil then return end
  begin_observation(player, "singleplayer-load")
end

local function settle(event)
  local current = state()
  bootstrap_singleplayer_load()
  current = state()
  local pending = current.pending
  if pending == nil or event.tick < pending.tick then return end
  current.pending = nil
  local player, row
  if pending.stage == "initial" then
    player = player_for(current.player_index)
    if player == nil then fail("observed player unavailable") end
    if type(player.controller_type) ~= "number" then fail("player controller is not usable") end
    if player.controller_type == defines.controllers.cutscene then
      if type(pending.deadline) ~= "number" or event.tick >= pending.deadline then
        fail("player controller did not leave cutscene")
      end
      current.pending = pending
      return
    end
    if player.opened ~= nil then
      if type(pending.deadline) ~= "number" or event.tick >= pending.deadline then
        fail("player UI did not become usable")
      end
      current.pending = pending
      return
    end
    player, row = record_snapshot("initial")
    current.phase = "await-open"
  elseif pending.stage == "open" then
    player, row = record_snapshot("open")
    current.phase = "await-help-tab"
  elseif pending.stage == "help-tab" then
    player, row = record_snapshot("help-tab")
    current.phase = "await-research-tab"
  elseif pending.stage == "research-tab" then
    player, row = record_snapshot("research-tab")
    current.phase = "await-query-click"
  elseif pending.stage == "query-click" then
    player, row = record_snapshot("query-click")
    current.phase = "await-query-text"
  elseif pending.stage == "text" then
    player, row = record_snapshot("text")
    local latest = current.snapshots[#current.snapshots]
    current.phase = latest.query == "gear" and "await-close" or "await-query-text"
  elseif pending.stage == "closed" then
    player, row = record_snapshot("closed")
    current.phase = "await-reopen"
  elseif pending.stage == "reopen" then
    player, row = record_snapshot("reopen")
    current.phase = "complete"
  else
    fail("unknown deferred stage")
  end
  write_phase(player, row)
end

local function on_join(event)
  local current = state()
  local player = player_for(event and event.player_index)
  if player == nil then fail("joined player unavailable") end
  if current.phase ~= "await-join" then fail("unexpected player join") end
  begin_observation(player, "joined")
end

local function on_shortcut(event)
  local current = state()
  if event == nil or event.prototype_name ~= SHORTCUT or event.player_index ~= current.player_index then return end
  record_event("shortcut", {player_index = event.player_index, prototype_name = event.prototype_name})
  if current.phase == "await-open" then
    current.events.shortcut = current.events.shortcut + 1
    if current.events.shortcut ~= 1 then fail("distinct shortcut events required") end
    schedule("open")
    current.phase = "settling-open"
  elseif current.phase == "await-reopen" then
    current.events.shortcut = current.events.shortcut + 1
    if current.events.shortcut ~= 2 then fail("distinct shortcut events required") end
    schedule("reopen")
    current.phase = "settling-reopen"
  else
    fail("shortcut event out of order")
  end
end

local function on_click(event)
  local current = state()
  if event ~= nil and event.player_index == current.player_index and before_first_shortcut(current)
    and not mir_gui_element(event.element) then
    record_setup_event("setup-click", event, true)
    return
  end
  if event == nil or event.player_index ~= current.player_index then
    fail("query click event out of order")
  end
  if current.phase == "await-help-tab" or current.phase == "settling-help-tab"
    or current.phase == "await-research-tab" or current.phase == "settling-research-tab" then
    local element = event.element
    local name = valid(element) and element.name or false
    local expected = (current.phase == "await-help-tab" or current.phase == "settling-help-tab")
      and PREFIX .. "tab_help" or PREFIX .. "tab_research"
    if name ~= false and name ~= expected then fail("tab click target invalid") end
    record_event("tab-click", {player_index = event.player_index, element_valid = valid(element), element_name = name})
    current.events.tab_click = current.events.tab_click + 1
    return
  end
  if current.phase ~= "await-query-click" then
    fail("query click event out of order")
  end
  local element = event.element
  if not valid(element) or element.name ~= PREFIX .. "query" then fail("query click target invalid") end
  record_event("query-click", {player_index = event.player_index, element_name = element.name})
  current.events.click = current.events.click + 1
  schedule("query-click")
  current.phase = "settling-query-click"
end

local function on_selected_tab_changed(event)
  local current = state()
  if event ~= nil and event.player_index == current.player_index and before_first_shortcut(current)
    and not mir_gui_element(event.element) then
    record_setup_event("setup-tab-selected", event, true)
    return
  end
  if event == nil or event.player_index ~= current.player_index then fail("tab selection event out of order") end
  if current.phase == "await-help-tab" then
    record_event("tab-selected", {player_index = event.player_index})
    current.events.tab = current.events.tab + 1
    schedule("help-tab")
    current.phase = "settling-help-tab"
  elseif current.phase == "await-research-tab" then
    record_event("tab-selected", {player_index = event.player_index})
    current.events.tab = current.events.tab + 1
    if current.events.tab ~= 2 then fail("distinct tab selections required") end
    schedule("research-tab")
    current.phase = "settling-research-tab"
  else
    fail("tab selection event out of order")
  end
end

local function on_text_changed(event)
  local current = state()
  if event ~= nil and event.player_index == current.player_index and before_first_shortcut(current)
    and not mir_gui_element(event.element) then
    record_setup_event("setup-text", event, true)
    return
  end
  if (current.phase ~= "await-query-text" and current.phase ~= "settling-text")
    or event == nil or event.player_index ~= current.player_index then
    fail("query text event out of order")
  end
  local element = event.element
  if valid(element) and element.name ~= PREFIX .. "query" then fail("query text target invalid") end
  record_event("query-text", {player_index = event.player_index, element_valid = valid(element),
    element_name = valid(element) and element.name or false})
  current.events.text = current.events.text + 1
  if current.events.text > MAX_EVENTS then fail("too many query text events") end
  schedule("text")
  current.phase = "settling-text"
end

local function on_closed(event)
  local current = state()
  if event ~= nil and event.player_index == current.player_index and before_first_shortcut(current) then
    -- Base may already have retired its welcome element.  Its close is setup
    -- evidence only; do not inspect that element before MIR is opened.
    record_setup_event("setup-closed", event, false)
    return
  end
  if current.phase ~= "await-close" or event == nil or event.player_index ~= current.player_index then
    fail("close event out of order")
  end
  if event.gui_type ~= defines.gui_type.custom then fail("close GUI type invalid") end
  -- A sibling handler may already have retired event.element.  Do not read it:
  -- the deferred snapshot below verifies the actual owned root retirement.
  record_event("closed", {player_index = event.player_index, gui_type = event.gui_type})
  current.events.close = current.events.close + 1
  if current.events.close ~= 1 then fail("duplicate close event") end
  current.close_gui_type = event.gui_type
  schedule("closed")
  current.phase = "settling-closed"
end

script.on_init(function()
  local current = state()
  if current.initialized then fail("observer initialized twice") end
  current.active_mods = active_mods()
  log("[MIR_ACTIVE_MODS] " .. current.active_mods)
  current.active_mods_reported = true
  current.initialized = true
end)

script.on_event(defines.events.on_player_joined_game, on_join)
script.on_event(defines.events.on_lua_shortcut, on_shortcut)
script.on_event(defines.events.on_gui_click, on_click)
script.on_event(defines.events.on_gui_selected_tab_changed, on_selected_tab_changed)
script.on_event(defines.events.on_gui_text_changed, on_text_changed)
script.on_event(defines.events.on_gui_closed, on_closed)
script.on_event(defines.events.on_tick, settle)

remote.add_interface("mir5-library-personal-view-input", {
  report = function()
    local current = state()
    return copy({
      phase = current.phase,
      complete = current.phase == "complete",
      active_mods = current.active_mods,
      active_mods_reported = current.active_mods_reported,
      events = current.events,
      event_log = current.event_log,
      snapshots = current.snapshots,
      native_snapshot_unchanged = current.native ~= nil,
      close_gui_type = current.close_gui_type
    })
  end
})
