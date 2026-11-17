-- Passive observer for six real Library export clicks in the exact fresh
-- current17 two-client case. The governed caller supplies the desktop input
-- and reads the role-local export files; this observer only records public
-- GUI/native facts on the tick after MIR handles each click.
local FIXTURE = "mir-fixture-library-fresh-export-input"
local MIR = "more-infinite-research"
local VERSION = script.active_mods[FIXTURE]
local ROOT, PREFIX = "mir_research_browser", "mir_library_"
local MAX_EVENTS, MAX_PHASES, MAX_TEXT = 24, 7, 65536
local SETTINGS_FILE = "more-infinite-research/settings/mir-settings-profile.txt"
local DIAGNOSTICS_FILE = "more-infinite-research/mir.log"

local ACTIONS = {
  {name = "en-full", role = "en", kind = "full", tab = 3},
  {name = "en-compact", role = "en", kind = "compact", tab = 3},
  {name = "en-diagnostics", role = "en", kind = "diagnostics", tab = 4},
  {name = "de-full", role = "de", kind = "full", tab = 3},
  {name = "de-compact", role = "de", kind = "compact", tab = 3},
  {name = "de-diagnostics", role = "de", kind = "diagnostics", tab = 4}
}

local function fail(message)
  error("[MIR fresh Library export input] " .. message)
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

local function require_active_mods()
  if VERSION ~= "0.1.0" then fail("exact active-mod selection required") end
  local required = {
    base = "2.1.24",
    [MIR] = "5.0.21017",
    [FIXTURE] = "0.1.0",
    ["mir-fixture-mir5-active-mods-observer"] = "0.1.0",
    ["mir-fixture-mir5-api-alpha"] = "0.1.0",
    ["mir-fixture-mir5-api-beta"] = "0.1.0"
  }
  local rows, count = {}, 0
  for name, version in pairs(script.active_mods) do
    if type(name) ~= "string" or type(version) ~= "string" or required[name] ~= version then
      fail("exact active-mod selection required")
    end
    count = count + 1
    rows[#rows + 1] = name .. "@" .. version
  end
  if count ~= 6 then fail("exact active-mod selection required") end
  for name, version in pairs(required) do
    if script.active_mods[name] ~= version then fail("exact active-mod selection required") end
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

local function state()
  local current = storage.mir_fresh_export_input
  if type(current) ~= "table" or current.schema ~= 1 or current.case ~= "fresh-export-input" then
    fail("observer state differs")
  end
  return current
end

local function role_for(player)
  if not valid(player) then fail("export client unavailable") end
  if player.name == "MIR5English" and player.locale == "en" then return "en" end
  if player.name == "MIR5Deutsch" and player.locale == "de" then return "de" end
  fail("export client role differs")
end

local function player_for(index)
  if type(index) ~= "number" then return nil end
  local player = game.get_player(index)
  if not valid(player) or player.connected ~= true then return nil end
  return player
end

local function pair()
  local current = state()
  local en, de = player_for(current.roles.en), player_for(current.roles.de)
  if en == nil or de == nil or role_for(en) ~= "en" or role_for(de) ~= "de" or en == de or en.force ~= de.force then
    fail("exact export client pair differs")
  end
  local count = 0
  for _ in pairs(game.connected_players) do count = count + 1 end
  if count ~= 2 then fail("exactly two connected export clients required") end
  return en, de
end

local function technology_row(value)
  if value == nil or type(value.name) ~= "string" or type(value.level) ~= "number"
      or type(value.researched) ~= "boolean" or type(value.enabled) ~= "boolean" then
    fail("fresh native technology unavailable")
  end
  return {name = value.name, level = value.level, researched = value.researched, enabled = value.enabled}
end

local function fresh_frame()
  local en, de = pair()
  local force = en.force
  if force == nil or force.valid == false or force.name ~= "player" then fail("fresh native force differs") end
  local gear = force.technologies and force.technologies["recipe-prod-research_gears-1"] or nil
  local recipe = force.recipes and force.recipes["iron-gear-wheel"] or nil
  local queue = force.research_queue
  if gear == nil or recipe == nil or type(queue) ~= "table" or #queue ~= 0
      or force.current_research ~= nil or not finite(force.research_progress)
      or force.research_progress ~= 0 or not finite(force.worker_robots_storage_bonus)
      or not finite(recipe.productivity_bonus) then
    fail("fresh native frame differs")
  end
  local row = technology_row(gear)
  if row.name ~= "recipe-prod-research_gears-1" or row.level ~= 3 or row.researched ~= true
      or row.enabled ~= true or math.abs(recipe.productivity_bonus - 0.2) > 0.000001 then
    fail("fresh earned provider frame differs")
  end
  return {
    force = force.name,
    roles = {en = en.index, de = de.index},
    gear = row,
    gear_productivity = recipe.productivity_bonus,
    current = false,
    progress = force.research_progress,
    queue = {},
    worker_robots_storage_bonus = force.worker_robots_storage_bonus
  }
end

local function owned(element, name, parent, kind)
  if not valid(element) or element.name ~= name or element.parent ~= parent
      or (kind ~= nil and element.type ~= kind) or type(element.get_mod) ~= "function"
      or element.get_mod() ~= MIR then
    fail("owned export GUI path differs")
  end
  return element
end

local function root_for(player)
  local screen = player.gui and player.gui.screen
  local root = screen and screen[ROOT]
  if not valid(root) or root.type ~= "frame" or type(root.get_mod) ~= "function" or root.get_mod() ~= MIR
      or type(root.tags) ~= "table" or root.tags["more-infinite-research.library-root.v1"] ~= true
      or player.opened ~= root then
    fail("owned Library export root differs")
  end
  local tabs = owned(root[PREFIX .. "tabs"], PREFIX .. "tabs", root, "tabbed-pane")
  return root, tabs
end

local function expected_button(kind)
  if kind == "full" then return PREFIX .. "export_settings" end
  if kind == "compact" then return PREFIX .. "export_compact" end
  return PREFIX .. "export_diagnostics"
end

local function export_target(player, action)
  local root, tabs = root_for(player)
  if tabs.selected_tab_index ~= action.tab then fail("export tab differs") end
  if action.kind == "diagnostics" then
    local content = owned(tabs[PREFIX .. "help_content"], PREFIX .. "help_content", tabs)
    local panes = owned(content[PREFIX .. "help_panes"], PREFIX .. "help_panes", content)
    local panel = owned(panes[PREFIX .. "report_panel"], PREFIX .. "report_panel", panes)
    return owned(panel[PREFIX .. "export_diagnostics"], expected_button(action.kind), panel, "button"), panel
  end
  local content = owned(tabs[PREFIX .. "settings_content"], PREFIX .. "settings_content", tabs)
  local toolbar = owned(content[PREFIX .. "settings_toolbar"], PREFIX .. "settings_toolbar", content, "table")
  return owned(toolbar[expected_button(action.kind)], expected_button(action.kind), toolbar, "button"), content
end

local function assert_click_path(player, element, action)
  local expected, parent = export_target(player, action)
  if element ~= expected then fail("owned export GUI path differs") end
  return expected, parent
end

local function text_box(parent, name, message)
  local box = owned(parent[name], name, parent, "text-box")
  if box.read_only ~= true or type(box.text) ~= "string" or #box.text == 0 or #box.text > MAX_TEXT then fail(message) end
  return box.text
end

local function snapshot_after_click(action)
  local current = state()
  local en, de = pair()
  local player = action.role == "en" and en or de
  local frame = fresh_frame()
  if not same(current.fresh_frame, frame) then fail("fresh native frame changed") end
  local _, parent = export_target(player, action)
  local profile = text_box(parent, PREFIX .. "export_profile", "MIRSET1 preview differs")
  if profile:sub(1, 8) ~= "MIRSET1:" then fail("MIRSET1 preview differs") end
  local files = {settings_profile = {path = SETTINGS_FILE, bytes = profile .. "\n"}}
  local snapshot = {action = action.name, role = action.role, kind = action.kind, frame = frame,
    preview = profile, files = files}
  if action.kind == "diagnostics" then
    local report = text_box(parent, PREFIX .. "report_preview", "diagnostic preview differs")
    if report:sub(1, #"MIR diagnostic report") ~= "MIR diagnostic report" then fail("diagnostic preview differs") end
    files.diagnostics = {path = DIAGNOSTICS_FILE, bytes = report}
    snapshot.diagnostic_preview = report
  end
  return player, snapshot
end

local function write_phase(player, name, row)
  local current = state()
  if helpers == nil or type(helpers.table_to_json) ~= "function" or type(helpers.write_file) ~= "function" then
    fail("phase output helpers unavailable")
  end
  local path = "mir-library-fresh-export-input/" .. name
  if current.written[path] or current.phase_count >= MAX_PHASES then fail("phase output bound exceeded") end
  helpers.write_file(path, helpers.table_to_json({
    schema = 1,
    fixture = FIXTURE,
    version = VERSION,
    active_mods = current.active_mods,
    phase = current.phase,
    complete = current.phase == "completed",
    actions = current.actions,
    click = current.click,
    fresh_frame = current.fresh_frame,
    native_fresh_frame_unchanged = true,
    snapshot = row
  }), false, player.index)
  current.written[path] = true
  current.phase_count = current.phase_count + 1
end

local function settle(event)
  local current = state()
  local pending = current.pending
  if pending == nil or event.tick < pending.tick then return end
  current.pending = nil
  if pending.kind == "baseline" then
    current.fresh_frame = fresh_frame()
    local en = player_for(current.roles.en)
    current.phase = "ready"
    write_phase(en, "00-baseline.json", {kind = "baseline", frame = current.fresh_frame})
    return
  end
  local action = ACTIONS[current.cursor]
  if action == nil or pending.action ~= action.name then fail("deferred export action differs") end
  local player, row = snapshot_after_click(action)
  current.actions[#current.actions + 1] = action.name
  current.cursor = current.cursor + 1
  current.phase = current.cursor > #ACTIONS and "completed" or "ready"
  write_phase(player, string.format("%02d-%s.json", #current.actions, action.name), row)
end

local function on_join(event)
  local current = state()
  if event == nil or current.phase ~= "await-roles" then fail("unexpected export client join") end
  local player = player_for(event.player_index)
  local role = role_for(player)
  if current.roles[role] ~= nil then fail("duplicate export client role") end
  current.roles[role] = player.index
  if current.roles.en ~= nil and current.roles.de ~= nil then
    pair()
    current.pending = {kind = "baseline", tick = game.tick + 1}
    current.phase = "settling-baseline"
  end
end

local function on_click(event)
  local element = event and event.element
  if not valid(element) or type(element.name) ~= "string" then return end
  local current = state()
  local button_kind = element.name == PREFIX .. "export_settings" and "full"
    or element.name == PREFIX .. "export_compact" and "compact"
    or element.name == PREFIX .. "export_diagnostics" and "diagnostics" or nil
  -- The governed actor may select a Library tab before an export. Only the
  -- six exact export controls are this observer's input protocol.
  if button_kind == nil then return end
  if current.phase ~= "ready" then fail("export click phase differs") end
  local action = ACTIONS[current.cursor]
  if action == nil or action.kind ~= button_kind then fail("export action differs") end
  local player = player_for(event.player_index)
  if player == nil or role_for(player) ~= action.role then fail("export client role differs") end
  assert_click_path(player, element, action)
  if #current.actions >= #ACTIONS or #current.actions >= MAX_EVENTS then fail("export event bound exceeded") end
  current.click = {action = action.name, role = action.role, player_index = player.index,
    element_name = element.name, tick = game.tick}
  current.pending = {kind = "export", action = action.name, tick = game.tick + 1}
  current.phase = "settling-export"
end

script.on_init(function()
  local active_mods = require_active_mods()
  if storage.mir_fresh_export_input ~= nil then fail("observer state already exists") end
  storage.mir_fresh_export_input = {
    schema = 1,
    case = "fresh-export-input",
    active_mods = active_mods,
    phase = "await-roles",
    roles = {},
    cursor = 1,
    actions = {},
    written = {},
    phase_count = 0
  }
end)

script.on_event(defines.events.on_player_joined_game, on_join)
script.on_event(defines.events.on_gui_click, on_click)
script.on_event(defines.events.on_tick, settle)
