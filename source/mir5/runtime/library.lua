-- Private, first vertical slice of the MIR Research Library.
--
-- The catalogue/model modules own research facts. This module owns only a
-- player's small view preference and GUI construction. Control.lua must route
-- its callbacks explicitly; this file never registers handlers or creates a
-- recurring subscription by itself.
local catalogue = require("research.catalogue")
local library_model = require("presentation.library_model")

local M = {}

local STORAGE_KEY = "mir_library"
local SCHEMA = 1
local ROOT = "mir_research_browser"
local PREFIX = "mir_library_"
local SHORTCUT = "mir-research-browser"
local MAX_QUERY = 160
local LEGACY_NAMESPACE = "mir"
local LEGACY_BROWSER_KEY = "research_browser"
local LEGACY_ROOT_MARKER = "mir_browser_tabs"
local LEGACY_SNAPSHOT_VERSION = 1
local LEGACY_SNAPSHOT_MAX_DEPTH = 8
local LEGACY_SNAPSHOT_MAX_ENTRIES = 512
local LEGACY_SNAPSHOT_MAX_STRING = 4096
local cap_provider = nil

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function player_for(index)
  if type(index) ~= "number" or not game then return nil end
  local ok, player = pcall(function()
    if type(game.get_player) == "function" then return game.get_player(index) end
    return game.players and game.players[index] or nil
  end)
  return ok and valid(player) and player or nil
end

local function existing_state()
  local value = storage[STORAGE_KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= SCHEMA or type(value.players) ~= "table" then
    error("MIR unsupported Library storage schema", 2)
  end
  return value
end

local function ensure_state()
  local value = existing_state()
  if value then return value end
  value = {schema = SCHEMA, players = {}}
  storage[STORAGE_KEY] = value
  return value
end

local function text(value)
  if type(value) ~= "string" then return "" end
  if #value > MAX_QUERY then return string.sub(value, 1, MAX_QUERY) end
  return value
end

local function technology_id(value)
  if type(value) ~= "string" or value == "" or #value > MAX_QUERY then return nil end
  return value
end

local function location(value)
  if type(value) ~= "table" then return nil end
  if not finite_number(value.x) or not finite_number(value.y) then return nil end
  return {x = value.x, y = value.y}
end

local function local_view(raw)
  raw = type(raw) == "table" and raw or {}
  local value = {
    schema = SCHEMA,
    query = text(raw.query),
    family = raw.family == "all" and "all" or "mir",
    selected = technology_id(raw.selected),
    location = location(raw.location),
    scroll = type(raw.scroll) == "number" and raw.scroll > 0 and math.floor(raw.scroll) or 1
  }
  -- The data-only model independently normalizes its own read surface. Keep
  -- this UI-owned record narrow and copy back only fields this host owns.
  local normalized = library_model.normalize({
    search = value.query,
    family = value.family,
    selected = value.selected
  })
  if type(normalized) == "table" then
    value.query = text(normalized.search or value.query)
    value.family = normalized.family == "mir" and "mir" or "all"
    value.selected = type(normalized.selected) == "string" and normalized.selected or nil
  end
  return value
end

local function view_for(player_index)
  local state = ensure_state()
  local value = local_view(state.players[player_index])
  state.players[player_index] = value
  return value
end

local function player_index(value)
  if type(value) ~= "number" or value < 1 or value ~= math.floor(value) then return nil end
  return value
end

-- Preserve the old browser's personal records as plain, bounded data.  MIR5
-- only understands the deliberately small view below; filters and preferences
-- outside it remain available for a later fidelity slice instead of being
-- discarded during a configuration change.
local function legacy_copy(value, depth, budget, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then return value end
  if kind == "number" then return finite_number(value) and value or nil end
  if kind == "string" then return string.sub(value, 1, LEGACY_SNAPSHOT_MAX_STRING) end
  if kind ~= "table" or depth >= LEGACY_SNAPSHOT_MAX_DEPTH or budget.left <= 0 then return nil end
  if seen[value] then return nil end
  seen[value] = true

  local copy = {}
  for key, child in pairs(value) do
    if budget.left <= 0 then break end
    local copied_key = legacy_copy(key, depth + 1, budget, seen)
    if copied_key ~= nil then
      budget.left = budget.left - 1
      local copied_value = legacy_copy(child, depth + 1, budget, seen)
      if copied_value ~= nil then copy[copied_key] = copied_value end
    end
  end
  seen[value] = nil
  return copy
end

local function legacy_snapshot(value)
  return legacy_copy(value, 0, {left = LEGACY_SNAPSHOT_MAX_ENTRIES}, {})
end

local function legacy_browser_state()
  local namespace = type(storage) == "table" and storage[LEGACY_NAMESPACE] or nil
  local browser = type(namespace) == "table" and namespace[LEGACY_BROWSER_KEY] or nil
  return type(browser) == "table" and browser or nil
end

local function legacy_view_as_private(value)
  return local_view({
    query = value.search,
    family = value.family,
    selected = value.selected,
    location = value.location,
    scroll = value.scroll
  })
end

local function legacy_marker(frame)
  if not valid(frame) then return nil end
  local ok, marker = pcall(function() return frame[LEGACY_ROOT_MARKER] end)
  return ok and valid(marker) and marker or nil
end

local function model_view(view)
  return library_model.normalize({
    search = view.query,
    family = view.family,
    selected = view.selected
  })
end

local function context_for(force)
  if type(cap_provider) ~= "function" then return nil end
  local ok, caps = pcall(cap_provider, force)
  if not ok or type(caps) ~= "table" then return nil end
  -- The model may ask this closure about several rows. It receives the same
  -- already-read snapshot and never causes another lifecycle/settings lookup.
  return {cap_provider = function(observed_force)
    if observed_force ~= force then return nil end
    return caps
  end}
end

local function rows_for(player, view, context)
  local rows = library_model.rows(player.force, catalogue.declared(), model_view(view), {}, context)
  if type(rows) ~= "table" then return {} end
  return rows
end

local function selected_detail(player, view, context)
  if not view.selected then return nil end
  return library_model.detail(player.force, catalogue.declared(), model_view(view), {}, context)
end

local function screen_root(player)
  return player.gui and player.gui.screen and player.gui.screen[ROOT] or nil
end

local function set_shortcut(player, toggled)
  if type(player.set_shortcut_toggled) == "function" then
    player.set_shortcut_toggled(SHORTCUT, toggled == true)
  end
end

local function remember_location(view, frame)
  if valid(frame) then
    local remembered = location(frame.location)
    if remembered then view.location = remembered end
  end
end

local function destroy_frame(player, view)
  local frame = screen_root(player)
  if valid(frame) then
    remember_location(view, frame)
    frame.destroy()
  end
  set_shortcut(player, false)
end

-- A same-named frame alone is not enough to claim it.  The historical browser
-- always created this tabbed-pane child, while the MIR5 root uses its own
-- mir_library_filters and mir_library_content children.
local function rebuild_owned_legacy_root(player, view)
  local frame = screen_root(player)
  if not legacy_marker(frame) then return false end
  remember_location(view, frame)
  frame.destroy()
  set_shortcut(player, false)
  M.open(player)
  return true
end

local function caption(row)
  if type(row.name) == "string" and row.name ~= "" then return row.name end
  return row.id or ""
end

local function row_index(rows, selected)
  for index, row in ipairs(rows) do
    if row.id == selected then return index end
  end
  return nil
end

local function add(parent, spec)
  return parent.add(spec)
end

local function detail_lines(parent, row, detail)
  if not row then
    add(parent, {type = "label", name = PREFIX .. "detail_empty", caption = {"mir-browser.no-results"}})
    return
  end

  add(parent, {type = "label", name = PREFIX .. "detail_title", caption = caption(row)})
  add(parent, {type = "label", name = PREFIX .. "detail_family", caption = {"mir-browser.family", row.family or "mir"}})
  if row.cap and row.cap > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_level", caption = {"mir-browser.level-cap", row.current_level or 1, row.cap}})
    add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"", {"mir-browser.setting-max-level"}, ": ", tostring(row.cap_setting or row.cap)}})
  else
    add(parent, {type = "label", name = PREFIX .. "detail_level", caption = {"mir-browser.level", row.current_level or 1}})
    if row.cap_state == "unlimited" then
      add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"", {"mir-browser.setting-max-level"}, ": ", {"mir-browser.setting-unlimited"}}})
    elseif row.cap_state == "unavailable" then
      add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"mir-browser.detail-unavailable", {"mir-browser.setting-max-level"}}})
    end
  end
  if type(detail) == "table" and detail.cost ~= nil then
    add(parent, {type = "label", name = PREFIX .. "detail_cost", caption = {"mir-browser.research-cost", tostring(type(detail.cost) == "table" and (detail.cost.count or detail.cost[1] or "?") or detail.cost), tostring(type(detail.cost) == "table" and (detail.cost.time or detail.cost.energy or detail.cost[2] or "?") or "?")}})
  end
  if type(detail) == "table" and type(detail.prerequisites) == "table" and #detail.prerequisites > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_prerequisites", caption = {"mir-browser.prerequisites"}})
    for index, prerequisite in ipairs(detail.prerequisites) do
      add(parent, {type = "label", name = PREFIX .. "prerequisite_" .. index, caption = tostring(prerequisite)})
    end
  end
  if type(detail) == "table" and type(detail.effects) == "table" and #detail.effects > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_benefits", caption = {"mir-browser.benefits"}})
    for index, effect in ipairs(detail.effects) do
      local effect_type = type(effect) == "table" and effect.type or effect
      local change = type(effect) == "table" and effect.change or nil
      local text_value = tostring(effect_type or "")
      if change ~= nil then text_value = text_value .. " " .. tostring(change) end
      add(parent, {type = "label", name = PREFIX .. "effect_" .. index, caption = text_value})
    end
  end
end

local function update_content(frame, player, view, context)
  local content = frame[PREFIX .. "content"]
  if not valid(content) then return end
  content.clear()

  local rows = rows_for(player, view, context)
  local labels = {}
  for index, row in ipairs(rows) do labels[index] = caption(row) end
  local selected_index = row_index(rows, view.selected) or 0
  local results = add(content, {type = "list-box", name = PREFIX .. "results", items = labels, selected_index = selected_index})
  if view.scroll and view.scroll <= #labels and type(results.scroll_to_item) == "function" then
    results.scroll_to_item(view.scroll, "top-third")
  end
  add(content, {type = "label", name = PREFIX .. "count", caption = {"mir-browser.count", #rows}})

  local selected = selected_index > 0 and rows[selected_index] or nil
  if selected then view.selected = selected.id end
  local detail = selected and selected_detail(player, view, context) or nil
  local detail_box = add(content, {type = "flow", name = PREFIX .. "detail", direction = "vertical"})
  detail_lines(detail_box, selected, detail)

  local actions = add(content, {type = "flow", name = PREFIX .. "actions", direction = "horizontal"})
  add(actions, {type = "button", name = PREFIX .. "open_native", caption = {"mir-browser.open-research"}, enabled = selected ~= nil})
  add(actions, {type = "button", name = PREFIX .. "close", caption = {"mir-browser.close"}})
end

local function create_frame(player, view)
  local screen = player.gui and player.gui.screen
  if not valid(screen) then return nil end
  local frame = add(screen, {type = "frame", name = ROOT, direction = "vertical", caption = {"mir-browser.title"}})
  if view.location then frame.location = view.location end

  local filters = add(frame, {type = "flow", name = PREFIX .. "filters", direction = "horizontal"})
  add(filters, {type = "label", name = PREFIX .. "search_label", caption = {"mir-browser.search-label"}})
  add(filters, {type = "textfield", name = PREFIX .. "query", text = view.query})
  add(filters, {type = "drop-down", name = PREFIX .. "family", items = {{"mir-browser.scope-all"}, {"mir-browser.scope-mir"}}, selected_index = view.family == "mir" and 2 or 1})
  add(frame, {type = "flow", name = PREFIX .. "content", direction = "vertical"})
  return frame
end

-- Dynamic list/detail content is rebuilt under a stable root. In particular,
-- query edits preserve the existing text field, native focus and caret.
local function render(player, view, context, preserve_query)
  context = context or context_for(player.force)
  local frame = screen_root(player)
  if not valid(frame) then frame = create_frame(player, view) end
  if not valid(frame) then return nil end

  local filters = frame[PREFIX .. "filters"]
  local query = valid(filters) and filters[PREFIX .. "query"] or nil
  if valid(query) and not preserve_query then query.text = view.query end
  local family = valid(filters) and filters[PREFIX .. "family"] or nil
  if valid(family) then family.selected_index = view.family == "mir" and 2 or 1 end
  update_content(frame, player, view, context)
  set_shortcut(player, true)
  return frame
end

-- Called by the parse-time composition owner. The provider is the sole
-- bridge from the UI host to lifecycle-resolved cap values; it must return a
-- detached plain id-to-nonnegative-integer map for the supplied force.
function M.set_cap_provider(provider)
  if provider ~= nil and type(provider) ~= "function" then
    error("MIR Library cap provider must be a function or nil", 2)
  end
  cap_provider = provider
end

function M.open(player, options)
  if not valid(player) or type(player.index) ~= "number" then return nil end
  local view = view_for(player.index)
  options = type(options) == "table" and options or {}
  if options.query ~= nil then view.query = text(options.query) end
  if options.family == "all" or options.family == "mir" then view.family = options.family end
  local selected = technology_id(options.selected)
  if selected then view.selected = selected end
  return render(player, view)
end

function M.close(player)
  if not valid(player) or type(player.index) ~= "number" then return end
  local view = view_for(player.index)
  destroy_frame(player, view)
end

function M.on_lua_shortcut(event)
  if not event or event.prototype_name ~= SHORTCUT then return end
  local player = player_for(event.player_index)
  if not player then return end
  if valid(screen_root(player)) then M.close(player) else M.open(player) end
end

function M.on_gui_text_changed(event)
  local element = event and event.element
  if not valid(element) or element.name ~= PREFIX .. "query" then return end
  local player = player_for(event.player_index)
  if not player then return end
  local view = view_for(player.index)
  view.query = text(element.text)
  view.scroll = 1
  render(player, view, nil, true)
end

function M.on_gui_selection_state_changed(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event.player_index)
  if not player then return end
  local view = view_for(player.index)
  if element.name == PREFIX .. "family" then
    view.family = element.selected_index == 2 and "mir" or "all"
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "results" then
    local context = context_for(player.force)
    local rows = rows_for(player, view, context)
    local index = element.selected_index
    local row = type(index) == "number" and rows[index] or nil
    if row then
      view.selected = row.id
      view.scroll = index
      render(player, view, context)
    end
  end
end

function M.on_gui_click(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event.player_index)
  if not player then return end
  if element.name == PREFIX .. "close" then
    M.close(player)
    return
  end
  if element.name ~= PREFIX .. "open_native" then return end
  local view = view_for(player.index)
  local selected = technology_id(view.selected)
  if selected == nil then return end
  local technologies = player.force and player.force.technologies
  if technologies == nil then return end
  local ok, technology = pcall(function() return technologies[selected] end)
  if not ok or not valid(technology) then return end
  destroy_frame(player, view)
  if type(player.open_technology_gui) == "function" then player.open_technology_gui(technology) end
end

function M.on_gui_location_changed(event)
  local element = event and event.element
  if not valid(element) or element.name ~= ROOT then return end
  local player = player_for(event.player_index)
  if not player then return end
  local view = view_for(player.index)
  local remembered = location(element.location)
  if remembered then view.location = remembered end
end

function M.on_gui_closed(event)
  local element = event and event.element
  if not valid(element) or element.name ~= ROOT then return end
  local player = player_for(event.player_index)
  if player then M.close(player) end
end

function M.on_player_removed(event)
  if not event or type(event.player_index) ~= "number" then return end
  local state = existing_state()
  if state then state.players[event.player_index] = nil end
end

-- Lifecycle callbacks deliberately do not initialize player state.  A later
-- explicit open reconstructs the frame from a normalized saved view.
function M.on_init()
end

-- Published 4.7 stored the browser at storage.mir.research_browser and used
-- view schema 3.  Copy every historic per-player record into a private
-- preservation envelope, migrate only the fields this first Library slice
-- supports, and leave the published bucket untouched.  Existing MIR5 views
-- win so a repeated configuration change cannot overwrite a newer choice.
function M.on_configuration_changed()
  local legacy = legacy_browser_state()
  local legacy_players = legacy and legacy.players
  if type(legacy_players) ~= "table" then return end

  local candidates = {}
  for index, historical_view in pairs(legacy_players) do
    local normalized_index = player_index(index)
    if normalized_index and type(historical_view) == "table" then
      candidates[#candidates + 1] = {index = normalized_index, view = historical_view}
    end
  end
  if #candidates == 0 then return end

  local state = existing_state() or ensure_state()
  local preserved = state.legacy_browser
  if type(preserved) ~= "table" then
    preserved = {
      version = LEGACY_SNAPSHOT_VERSION,
      source = "storage.mir.research_browser",
      players = {}
    }
    state.legacy_browser = preserved
  elseif type(preserved.players) ~= "table" then
    preserved.players = {}
  end

  for _, candidate in ipairs(candidates) do
    local index, historical_view = candidate.index, candidate.view
    if preserved.players[index] == nil then
      preserved.players[index] = legacy_snapshot(historical_view)
    end
    if type(state.players[index]) ~= "table" then
      state.players[index] = legacy_view_as_private(historical_view)
    end
  end

  -- game.get_player(uint32) and LuaGuiElement child lookup/destroy are
  -- documented by the local 2.1 runtime API.  No player is created here: a
  -- headless native process cannot establish GUI-client evidence.
  for _, candidate in ipairs(candidates) do
    local player = player_for(candidate.index)
    if player then
      local view = local_view(state.players[candidate.index])
      state.players[candidate.index] = view
      rebuild_owned_legacy_root(player, view)
    end
  end
end

-- Load is intentionally read-only: it neither migrates, repairs, nor rebuilds
-- a player view.  Migration belongs to configuration change only.
function M.on_load()
end

-- Root event composition can call this after any library callback. This first
-- slice resolves search synchronously and has no localization dispatcher, so
-- it requests no periodic work while closed or open.
function M.subscription_needs()
  return nil
end

return M
