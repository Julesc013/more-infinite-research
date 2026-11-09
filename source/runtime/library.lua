-- Player-local Research Library presentation and interaction.
--
-- The catalogue/model modules own research facts. This module owns only a
-- player's small view preference and GUI construction. Control.lua must route
-- its callbacks explicitly; this file never registers handlers or creates a
-- recurring subscription by itself.
local catalogue = require("runtime.catalogue")
local settings_catalog = require("research.settings")
-- Configuration resolves MIRSET1 precedence once at control parse time. The
-- Availability view receives its compact stream map rather than resolving a
-- profile while the player opens or filters the Library.
local effective_configuration = require("runtime.configuration")
local profile_codec = require("research.settings_profile")
local library_model = require("presentation.library_model")
local library_layout = require("presentation.library_layout")
local library_effects = require("presentation.library_effects")
local library_localization = require("presentation.library_localization")
local availability = require("presentation.availability")
local target = require("platform.target")
local translation_queue = require("runtime.library_translations")
local library_production = require("runtime.library_production")
local support_exports
if helpers and type(helpers.write_file) == "function" then
  support_exports = require("runtime.settings_commands")
end
local diagnostics = support_exports and require("runtime.diagnostics")

local M = {}

local STORAGE_KEY = "mir_library"
local SCHEMA = 1
local ROOT = "mir_research_browser"
-- A name is shared global GUI namespace, so it cannot establish ownership.
-- The tag is set when this slice creates the root; callbacks also prove the
-- full parent chain back to the current player's screen before changing state.
local ROOT_TAG = "more-infinite-research.library-root.v1"
local PREFIX = "mir_library_"
local SHORTCUT = "mir-research-browser"
local MAX_QUERY = 160
local MAX_HIDDEN = 128
local MAX_PAGE = 30000
local MAX_FAMILY_DESCRIPTORS = 128
local MAX_SETTING_DESCRIPTORS = 2048
local SETTING_TRANSLATION_PREFIX = "@setting:"
local LEGACY_NAMESPACE = "mir"
local LEGACY_BROWSER_KEY = "research_browser"
local LEGACY_ROOT_MARKER = "mir_browser_tabs"
local LEGACY_SNAPSHOT_VERSION = 1
local LEGACY_SNAPSHOT_MAX_DEPTH = 8
local LEGACY_SNAPSHOT_MAX_ENTRIES = 512
local LEGACY_SNAPSHOT_MAX_STRING = 4096
local cap_provider = nil
local discovery_visibility_provider
local DISCOVERY_TREE = script and script.active_mods and script.active_mods.discovery_tree ~= nil
local TRANSLATION_SCHEMA = 1
local TRANSLATION_MAINTENANCE_TICKS = 61
local setting_groups_cache
local setting_prototype_cache
local TABS = {"research", "queue", "settings", "help"}
local TAB_INDEX = {research = 1, queue = 2, settings = 3, help = 4}

-- Open translation work is saved separately from personal preferences, so a
-- joining client reconnects the same labels, cursor and issued window.
-- Closing a view drops that working cache and retains only issued native IDs.
local translation_caches = {}
local declaration_cache
-- Credit carriers are genuine native technologies for migration/runtime
-- accounting, but never Library research. The catalogue supplies this small
-- exact identity map at control parse; it is not inferred from hidden flags
-- or native names.
local private_credit_ids = catalogue.internal_credit_ids()

-- Authored metadata is immutable within a loaded configuration. Build its
-- private copy only for actual UI use; force/research/cap facts stay live.
local function authored_declarations()
  if declaration_cache == nil then declaration_cache = catalogue.declared() end
  return declaration_cache
end

M.translation_maintenance_ticks = TRANSLATION_MAINTENANCE_TICKS
M.native_refresh_ticks = 1

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- LuaStyle dimensions are int32. Retain the existing upper/lower layout
-- bounds while making display-scale division safe for the native setters.
local function style_pixels(value)
  return math.max(1, math.floor(value))
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function private_credit_id(id)
  return type(id) == "string" and private_credit_ids[id] == true
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

local function whole_option(value, minimum, maximum)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    and value == math.floor(value) and value >= minimum and value <= maximum and value or nil
end

local function status_option(value)
  return whole_option(value, 1, 4)
end

local function sort_option(value)
  if value == "progression" or value == "native" or value == "name-asc" or value == "name-desc" then
    return value
  end
  return nil
end

local SORT_INDEX = {
  ["progression"] = 1,
  ["native"] = 2,
  ["name-asc"] = 3,
  ["name-desc"] = 4
}

-- The published browser offered its aggregate choices plus actual authored
-- family descriptors.  These values come only from the compact declaration
-- catalogue; a force's native technologies never create GUI selectors.
local function family_values()
  local values, known = {"mir", "all", "external"}, {mir = true, all = true, external = true}
  local ok, declared = pcall(authored_declarations)
  if not ok or type(declared) ~= "table" or #declared > MAX_FAMILY_DESCRIPTORS then return values, known end
  local extras = {}
  for index = 1, #declared do
    local row = declared[index]
    local family = type(row) == "table" and technology_id(row.family) or nil
    if family and not known[family] then
      if #extras >= MAX_FAMILY_DESCRIPTORS then
        return {"mir", "all", "external"}, {mir = true, all = true, external = true}
      end
      known[family] = true
      extras[#extras + 1] = family
    end
  end
  table.sort(extras)
  for _, family in ipairs(extras) do values[#values + 1] = family end
  return values, known
end

local function family_option(value)
  local _, known = family_values()
  return type(value) == "string" and known[value] and value or nil
end

local function family_from_index(value)
  local values = family_values()
  return whole_option(value, 1, #values) and values[value] or nil
end

local function family_caption(family, native_names)
  if family == "mir" then return {"mir-browser.scope-mir"} end
  if family == "all" then return {"mir-browser.scope-all"} end
  if family == "external" then return {"mir-browser.scope-native"} end
  -- Authored technology names can require localized parameters. Use the
  -- engine's complete name rather than invoking its locale key without them.
  if native_names[family] ~= nil then return native_names[family] end
  return family:gsub("^research_", ""):gsub("[-_]", " "):gsub("^%l", string.upper)
end

local function family_items(values, player)
  local native_names = {}
  for _, row in ipairs(authored_declarations()) do
    local family = type(row) == "table" and technology_id(row.family) or nil
    if family and native_names[family] == nil then
      local ok, name = pcall(function()
        local technology = player.force.technologies[row.id]
        return technology and technology.localised_name or nil
      end)
      if ok then native_names[family] = name end
    end
  end
  local items = {}
  for index, family in ipairs(values) do items[index] = family_caption(family, native_names) end
  return items
end

local function family_index(values, family)
  for index, candidate in ipairs(values) do
    if candidate == family then return index end
  end
  return nil
end

-- Personal hiding remains a view-local filter.  The published third choice
-- showed its terminal availability explanation within Research, rather than
-- constructing a speculative omitted-technology catalogue.
local function visibility_option(value)
  return whole_option(value, 1, 3)
end

local function sort_from_index(value)
  if value == 1 then return "progression" end
  if value == 2 then return "native" end
  if value == 3 then return "name-asc" end
  if value == 4 then return "name-desc" end
  return "progression"
end

local function known_technology(player, id)
  if not valid(player) or id == nil or private_credit_id(id) then return nil end
  local ok, technology = pcall(function()
    local force = player.force
    local technologies = force and force.technologies
    return technologies and technologies[id] or nil
  end)
  return ok and valid(technology) and technology or nil
end

-- The published remote browser accepted only a dense, known-technology list.
-- Validate it before changing the saved view so malformed callers cannot hide
-- arbitrary names or turn a bounded selection into an unbounded native scan.
local function hidden_option(player, values)
  if type(values) ~= "table" then return nil end
  local entries, count, valid_input = {}, 0, true
  local scanned = pcall(function()
    for index, id in pairs(values) do
      if not whole_option(index, 1, MAX_HIDDEN) or technology_id(id) == nil or entries[index] ~= nil then
        valid_input = false
        return
      end
      count = count + 1
      if count > MAX_HIDDEN then
        valid_input = false
        return
      end
      entries[index] = id
    end
  end)
  if not scanned or not valid_input then return nil end

  local hidden, seen = {}, {}
  for index = 1, count do
    local id = entries[index]
    if id == nil or seen[id] or known_technology(player, id) == nil then return nil end
    seen[id], hidden[id] = true, true
  end
  return hidden
end

local function location(value)
  if type(value) ~= "table" then return nil end
  if not finite_number(value.x) or not finite_number(value.y) then return nil end
  return {x = value.x, y = value.y}
end

local function geometry(value)
  if type(value) ~= "table" or not finite_number(value.width) or not finite_number(value.height) then return nil end
  if value.width < 1 or value.height < 1 then return nil end
  return {width = math.floor(value.width), height = math.floor(value.height)}
end

local function local_view(raw)
  raw = type(raw) == "table" and raw or {}
  local value = {
    schema = SCHEMA,
    query = text(raw.query),
    family = raw.family ~= nil and raw.family or "mir",
    mode = raw.mode,
    status = raw.status,
    page = raw.page,
    sort = raw.sort,
    stable_sort = raw.stable_sort,
    visibility = raw.visibility,
    hidden = raw.hidden,
    selected = technology_id(raw.selected),
    tab = raw.tab,
    settings_scope = raw.settings_scope,
    settings_query = text(raw.settings_query),
    setting_selected = technology_id(raw.setting_selected),
    report_settings = raw.report_settings == true,
    report_omissions = raw.report_omissions == true,
    open = raw.open == true,
    refresh_pending = raw.refresh_pending == true,
    location = location(raw.location),
    geometry = geometry(raw.geometry),
    scroll = type(raw.scroll) == "number" and raw.scroll > 0 and math.floor(raw.scroll) or 1
  }
  -- The data-only model independently normalizes its own read surface. Keep
  -- this UI-owned record narrow and copy back only fields this host owns.
  local normalized = library_model.normalize({
    search = value.query,
    family = value.family,
    mode = value.mode,
    status = value.status,
    page = value.page,
    sort = value.sort,
    stable_sort = value.stable_sort,
    visibility = value.visibility,
    hidden = value.hidden,
    selected = value.selected
  })
  if type(normalized) == "table" then
    value.query = text(normalized.search or value.query)
    value.family = family_option(normalized.family) or "mir"
    value.mode = whole_option(normalized.mode, 1, 3) or 1
    value.status = type(normalized.status) == "number" and normalized.status or 1
    value.page = type(normalized.page) == "number" and normalized.page or 1
    value.sort = type(normalized.sort) == "string" and normalized.sort or "progression"
    value.stable_sort = type(normalized.stable_sort) == "string" and normalized.stable_sort or "progression"
    value.visibility = visibility_option(normalized.visibility) or 1
    value.hidden = type(normalized.hidden) == "table" and normalized.hidden or {}
    value.selected = type(normalized.selected) == "string" and normalized.selected or nil
  end
  value.tab = TAB_INDEX[value.tab] and value.tab or "research"
  value.settings_scope = value.settings_scope == "options" and "options" or "research"
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

local function whole_number(value, minimum)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    and value == math.floor(value) and value >= minimum
end

-- The issued-request ledger retains its original schema. The optional working
-- map adds schema-1 open-view caches containing plain bounded translation
-- data only; no LuaObjects, native research facts or Generator state is saved.
local function existing_translation_ledger(state)
  local value = type(state) == "table" and state.translations or nil
  if type(value) ~= "table" or value.schema ~= TRANSLATION_SCHEMA
      or not whole_number(value.next_epoch, 0)
      or type(value.active) ~= "table" or type(value.retired) ~= "table" then
    return nil
  end
  return value
end

-- Unknown or malformed private state may still contain issued native request
-- IDs. A writable view must leave it intact and decline translation issuance;
-- only an absent sidecar may receive this schema.
local function ensure_translation_ledger(state)
  local value = existing_translation_ledger(state)
  if value then return value end
  if state.translations ~= nil then return nil end
  value = {
    schema = TRANSLATION_SCHEMA,
    next_epoch = 0,
    active = {},
    retired = {}
  }
  state.translations = value
  return value
end

local function ordered_player_indices(rows)
  local indices = {}
  for index in pairs(rows) do
    if whole_number(index, 1) then indices[#indices + 1] = index end
  end
  table.sort(indices)
  return indices
end

local function reconnect_translation_caches()
  translation_caches = {}
  local state = type(storage) == "table" and storage[STORAGE_KEY] or nil
  local ledger = existing_translation_ledger(state)
  local working = ledger and ledger.working
  if type(working) ~= "table" then return end
  for index, saved in pairs(working) do
    if whole_number(index, 1) and type(saved) == "table" and saved.schema == 1
        and (saved.family == "settings" or technology_id(saved.family) ~= nil) and type(saved.scope) == "table"
        and saved.scope.player_index == index
        and translation_queue.labels(saved.cache, saved.scope) ~= nil then
      translation_caches[index] = {
        player_index = index, scope = saved.scope, family = saved.family,
        cache = saved.cache, ledger = ledger
      }
    end
  end
end

local function entry_pending(entry)
  return type(entry) == "table" and type(entry.pending) == "table" and #entry.pending > 0
    and entry.pending or nil
end

local function next_translation_epoch(ledger)
  local previous = whole_number(ledger.next_epoch, 0) and ledger.next_epoch or 0
  ledger.next_epoch = previous + 1
  return ledger.next_epoch
end

local function scope_for(player, epoch)
  local force = player and player.force
  if not valid(player) or not whole_number(player.index, 1) or type(player.locale) ~= "string"
      or not whole_number(epoch, 0) or force == nil then
    return nil
  end
  local force_index = force and force.index
  if not whole_number(force_index, 1) then return nil end
  return {
    player_index = player.index,
    locale = player.locale,
    force_index = force_index,
    generation = epoch
  }
end

local function same_translation_scope(left, right)
  return type(left) == "table" and type(right) == "table"
    and left.player_index == right.player_index and left.locale == right.locale
    and left.force_index == right.force_index and left.generation == right.generation
end

local function setting_prototypes_by_name()
  if setting_prototype_cache ~= nil then return setting_prototype_cache end
  local ok, values = pcall(settings_catalog.prototypes)
  if not ok or type(values) ~= "table" or #values > MAX_SETTING_DESCRIPTORS then return nil end
  local result = {}
  for _, prototype in ipairs(values) do
    if type(prototype) ~= "table" or type(prototype.name) ~= "string" or prototype.name == ""
      or result[prototype.name] ~= nil then return nil end
    result[prototype.name] = prototype
  end
  setting_prototype_cache = result
  return setting_prototype_cache
end

-- Authored-only family views translate only declared technologies that exist
-- in this force. All/external views scan the caller's current native force
-- once per family/scope change and keep a bounded deterministic request order.
local function ordered_translation_ids(player, family)
  local ids, seen = {}, {}
  local function add_id(id)
    if type(id) ~= "string" or id == "" or #id > translation_queue.label_limit then return false end
    if seen[id] then return true end
    if #ids >= translation_queue.catalogue_limit then return false end
    seen[id] = true
    ids[#ids + 1] = id
    return true
  end
  if family == "settings" then
    local names_ok, names = pcall(settings_catalog.registered_names)
    if not names_ok or type(names) ~= "table" or #names > MAX_SETTING_DESCRIPTORS then return nil end
    for _, name in ipairs(names) do
      if type(name) ~= "string" or name == "" or not add_id(SETTING_TRANSLATION_PREFIX .. name) then return nil end
    end
    return ids
  end
  local ok, declared = pcall(authored_declarations)
  if not ok or type(declared) ~= "table" then return nil end
  local force = player and player.force
  local technologies = force and force.technologies
  if technologies == nil then return nil end
  local function technology_exists(id)
    local found, technology = pcall(function() return technologies[id] end)
    return found and valid(technology)
  end

  local declarations = {}
  for _, row in ipairs(declared) do
    if type(row) ~= "table" or type(row.id) ~= "string" or row.id == ""
        or #row.id > translation_queue.label_limit then return nil end
    declarations[row.id] = row
    if not private_credit_id(row.id) then
      local declared_family = technology_id(row.family) or "mir"
      local include_declared = family == "all"
        or family == "mir" and declared_family ~= "external"
        or family == declared_family
      if include_declared and technology_exists(row.id) and not add_id(row.id) then return nil end
    end
  end
  if family ~= "all" and family ~= "external" then return ids end

  local native, overflow = {}, false
  local scanned_ok = pcall(function()
    for id, technology in pairs(technologies) do
      if not valid(technology) or type(id) ~= "string" or id == "" or #id > translation_queue.label_limit then
        overflow = true
        return
      end
      native[#native + 1] = id
      if #native > translation_queue.catalogue_limit then
        overflow = true
        return
      end
    end
  end)
  if not scanned_ok or overflow then return nil end
  table.sort(native)
  for _, id in ipairs(native) do
    if not private_credit_id(id) then
      local declaration = declarations[id]
      local declared_family = declaration and technology_id(declaration.family) or "mir"
      if family ~= "external" or declaration == nil or declared_family == "external" then
        if not add_id(id) then return nil end
      end
    end
  end
  return ids
end

-- Preserve the old browser's personal records as a bounded convenience copy.
-- The published bucket remains untouched and is the authoritative full-fidelity
-- record. Snapshot metadata makes any bounded copy explicit rather than
-- silently presenting it as a complete migration.
local function legacy_copy(value, depth, budget, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then return value end
  if kind == "number" then
    if finite_number(value) then return value end
    budget.truncated, budget.invalid = true, true
    return nil
  end
  if kind == "string" then
    if #value <= LEGACY_SNAPSHOT_MAX_STRING then return value end
    budget.truncated, budget.string_limited = true, true
    return string.sub(value, 1, LEGACY_SNAPSHOT_MAX_STRING)
  end
  if kind ~= "table" then
    budget.truncated, budget.unsupported = true, true
    return nil
  end
  if depth >= LEGACY_SNAPSHOT_MAX_DEPTH then
    budget.truncated, budget.depth_limited = true, true
    return nil
  end
  if budget.left <= 0 then
    budget.truncated, budget.entry_limited = true, true
    return nil
  end
  if seen[value] then
    budget.truncated, budget.cyclic = true, true
    return nil
  end
  seen[value] = true

  local copy = {}
  for key, child in pairs(value) do
    if budget.left <= 0 then
      budget.truncated, budget.entry_limited = true, true
      break
    end
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
  local budget = {left = LEGACY_SNAPSHOT_MAX_ENTRIES}
  local copied = legacy_copy(value, 0, budget, {})
  return copied, {
    complete = budget.truncated ~= true,
    truncated = budget.truncated == true,
    entry_limited = budget.entry_limited == true,
    depth_limited = budget.depth_limited == true,
    string_limited = budget.string_limited == true,
    cyclic = budget.cyclic == true,
    unsupported = budget.unsupported == true,
    invalid = budget.invalid == true
  }
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
    mode = value.mode,
    status = value.status,
    page = value.page,
    sort = value.sort,
    stable_sort = value.stable_sort,
    visibility = value.visibility,
    hidden = value.hidden,
    selected = value.selected,
    tab = value.tab,
    settings_scope = value.settings_scope,
    settings_query = value.settings_search,
    setting_selected = value.setting_selection,
    report_settings = value.report_settings,
    report_omissions = value.report_omissions,
    location = value.location,
    geometry = value.geometry,
    scroll = value.scroll
  })
end

local function carry_report_choices(view, historical)
  if type(view) ~= "table" or type(historical) ~= "table" then return end
  for _, field in ipairs({"report_settings", "report_omissions"}) do
    if view[field] == nil and type(historical[field]) == "boolean" then view[field] = historical[field] end
  end
end

local function legacy_player_retired(state, index)
  local preserved = state and state.legacy_browser
  local retired = type(preserved) == "table" and preserved.retired_players or nil
  return type(retired) == "table" and retired[index] == true
end

local function named_root(player)
  local gui = player and player.gui
  local screen = gui and gui.screen
  return screen and screen[ROOT] or nil
end

local function root_is_on_screen(player, frame)
  if not valid(frame) then return false end
  local gui = player and player.gui
  local screen = gui and gui.screen
  if not valid(screen) then return false end
  local ok, parent = pcall(function() return frame.parent end)
  return ok and parent == screen
end

local function root_has_tag(frame)
  local ok, tags = pcall(function() return frame.tags end)
  return ok and type(tags) == "table" and tags[ROOT_TAG] == true
end

local function owned_root(player)
  local frame = named_root(player)
  if not root_is_on_screen(player, frame) or not root_has_tag(frame) then return nil end
  return frame
end

-- Event payload names are globally shared. Check every ancestor, ending in
-- this player's tagged root, before accepting a GUI callback.
local function owns_element(player, element, names)
  if not valid(element) or type(names) ~= "table" then return false end
  local current = element
  for index = 1, #names do
    if not valid(current) or current.name ~= names[index] then return false end
    if index < #names then
      local ok, parent = pcall(function() return current.parent end)
      if not ok then return false end
      current = parent
    end
  end
  return current == owned_root(player)
end

local function legacy_marker(player, frame)
  if not root_is_on_screen(player, frame) then return nil end
  local ok, marker = pcall(function() return frame[LEGACY_ROOT_MARKER] end)
  if not ok or not valid(marker) then return nil end
  local parent_ok, parent = pcall(function() return marker.parent end)
  if not parent_ok or parent ~= frame then return nil end
  local type_ok, marker_type = pcall(function() return marker.type end)
  return type_ok and marker_type == "tabbed-pane" and marker or nil
end

local function model_view(view)
  return library_model.normalize({
    search = view.query,
    family = view.family,
    mode = view.mode,
    status = view.status,
    page = view.page,
    sort = view.sort,
    stable_sort = view.stable_sort,
    visibility = view.visibility,
    hidden = view.hidden,
    selected = view.selected
  })
end

local function context_for(force)
  local context = {
    private_credit_ids = private_credit_ids,
    discovery_tree = DISCOVERY_TREE == true,
    research_triggers_supported = target.id == "f200" or target.id == "f210",
    recipe_productivity_supported = target.recipe_productivity == true
  }
  if DISCOVERY_TREE and type(discovery_visibility_provider) == "function" then
    context.discovery_visibility = discovery_visibility_provider(force)
  end
  if type(cap_provider) ~= "function" then return context end
  local ok, caps = pcall(cap_provider, force)
  if not ok or type(caps) ~= "table" then return context end
  -- The model may ask this closure about several rows. It receives the same
  -- already-read snapshot and never causes another lifecycle/settings lookup.
  context.cap_provider = function(observed_force)
    if observed_force ~= force then return nil end
    return caps
  end
  return context
end

local EMPTY_TRANSLATIONS = {}

local function cache_from_pending(pending)
  if type(pending) ~= "table" or #pending == 0 then return nil end
  local first = pending[1]
  if type(first) ~= "table" or type(first.scope) ~= "table" then return nil end
  local cache = translation_queue.new(first.scope)
  if cache == nil or not translation_queue.hydrate_pending(cache, pending) then return nil end
  return cache
end

local function sync_issued_cache(record)
  if type(record) ~= "table" or type(record.ledger) ~= "table" then return false end
  local pending = translation_queue.export_pending(record.cache)
  if pending == nil then return false end
  local working = record.ledger.working
  if working == nil then
    working = {}
    record.ledger.working = working
  end
  if type(working) ~= "table" then return false end
  local previous = working[record.player_index]
  if previous ~= nil and (type(previous) ~= "table" or previous.schema ~= 1
      or previous.cache ~= record.cache) then return false end
  working[record.player_index] = {
    schema = 1, scope = record.scope, family = record.family, cache = record.cache
  }
  if #pending == 0 then
    record.ledger.active[record.player_index] = nil
  else
    record.ledger.active[record.player_index] = {
      epoch = record.scope.generation,
      pending = pending
    }
  end
  return true
end

local function discard_translation_cache(index)
  local record = translation_caches[index]
  if record then sync_issued_cache(record) end
  local ledger = record and record.ledger
  local working = ledger and ledger.working
  if record and type(working) == "table" then
    local saved = working[index]
    if type(saved) ~= "table" or saved.schema ~= 1 or saved.cache ~= record.cache then
      translation_caches[index] = nil
      return
    end
    working[index] = nil
    if next(working) == nil then ledger.working = nil end
  end
  translation_caches[index] = nil
end

local function open_translation_cache(player, view)
  local index = player and player.index
  if not whole_number(index, 1) then return nil end
  local family = type(view) == "table" and view.tab == "settings" and "settings"
    or (type(view) == "table" and family_option(view.family) or "mir")
  local retained = translation_caches[index]
  local same_live_scope = retained and retained.scope and retained.scope.locale == player.locale
    and retained.scope.force_index == (player.force and player.force.index)

  if retained and same_live_scope and retained.family == family
      and translation_queue.discovery_limited(retained.cache, retained.scope) ~= nil then
    -- Ordered identities are local immutable presentation data. Reusing this
    -- record prevents a native catalogue traversal on every GUI render.
    return retained
  end

  if retained and same_live_scope then
    -- Family selection or an older metadata-free cache renews derived work.
    -- Retain engine IDs already issued, but replace unissued work under a fresh caller
    -- epoch so former responses cannot label the new view.
    local ids = ordered_translation_ids(player, family)
    local ledger = retained.ledger
    local scope = ledger and scope_for(player, next_translation_epoch(ledger)) or nil
    if ids == nil or scope == nil or not translation_queue.prepare(retained.cache, scope, ids) then
      discard_translation_cache(index)
      return nil
    end
    retained.scope, retained.family = scope, family
    sync_issued_cache(retained)
    return retained
  end
  if retained then discard_translation_cache(index) end

  local state = ensure_state()
  local ledger = ensure_translation_ledger(state)
  if ledger == nil then return nil end
  if ledger.working ~= nil and type(ledger.working) ~= "table" then return nil end
  -- A remaining record was not reconnected by this implementation. Preserve
  -- that unknown working protocol rather than overwriting its issued rights.
  if ledger.working and ledger.working[index] ~= nil then return nil end
  -- A removed player can have an old engine request in flight. Preserve an
  -- unfamiliar retired entry rather than deleting it and reusing this index.
  if ledger.retired[index] ~= nil then return nil end

  -- A nonnil active record is an issued native window until it fully validates
  -- through the pure ledger hydrator. Do not discard it and create 16 more.
  local active = ledger.active[index]
  local pending = nil
  if active ~= nil then
    pending = entry_pending(active)
    if pending == nil then return nil end
  end

  local scope = scope_for(player, next_translation_epoch(ledger))
  local ids = ordered_translation_ids(player, family)
  local cache = scope and ids and translation_queue.new(scope) or nil
  if cache == nil or not translation_queue.prepare(cache, scope, ids) then return nil end
  if pending and not translation_queue.hydrate_pending(cache, pending) then return nil end

  local record = {player_index = index, scope = scope, family = family, cache = cache, ledger = ledger}
  translation_caches[index] = record
  return record
end

local function translated_labels(record)
  if type(record) ~= "table" then return EMPTY_TRANSLATIONS end
  return translation_queue.labels(record.cache, record.scope) or EMPTY_TRANSLATIONS
end

local function current_tick()
  local value = game and game.tick
  return whole_number(value, 0) and value or 0
end

-- Factorio 2.x exposes the prototype collections globally. The supported
-- 1.0/1.1 runtime exposes the same immutable collections through `game`.
-- Keep this compatibility at the read boundary so localized search and
-- selected detail work across the published edition range.
local LEGACY_PROTOTYPE_COLLECTIONS = {
  item = "item_prototypes",
  fluid = "fluid_prototypes",
  recipe = "recipe_prototypes"
}

local function prototype_collection(kind)
  local modern_ok, modern = pcall(function()
    return prototypes and prototypes[kind]
  end)
  if modern_ok and modern ~= nil then return modern end
  local legacy_key = LEGACY_PROTOTYPE_COLLECTIONS[kind]
  if legacy_key == nil then return nil end
  local legacy_ok, legacy = pcall(function()
    return game and game[legacy_key]
  end)
  return legacy_ok and legacy or nil
end

local function request_translation(player, key)
  if not valid(player) or player.connected ~= true
      or type(player.request_translation) ~= "function" then return nil end
  local subjects, limited = 0, false
  local ok, request_id = pcall(function()
    local setting_name = type(key) == "string" and key:match("^" .. SETTING_TRANSLATION_PREFIX .. "(.+)$") or nil
    if setting_name then
      local prototypes = setting_prototypes_by_name()
      local prototype = prototypes and prototypes[setting_name] or nil
      if prototype == nil or prototype.localised_name == nil then return nil end
      return player.request_translation(prototype.localised_name)
    end
    if private_credit_id(key) then return nil end
    local force = player.force
    local technologies = force and force.technologies
    local technology = technologies and technologies[key] or nil
    if not valid(technology) then return nil end
    local collections = {
      recipe = prototype_collection("recipe"),
      item = prototype_collection("item"),
      fluid = prototype_collection("fluid")
    }
    local payload
    payload, subjects, limited = library_localization.search_request(technology, collections)
    payload = payload or technology.localised_name
    return player.request_translation(payload)
  end)
  return ok and request_id or nil, subjects, limited
end

local function dispatch_translations(player, record)
  if type(record) ~= "table" or player.connected ~= true or not valid(owned_root(player)) then return end
  translation_queue.dispatch(record.cache, record.scope, current_tick(), function(key)
    return request_translation(player, key)
  end)
  sync_issued_cache(record)
end

local function update_discovery_indicator(content, record)
  local list_pane = valid(content) and content[PREFIX .. "list_pane"]
  local indicator = valid(list_pane) and list_pane[PREFIX .. "count"] or nil
  if valid(indicator) then
    indicator.tooltip = type(record) == "table"
      and translation_queue.discovery_limited(record.cache, record.scope) == true
      and {"mir-browser.discovery-limited"} or nil
  end
end

local function rows_for(player, view, context, labels)
  local rows = library_model.rows(player.force, authored_declarations(), model_view(view), labels or EMPTY_TRANSLATIONS, context)
  if type(rows) ~= "table" then return {} end
  return rows
end

local function selected_detail(player, view, context, labels)
  if not view.selected then return nil end
  return library_model.detail(player.force, authored_declarations(), model_view(view), labels or EMPTY_TRANSLATIONS, context)
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
  view.open, view.refresh_pending = false, false
  local frame = owned_root(player)
  if not valid(frame) then return false end
  remember_location(view, frame)
  frame.destroy()
  set_shortcut(player, false)
  return true
end

-- A same-named frame alone is not enough to claim it.  The historical browser
-- always created this tabbed-pane child, while the MIR5 root uses its own
-- mir_library_filters and mir_library_content children.
local function rebuild_owned_legacy_root(player, view)
  local frame = named_root(player)
  -- This is migration-only evidence for the published untagged browser, never
  -- ordinary open/close ownership. The authoritative legacy storage bucket is
  -- also required by the caller before this branch is reached.
  if not legacy_marker(player, frame) then return false end
  remember_location(view, frame)
  frame.destroy()
  set_shortcut(player, false)
  M.open(player)
  return true
end

local function native_technology_name(player, id)
  local ok, name = pcall(function()
    local technology = player.force.technologies[id]
    return valid(technology) and technology.localised_name or nil
  end)
  if ok and (type(name) == "table" or (type(name) == "string" and name ~= "")) then return name end
  return nil
end

local function native_item_name(id)
  local ok, name = pcall(function()
    local items, fluids = prototype_collection("item"), prototype_collection("fluid")
    local item = (items and items[id]) or (fluids and fluids[id])
    return valid(item) and item.localised_name or nil
  end)
  if ok and (type(name) == "table" or (type(name) == "string" and name ~= "")) then return name end
  return nil
end

local function affected_recipe_rows(player, detail)
  local result = {}
  if type(detail) ~= "table" or type(detail.recipe_targets) ~= "table" then return result end
  local seen = {}
  for _, id in ipairs(detail.recipe_targets) do
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      local ok, recipe = pcall(function()
        local force_recipe = player.force and player.force.recipes and player.force.recipes[id]
        if valid(force_recipe) then return force_recipe end
        local recipes = prototype_collection("recipe")
        return recipes and recipes[id] or nil
      end)
      if ok and valid(recipe) then
        local ok_name, name = pcall(function()
          return recipe.localised_name or (recipe.prototype and recipe.prototype.localised_name)
        end)
        result[#result + 1] = {id = id, recipe = recipe, name = ok_name and name or id}
      end
    end
  end
  return result
end

local add

local function show_production_snapshot(panel, player, technology)
  if not valid(panel) then return end
  panel.clear()
  local report = library_production.snapshot(player, technology)
  if type(report) ~= "table" then
    add(panel, {type = "label", name = PREFIX .. "production_unavailable", caption = {"mir-browser.production-unavailable"}})
    return
  end
  local scope_caption = report.scope == "force"
    and {"mir-browser.production-scope-force", report.force_name}
    or {"mir-browser.production-scope", report.force_name, report.surface_name}
  add(panel, {type = "label", name = PREFIX .. "production_scope", caption = scope_caption})
  add(panel, {type = "label", name = PREFIX .. "production_snapshot",
    caption = {"mir-browser.production-snapshot", tostring(report.tick)}})
  add(panel, {type = "label", name = PREFIX .. "production_note", caption = {"mir-browser.production-note"}})
  for index, row in ipairs(report.rows) do
    local item = native_item_name(row.name) or row.name
    add(panel, {type = "label", name = PREFIX .. "production_row_" .. index,
      caption = {"mir-browser.production-row", item, string.format("%.3g", row.produced),
        string.format("%.3g", row.consumed), string.format("%.3g", row.balance)}})
  end
end

local function open_recipe_entry(player, detail, index)
  if type(player.open_factoriopedia_gui) ~= "function" then return false end
  local recipe = affected_recipe_rows(player, detail)[index]
  if recipe == nil then return false end
  local ok = pcall(function()
    local prototype = recipe.recipe.prototype or recipe.recipe
    player.open_factoriopedia_gui(prototype)
  end)
  return ok
end

local function caption(row, player)
  if type(row.name) == "string" and row.name ~= "" and row.name ~= row.id then return row.name end
  -- Native widgets can localize complete names before the asynchronous cache
  -- supplies search/sort text. Keep that cache and its scheduling unchanged.
  local native_name = native_technology_name(player, row.id)
  if native_name ~= nil then return native_name end
  if type(row.name) == "string" and row.name ~= "" then return row.name end
  return row.id or ""
end

local function row_index(rows, selected)
  for index, row in ipairs(rows) do
    if row.id == selected then return index end
  end
  return nil
end

add = function(parent, spec)
  local element = parent.add(spec)
  -- Bound only this owned GUI subtree. Native labels wrap inside their
  -- container; no world/catalogue work is involved in sizing a requested view.
  local parent_style = spec.name ~= ROOT and parent.style or nil
  local style = element.style
  local width = parent_style and parent_style.maximal_width
  if style and type(width) == "number" and width > 0 then
    if spec.type == "label" then
      style.single_line = false
      style.maximal_width = parent.name == PREFIX .. "research_facts" and math.max(1, width - 16) or width
    elseif spec.type == "flow" or spec.type == "scroll-pane"
        or spec.type == "tabbed-pane" or spec.type == "list-box" then
      style.maximal_width = width
      style.horizontally_stretchable = true
    end
  end
  return element
end

local function research_seconds(cost)
  if type(cost) ~= "table" then return "?" end
  if type(cost.energy) == "number" then return cost.energy / 60 end
  return cost.time or cost[2] or "?"
end

local function add_recipe_benefits(parent, detail)
  if type(detail) ~= "table" then return end
  if detail.recipe_benefits_state == "unavailable" then
    add(parent, {type = "label", name = PREFIX .. "live_detail_unavailable",
      caption = {"mir-browser.live-detail-unavailable"}})
    return
  end
  local benefits = detail.recipe_benefits
  if detail.recipe_benefits_state ~= "available" or type(benefits) ~= "table" or #benefits == 0 then return end
  local current_min, current_max = benefits[1].current_productivity_bonus, benefits[1].current_productivity_bonus
  local maximum_min, maximum_max = benefits[1].maximum_productivity, benefits[1].maximum_productivity
  for index = 2, #benefits do
    local benefit = benefits[index]
    current_min = math.min(current_min, benefit.current_productivity_bonus)
    current_max = math.max(current_max, benefit.current_productivity_bonus)
    maximum_min = math.min(maximum_min, benefit.maximum_productivity)
    maximum_max = math.max(maximum_max, benefit.maximum_productivity)
  end
  if current_max * 100 == math.huge or maximum_max * 100 == math.huge then
    add(parent, {type = "label", name = PREFIX .. "live_detail_unavailable",
      caption = {"mir-browser.live-detail-unavailable"}})
    return
  end
  local low, high = string.format("%.6g", current_min * 100), string.format("%.6g", current_max * 100)
  local cap_low, cap_high = string.format("%.6g", maximum_min * 100), string.format("%.6g", maximum_max * 100)
  local caption = low == high and cap_low == cap_high
    and {"mir-browser.productivity-current-cap", low, cap_low}
    or {"mir-browser.productivity-current-cap-range", low, high, cap_low, cap_high}
  add(parent, {type = "label", name = PREFIX .. "productivity_current_cap", caption = caption})
  -- The authored message covers all MIR benefit; mixed native effects may
  -- still grant something beyond recipe productivity.
  if detail.next_level_has_effective_benefit == false and detail.recipe_benefits_only_effects == true then
    add(parent, {type = "label", name = PREFIX .. "no_next_benefit",
      caption = {"mir-browser.no-next-benefit", #benefits}})
  end
end

-- Only the selected presentation is retained, on its native GUI owner. Tags
-- survive a client joining; a module-local last-render cache would not.
-- Decline unsupported/oversized inputs rather than caching a partial match.
local function copy_detail_inputs(value, budget, depth)
  budget.nodes = budget.nodes - 1
  if budget.nodes < 0 or depth > 12 then return nil end
  local kind = type(value)
  if kind == "boolean" or finite_number(value) then return value end
  if kind == "string" then
    budget.bytes = budget.bytes - #value
    return budget.bytes >= 0 and value or nil
  end
  if kind ~= "table" or getmetatable(value) ~= nil then return nil end
  local out, count, numeric, maximum = {}, 0, 0, 0
  for key, child in pairs(value) do
    count = count + 1
    if type(key) == "string" then
      budget.bytes = budget.bytes - #key
      if budget.bytes < 0 then return nil end
    elseif whole_number(key, 1) then
      numeric, maximum = numeric + 1, math.max(maximum, key)
    else return nil end
    out[key] = copy_detail_inputs(child, budget, depth + 1)
    if out[key] == nil then return nil end
  end
  -- Native tags stringify sparse numeric keys. Admit only records or dense
  -- arrays so an exact readback cannot silently change the comparison shape.
  if numeric > 0 and (numeric ~= count or maximum ~= count) then return nil end
  return out
end

local function same_detail_inputs(left, right, budget)
  budget.left = budget.left - 1
  if budget.left < 0 then return false end
  if left == right then return true end
  if type(left) ~= "table" or type(right) ~= "table" or getmetatable(right) ~= nil then return false end
  for key, value in pairs(left) do
    if not same_detail_inputs(value, right[key], budget) then return false end
  end
  for key in pairs(right) do
    budget.left = budget.left - 1
    if budget.left < 0 or left[key] == nil then return false end
  end
  return true
end

local function detail_inputs(player, row, detail, panes, recipes)
  local technology = row and known_technology(player, row.id)
  if not technology then return nil end
  detail = type(detail) == "table" and detail or {}
  local inputs = {
    revision = 1, id = row.id, force = player.force.index, locale = player.locale,
    width = panes.detail_width, height = panes.detail_height,
    title = caption(row, player), native_name = technology.localised_name,
    status = row.status, current = row.current, queued_count = row.queued_count, queue_index = row.queue_index,
    level = row.current_level, cap = row.cap, cap_state = row.cap_state, cap_setting = row.cap_setting,
    effects = detail.effects, effects_complete = detail.effects_complete, cost = detail.cost,
    prerequisites = detail.prerequisites, recipe_benefits = detail.recipe_benefits,
    recipe_benefits_state = detail.recipe_benefits_state,
    next_level_has_effective_benefit = detail.next_level_has_effective_benefit,
    recipe_benefits_only_effects = detail.recipe_benefits_only_effects,
    science_names = {}, prerequisite_names = {}, recipes = {},
    recipe_navigation = type(player.open_factoriopedia_gui) == "function",
  }
  if #recipes == 0 then
    local ok, description = pcall(function() return technology.localised_description end)
    if ok then inputs.description = description end
  end
  local ingredients = type(detail.cost) == "table" and detail.cost.ingredients or nil
  for index, ingredient in ipairs(type(ingredients) == "table" and ingredients or {}) do
    if index > 512 then return nil end
    inputs.science_names[index] = type(ingredient) == "table" and native_item_name(ingredient.name) or false
  end
  for index, id in ipairs(type(detail.prerequisites) == "table" and detail.prerequisites or {}) do
    if index > 512 then return nil end
    inputs.prerequisite_names[index] = native_technology_name(player, id) or false
  end
  for index, recipe in ipairs(recipes) do inputs.recipes[index] = {id = recipe.id, name = recipe.name} end
  return copy_detail_inputs(inputs, {nodes = 4096, bytes = 65536}, 0)
end

local function detail_subtree_present(container, inputs)
  local facts = container[PREFIX .. "research_facts"]
  local heading = valid(facts) and facts[PREFIX .. "detail_heading"]
  if not valid(facts) or facts.type ~= "scroll-pane" or not valid(heading) or heading.type ~= "flow"
      or not valid(heading[PREFIX .. "detail_title"]) or not valid(heading[PREFIX .. "detail_icon"])
      or not valid(facts[PREFIX .. "detail_context"]) or not valid(facts[PREFIX .. "detail_requirements"]) then return false end
  local recipe_parent = inputs.height < 200 and facts or container
  if #inputs.recipes > 0 and not valid(recipe_parent[PREFIX .. "recipe_list"]) then return false end
  if type(inputs.cost) == "table" and type(inputs.cost.ingredients) == "table" and #inputs.cost.ingredients > 0 then
    if not valid(facts[PREFIX .. "science_icons"]) or not valid(facts[PREFIX .. "production_check"])
        or not valid(facts[PREFIX .. "production_results"]) then return false end
  end
  return not (type(inputs.prerequisites) == "table" and #inputs.prerequisites > 0)
    or valid(facts[PREFIX .. "prerequisite_icons"])
end

local function library_section(parent, name, caption, width)
  -- Authored8a3b190d section(): a native divider and restrained spacing,
  -- followed by a short bold heading rather than another paragraph.
  local divider = add(parent, {type = "line", name = PREFIX .. name .. "_divider", direction = "horizontal"})
  divider.style.width = math.max(1, width - 16)
  divider.style.top_margin, divider.style.bottom_margin = library_layout.section_gap, library_layout.control_gap
  local heading = add(parent, {type = "label", name = PREFIX .. name, caption = {caption}})
  heading.style.font, heading.style.bottom_margin = "default-bold", 4
end

local function detail_lines(parent, row, detail, player, recipe_rows)
  if not row then
    add(parent, {type = "label", name = PREFIX .. "detail_empty", caption = {"mir-browser.no-results"}})
    return
  end

  local container = parent
  local width = parent.style and parent.style.maximal_width or 560
  local height = parent.style and parent.style.maximal_height or 220
  recipe_rows = recipe_rows or affected_recipe_rows(player, detail)
  local compact = height < 200
  local recipe_height = #recipe_rows > 0
    and math.min(#recipe_rows * 28 + 8, math.max(32, style_pixels(height * .28))) or 0
  parent = add(container, {type = "scroll-pane", name = PREFIX .. "research_facts",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
  parent.style.width = width
  parent.style.height = recipe_height > 0 and not compact and math.max(60, height - recipe_height - 70) or height
  local heading = add(parent, {type = "flow", name = PREFIX .. "detail_heading", direction = "horizontal"})
  heading.style.width = math.max(1, width - 16)
  local technology = known_technology(player, row.id)
  if technology then
    local icon = add(heading, {type = "sprite", name = PREFIX .. "detail_icon", sprite = "technology/" .. row.id,
      tooltip = technology.localised_name, resize_to_sprite = false})
    if icon.style then
      icon.style.width, icon.style.height = 48, 48
      icon.style.stretch_image_to_widget_size = true
    end
  end
  local title = add(heading, {type = "label", name = PREFIX .. "detail_title", caption = caption(row, player)})
  if title.style then
    title.style.font = "default-large-bold"
    title.style.maximal_width = math.max(80, width - 72)
  end
  library_section(parent, "detail_benefits", "mir-browser.benefits", width)
  if technology and #recipe_rows == 0 then
    local ok, description = pcall(function() return technology.localised_description end)
    if ok and description ~= nil and description ~= "" then
      add(parent, {type = "label", name = PREFIX .. "detail_description", caption = description})
    end
  end
  local other_effects = type(detail) == "table" and detail.effects_complete == false
  local productivity_changes = {}
  local effects = type(detail) == "table" and type(detail.effects) == "table" and detail.effects or {}
  for index, effect in ipairs(effects) do
    local text_value = library_effects.caption(effect)
    if text_value then
      local change = type(effect) == "table" and effect.type == "change-recipe-productivity" and effect.change or nil
      if change == nil or not productivity_changes[change] then
        add(parent, {type = "label", name = PREFIX .. "effect_" .. index, caption = text_value})
      end
      if change ~= nil then productivity_changes[change] = true end
    elseif type(effect) ~= "table" or effect.type ~= "unlock-recipe" then
      other_effects = true
    end
  end
  if other_effects then
    add(parent, {type = "label", name = PREFIX .. "other_effects", caption = {"mir-browser.effect-native-details"}})
  end
  add_recipe_benefits(parent, detail)
  library_section(parent, "detail_requirements", "mir-browser.research-requirements", width)
  local context = add(parent, {type = "flow", name = PREFIX .. "detail_context", direction = "vertical"})
  local status_key = {
    ready = "mir-browser.status-ready",
    complete = "mir-browser.status-complete",
    disabled = "mir-browser.status-disabled",
    locked = "mir-browser.status-locked",
    queued = "mir-browser.status-queued",
    missing = "mir-browser.status-missing"
  }
  add(context, {type = "label", name = PREFIX .. "context_status", caption = {"mir-browser.context-status", {status_key[row.status] or "mir-browser.detail-unavailable"}}})
  if row.current == true then
    add(context, {type = "label", name = PREFIX .. "context_current", caption = {"mir-browser.context-current"}})
  elseif type(row.queued_count) == "number" and row.queued_count > 0 then
    add(context, {type = "label", name = PREFIX .. "context_queued", caption = {"mir-browser.context-queued"}})
  end
  if type(row.queued_count) == "number" and row.queued_count > 0 then
    add(context, {type = "label", name = PREFIX .. "context_queue_count", caption = {"mir-browser.context-queue-count", row.queued_count}})
    if type(row.queue_index) == "number" and row.queue_index > 0 then
      add(context, {type = "label", name = PREFIX .. "context_queue_position", caption = {"mir-browser.context-queue-position", row.queue_index}})
    end
  end
  if row.cap and row.cap > 0 then
    add(parent, {type = "label", name = PREFIX .. "detail_level", caption = {"mir-browser.level-cap", row.current_level or 1, row.cap}})
    add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"mir-browser.cap-finite", row.cap, tostring(row.cap_setting or "?")}})
  else
    local level = add(parent, {type = "label", name = PREFIX .. "detail_level", caption = {"mir-browser.level", row.current_level or 1}})
    if row.cap_state == "unlimited" then
      level.tooltip = {"mir-browser.cap-unlimited"}
    elseif row.cap_state == "unavailable" then
      add(parent, {type = "label", name = PREFIX .. "detail_cap", caption = {"mir-browser.cap-unavailable"}})
    end
  end
  if type(detail) == "table" and detail.cost ~= nil then
    add(parent, {type = "label", name = PREFIX .. "detail_cost", caption = {"mir-browser.research-cost", tostring(type(detail.cost) == "table" and (detail.cost.count or detail.cost[1] or "?") or detail.cost), tostring(research_seconds(detail.cost))}})
    if type(detail.cost) == "table" and type(detail.cost.ingredients) == "table"
        and #detail.cost.ingredients > 0 then
      local science_heading = add(parent, {type = "label", name = PREFIX .. "detail_science", caption = {"mir-browser.science"}})
      if science_heading.style then science_heading.style.font = "default-bold" end
      local science = add(parent, {type = "table", name = PREFIX .. "science_icons",
        column_count = math.max(1, math.min(8, style_pixels((width - 16) / 40)))})
      science.style.width = math.max(1, width - 16)
      for index, ingredient in ipairs(detail.cost.ingredients) do
        if type(ingredient) == "table" then
          local name = native_item_name(ingredient.name)
          local text = {"mir-browser.science-ingredient", name or tostring(ingredient.name or "?"), tostring(ingredient.amount or "?")}
          if name then
            local icon = add(science, {type = "sprite", name = PREFIX .. "science_" .. index,
              sprite = "item/" .. ingredient.name, tooltip = text, resize_to_sprite = false})
            icon.style.width, icon.style.height = 32, 32
            icon.style.stretch_image_to_widget_size = true
          else
            add(science, {type = "label", name = PREFIX .. "science_" .. index, caption = text})
          end
        end
      end
    end
  end
  if type(detail) == "table" and type(detail.prerequisites) == "table" and #detail.prerequisites > 0 then
    local prerequisite_heading = add(parent, {type = "label", name = PREFIX .. "detail_prerequisites", caption = {"mir-browser.prerequisites"}})
    if prerequisite_heading.style then prerequisite_heading.style.font = "default-bold" end
    local prerequisites = add(parent, {type = "table", name = PREFIX .. "prerequisite_icons",
      column_count = math.max(1, math.min(8, style_pixels((width - 16) / 40)))})
    prerequisites.style.width = math.max(1, width - 16)
    for index, prerequisite in ipairs(detail.prerequisites) do
      local name = native_technology_name(player, prerequisite)
      if name then
        local icon = add(prerequisites, {type = "sprite", name = PREFIX .. "prerequisite_" .. index,
          sprite = "technology/" .. prerequisite, tooltip = name, resize_to_sprite = false})
        icon.style.width, icon.style.height = 32, 32
        icon.style.stretch_image_to_widget_size = true
      else
        add(prerequisites, {type = "label", name = PREFIX .. "prerequisite_" .. index, caption = tostring(prerequisite)})
      end
    end
  end
  if type(detail) == "table" and type(detail.cost) == "table"
      and type(detail.cost.ingredients) == "table" and #detail.cost.ingredients > 0 then
    add(parent, {type = "button", name = PREFIX .. "production_check",
      caption = {"mir-browser.production-check"}})
    add(parent, {type = "flow", name = PREFIX .. "production_results", direction = "vertical"})
  end
  if #recipe_rows > 0 then
    local recipe_parent = compact and parent or container
    local recipe_heading = add(recipe_parent, {type = "label", name = PREFIX .. "detail_affected_recipes",
      caption = {"mir-browser.affected-recipes"}})
    if recipe_heading.style then recipe_heading.style.font = "default-bold" end
    local items = {}
    for index, recipe in ipairs(recipe_rows) do
      items[index] = {"", "[img=recipe/" .. recipe.id .. "] ", recipe.name}
    end
    local recipe_navigation = type(player.open_factoriopedia_gui) == "function"
    local recipe_hint = recipe_navigation and "mir-browser.recipe-select-hint" or "mir-browser.recipe-list-only-hint"
    local list = add(recipe_parent, {type = "list-box", name = PREFIX .. "recipe_list", items = items,
      selected_index = 0, tooltip = {recipe_hint}})
    if list.style then
      list.style.width = math.max(1, width - 16)
      list.style.height = recipe_height
    end
    if not recipe_navigation then
      add(recipe_parent, {type = "label", name = PREFIX .. "recipe_hint", caption = {recipe_hint}})
    end
  end
end

local function research_page(frame)
  local tabs = frame and frame[PREFIX .. "tabs"]
  return valid(tabs) and tabs[PREFIX .. "research_page"] or nil
end

local function research_filters(frame)
  local page = research_page(frame)
  return valid(page) and page[PREFIX .. "filters"] or nil
end

local function research_filter_control(filters, name)
  if not valid(filters) then return nil end
  if name == "query" then return filters[PREFIX .. "query"] end
  local grid = filters[PREFIX .. "filter_grid"]
  local field = valid(grid) and grid[PREFIX .. name .. "_field"]
  return valid(field) and field[PREFIX .. name] or nil
end

local function research_filters_ready(filters)
  local grid = valid(filters) and filters[PREFIX .. "filter_grid"]
  local query = research_filter_control(filters, "query")
  if not valid(filters) or filters.type ~= "flow" or filters.direction ~= "vertical"
      or not valid(grid) or grid.type ~= "table"
      or not valid(query) or query.type ~= "textfield" then return false end
  local columns = grid.column_count
  if columns ~= 1 and columns ~= 2 and columns ~= 3 and columns ~= 5 then return false end
  for _, name in ipairs({"family", "status", "mode", "sort", "visibility"}) do
    local field = grid[PREFIX .. name .. "_field"]
    local control = research_filter_control(filters, name)
    if not valid(field) or field.type ~= "flow" or field.direction ~= "vertical"
        or not valid(field[PREFIX .. name .. "_label"])
        or not valid(control) or control.type ~= "drop-down" then return false end
  end
  return true
end

local function tab_content(frame, tab)
  if tab == "research" then
    local page = research_page(frame)
    return valid(page) and page[PREFIX .. "research_content"] or nil
  end
  local tabs = frame and frame[PREFIX .. "tabs"]
  return valid(tabs) and tabs[PREFIX .. tab .. "_content"] or nil
end

local function research_content_type(player, view)
  local width, height = library_layout.frame_size(player.display_resolution, player.display_scale, view.geometry)
  local pairs_per_row = library_layout.filter_layout(width)
  local content_width = style_pixels(width - 48)
  local content_height = style_pixels(library_layout.content_height(height, pairs_per_row))
  return library_layout.split_sizes(content_width, content_height).columns == 1 and "scroll-pane" or "table"
end

local function frame_layout_ready(frame, player, view)
  local title = frame and frame[PREFIX .. "title"]
  local tabs = frame and frame[PREFIX .. "tabs"]
  local filters = research_filters(frame)
  local research = tab_content(frame, "research")
  local settings = valid(tabs) and tabs[PREFIX .. "settings_content"] or nil
  return valid(title) and valid(title[PREFIX .. "layout_smaller"])
    and valid(title[PREFIX .. "layout_larger"]) and valid(title[PREFIX .. "layout_reset"])
    and valid(title[PREFIX .. "close"])
    and research_filters_ready(filters)
    and valid(research) and research.type == research_content_type(player, view)
    and valid(settings) and valid(settings.type == "scroll-pane" and settings or nil)
end

-- Native list widgets own their actual scroll/interaction state. Compare the
-- bounded LocalisedString rows before assigning items; a no-op refresh should
-- neither replace a widget nor repopulate it. No durable mirror is needed.
local function same_list_caption(left, right, budget)
  if budget.left == 0 then return false end
  budget.left = budget.left - 1
  if left == right then return true end
  if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
  for index = 1, #left do
    if not same_list_caption(left[index], right[index], budget) then return false end
  end
  return true
end

local function update_list_items(list, items, selected_index)
  local previous = list.items
  local changed = type(previous) ~= "table" or #previous ~= #items
  if not changed then
    local budget = {left = 256}
    for index = 1, #items do
      budget.left = 256
      if not same_list_caption(previous[index], items[index], budget) then changed = true; break end
    end
  end
  if changed then list.items = items end
  local selection_changed = list.selected_index ~= selected_index
  if selection_changed then list.selected_index = selected_index end
  return changed, selection_changed
end

local function update_research_content(content, player, view, context, translations, localized_search_pending)
  if not valid(content) then return end
  -- Availability is a different projection in the same body. Clear it only
  -- at that boundary; ordinary Research refreshes retain their widgets.
  if valid(content[PREFIX .. "availability_empty"]) or valid(content[PREFIX .. "availability_1"])
      or valid(content[PREFIX .. "actions"]) or valid(content[PREFIX .. "results"]) then
    content.clear()
  end

  local rows = rows_for(player, view, context, translations)
  local item_labels = {}
  for index, row in ipairs(rows) do
    local text = caption(row, player)
    item_labels[index] = known_technology(player, row.id)
      and {"", "[img=technology/" .. row.id .. "] ", text} or text
  end
  local selected_index = row_index(rows, view.selected) or 0
  -- Filter changes choose a useful visible subject. Keep explicitly hidden
  -- personal focus and stale private-credit selections inert, as before.
  local reserved_selection = private_credit_id(view.selected) or view.hidden[view.selected] == true
  -- A returning tab can initially contain only the first translated matches.
  -- Keep personal focus inert until the localized search can decide whether
  -- that research is absent; a partial batch must not replace it permanently.
  local waiting_for_selection = view.selected ~= nil and localized_search_pending
  if selected_index == 0 and #rows > 0 and not reserved_selection and not waiting_for_selection then
    selected_index, view.selected = 1, rows[1].id
  end
  local width = content.style and content.style.maximal_width or 592
  local height = content.style and content.style.maximal_height or 220
  -- The list header now belongs to its own pane. The selected detail can
  -- use the full body instead of reserving a toolbar row above both panes.
  local panes = library_layout.split_sizes(width, height + 36)
  local selected = selected_index > 0 and rows[selected_index] or nil
  if selected then
    view.selected = selected.id
    selected.hidden = view.hidden[selected.id] == true
  end

  local list_pane = content[PREFIX .. "list_pane"]
  if not valid(list_pane) then
    list_pane = add(content, {type = "flow", name = PREFIX .. "list_pane", direction = "vertical"})
    add(list_pane, {type = "label", name = PREFIX .. "count"})
  end
  list_pane.style.width = panes.list_width
  local action_columns = panes.list_width < 300 and 2 or 5
  local action_rows = math.ceil((view.visibility == 2 and 5 or 4) / action_columns)
  local header_height = 28 + action_rows * 32
  list_pane.style.height = math.max(header_height + 76, panes.list_height)
  local actions = list_pane[PREFIX .. "actions"]
  if valid(actions) and (actions.type ~= "table" or actions.column_count ~= action_columns) then
    local previous_results = list_pane[PREFIX .. "results"]
    if valid(previous_results) then previous_results.destroy() end
    actions.destroy()
    actions = nil
  end
  if not valid(actions) then
    actions = add(list_pane, {type = "table", name = PREFIX .. "actions", column_count = action_columns})
    add(actions, {type = "sprite-button", name = PREFIX .. "hide", style = "tool_button"})
    add(actions, {type = "button", name = PREFIX .. "inspect_settings", caption = {"mir-browser.settings"},
      tooltip = {"mir-browser.inspect-settings"}})
    add(actions, {type = "sprite-button", name = PREFIX .. "open_native", style = "tool_button",
      sprite = "utility/side_menu_technology_icon", tooltip = {"mir-browser.native-queue-guidance"}})
    add(actions, {type = "sprite-button", name = PREFIX .. "close", style = "tool_button",
      sprite = "utility/close", tooltip = {"mir-browser.close"}})
  end
  actions.style.width = panes.list_width
  actions.style.horizontal_spacing, actions.style.vertical_spacing = 4, 4
  actions[PREFIX .. "inspect_settings"].style.minimal_width = 0
  actions[PREFIX .. "inspect_settings"].style.maximal_width = math.max(1, panes.list_width - (action_columns == 2 and 40 or 132))
  local count = list_pane[PREFIX .. "count"]
  count.caption = {"mir-browser.count", #rows}
  local hide = actions[PREFIX .. "hide"]
  hide.sprite, hide.enabled = selected and selected.hidden and "utility/expand" or "utility/collapse", selected ~= nil
  hide.tooltip = {"mir-browser." .. (selected and selected.hidden and "show-tooltip" or "hide-tooltip")}
  actions[PREFIX .. "inspect_settings"].enabled = selected ~= nil and type(selected.cap_setting) == "string"
  actions[PREFIX .. "open_native"].enabled = selected ~= nil
  local show_hidden = actions[PREFIX .. "show_hidden"]
  if view.visibility == 2 and not valid(show_hidden) then
    add(actions, {type = "sprite-button", name = PREFIX .. "show_hidden", style = "tool_button",
      sprite = "utility/reset", tooltip = {"mir-browser.show-hidden"}})
  elseif view.visibility ~= 2 and valid(show_hidden) then
    show_hidden.destroy()
  end

  local results = list_pane[PREFIX .. "results"]
  local created = not valid(results)
  if created then
    results = add(list_pane, {type = "list-box", name = PREFIX .. "results", items = item_labels, selected_index = selected_index})
  end
  local items_changed, selection_changed = update_list_items(results, item_labels, selected_index)
  if results.style then results.style.width, results.style.height = panes.list_width, math.max(76, panes.list_height - header_height) end
  if created and view.scroll and view.scroll <= #item_labels and type(results.scroll_to_item) == "function" then
    results.scroll_to_item(view.scroll, "top-third")
  elseif (items_changed or selection_changed) and selected_index > 0 and type(results.scroll_to_item) == "function" then
    results.scroll_to_item(selected_index, "in-view")
  end
  local detail = selected and selected_detail(player, view, context, translations) or nil
  local detail_box = content[PREFIX .. "detail"]
  if not valid(detail_box) then
    detail_box = add(content, {type = "scroll-pane", name = PREFIX .. "detail",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
  end
  if detail_box.style then
    detail_box.style.width, detail_box.style.height = panes.detail_width, panes.detail_height
    detail_box.style.maximal_width = panes.detail_width
  end
  local recipes = selected and affected_recipe_rows(player, detail) or {}
  local inputs = detail_inputs(player, selected, detail, panes, recipes)
  local tags = detail_box.tags or {}
  if not (inputs and detail_subtree_present(detail_box, inputs)
      and same_detail_inputs(inputs, tags.mir_detail_inputs, {left = 8192})) then
    detail_box.clear()
    detail_lines(detail_box, selected, detail, player, recipes)
    tags.mir_detail_inputs = inputs
    detail_box.tags = tags
  end
end

local function setting_value(startup, name, fallback)
  local ok, value = pcall(function()
    local entry = startup and startup[name]
    return entry and entry.value
  end)
  if ok and value ~= nil then return value end
  return fallback
end

local function setting_display(name, value)
  if type(value) == "boolean" then return {"mir-browser.setting-" .. (value and "on" or "off")} end
  if type(value) == "number" and value == 0 and type(name) == "string"
      and name:find("%-max%-level%-", 1) then
    return {"mir-browser.setting-unlimited"}
  end
  if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
    local compact = string.format("%.6g", value)
    return tonumber(compact) == value and compact or "≈ " .. compact
  end
  local shown = tostring(value)
  if #shown > 120 then
    -- Keep the authored compact preview without splitting a UTF-8 character.
    -- Configuration and profile export continue to use the original value.
    local last = 117
    while last > 0 do
      local next_byte = string.byte(shown, last + 1)
      if next_byte < 128 or next_byte > 191 then break end
      last = last - 1
    end
    return string.sub(shown, 1, last) .. "..."
  end
  return shown
end

local SETTING_FIELD_CAPTIONS = {
  enabled = "setting-enable", base_cost = "setting-cost-base",
  linear_increment = "setting-cost-linear-increment", growth_factor = "setting-cost-growth",
  max_level = "setting-max-level", research_time = "setting-research-time",
}

local function setting_catalogue()
  -- Startup settings and their imported-profile precedence cannot change
  -- during a running session. Build the bounded grouping once, then reuse it
  -- for search keystrokes, selection changes and window resizing.
  if setting_groups_cache ~= nil then return setting_groups_cache end
  local ok, names = pcall(settings_catalog.registered_names)
  if not ok or type(names) ~= "table" or #names > MAX_SETTING_DESCRIPTORS then return nil end

  local prototypes, by_name = setting_prototypes_by_name(), {}
  if prototypes == nil then return nil end

  local startup = settings and settings.startup or nil
  local effective_ok, effective = pcall(settings_catalog.effective_values, startup, helpers)
  if not effective_ok or type(effective) ~= "table" then return nil end

  local imported = nil
  local import_name = settings_catalog.import_setting_name
  local imported_text = setting_value(startup, import_name, "")
  if type(imported_text) == "string" and imported_text ~= "" then
    local decoded_ok, profile = pcall(profile_codec.decode, imported_text, helpers)
    if decoded_ok and type(profile) == "table" and type(profile.settings) == "table" then imported = profile.settings end
  end

  local controlled_families = {}
  for _, declaration in ipairs(authored_declarations()) do controlled_families[declaration.family] = true end
  local groups, ordered = {}, {}
  for index, name in ipairs(names) do
    if type(name) ~= "string" or name == "" or by_name[name] then return nil end
    by_name[name] = true
    local spec = settings_catalog.spec(name)
    if type(spec) ~= "table" then return nil end
    local stream = type(spec.stream) == "table" and spec.stream or nil
    local scope = stream and "research" or "options"
    local key = stream and type(stream.key) == "string" and stream.key or name
    local group = groups[key]
    if group == nil then
      local title = stream and stream.technology_locale or nil
      if type(title) == "string" then title = {title} end
      group = {key = key, scope = scope, title = title or (prototypes[name] and prototypes[name].localised_name) or name,
        fields = {}, search = key .. " " .. name}
      group.externally_supplied = stream and stream.native_continuation == true and not controlled_families[key]
        and type(catalogue.externally_supplied_continuation) == "function"
        and catalogue.externally_supplied_continuation(stream.continuation_id) or false
      groups[key], ordered[#ordered + 1] = group, group
    end
    local default = spec.default_value
    local direct = setting_value(startup, name, default)
    local source = "direct"
    if imported and startup and startup[name] and imported[name] ~= nil then
      local accepted = settings_catalog.validate_value(name, imported[name])
      if accepted then source = "mirset1" end
    end
    local field_caption = stream and SETTING_FIELD_CAPTIONS[spec.key]
    if stream and spec.key == "effect_percent" then
      -- Preserve the authored percentage/count distinction. Continuations
      -- use the original generic label; their setting description has units.
      field_caption = "setting-effect-per-level"
        .. (not stream.native_continuation and spec.type == "double-setting" and "-percent" or "")
    end
    group.fields[#group.fields + 1] = {
      name = name,
      caption = field_caption and {"mir-browser." .. field_caption}
        or (prototypes[name] and prototypes[name].localised_name) or name,
      description = prototypes[name] and prototypes[name].localised_description or nil,
      effective = effective[name], direct = direct, default = default, source = source,
      order = spec.field_index or index
    }
    group.search = group.search .. " " .. name
  end
  if import_name and not by_name[import_name] and prototypes[import_name] then
    local group = {key = import_name, scope = "options", title = prototypes[import_name].localised_name or import_name,
      search = import_name, fields = {{name = import_name, caption = prototypes[import_name].localised_name or import_name,
        description = prototypes[import_name].localised_description, effective = setting_value(startup, import_name, ""),
        direct = setting_value(startup, import_name, ""), default = prototypes[import_name].default_value, source = "direct", order = 1}}}
    groups[import_name], ordered[#ordered + 1] = group, group
  end
  for _, group in ipairs(ordered) do
    table.sort(group.fields, function(left, right)
      if left.order ~= right.order then return left.order < right.order end
      return left.name < right.name
    end)
  end
  table.sort(ordered, function(left, right) return left.key < right.key end)
  setting_groups_cache = ordered
  return setting_groups_cache
end

local function setting_search_matches(group, query, translations)
  if query == "" then return true end
  local haystack = group.search
  if type(translations) == "table" then
    for _, field in ipairs(group.fields) do
      local label = translations[SETTING_TRANSLATION_PREFIX .. field.name]
      if type(label) == "string" and label ~= "" then haystack = haystack .. " " .. label end
    end
  end
  haystack = haystack:lower():gsub("[-_]", " ")
  return haystack:find(query:lower():gsub("[-_]", " "), 1, true) ~= nil
end

local function settings_group_key(setting_name)
  if type(setting_name) ~= "string" then return nil end
  local ok, spec = pcall(settings_catalog.spec, setting_name)
  if not ok or type(spec) ~= "table" then return setting_name end
  local stream = type(spec.stream) == "table" and spec.stream or nil
  return stream and type(stream.key) == "string" and stream.key or setting_name
end

local function update_settings_content(content, view, preserve_query, translations)
  if not valid(content) then return end
  local width = content.style and (content.style.maximal_width or content.style.width) or 592
  local available_height = content.style and (content.style.maximal_height or content.style.height) or 220
  local toolbar_columns = width < 380 and 1 or (width < 700 and 2 or 4)
  local toolbar = content[PREFIX .. "settings_toolbar"]
  if not valid(content[PREFIX .. "settings_search_label"])
      or (valid(toolbar) and (toolbar.type ~= "table" or toolbar.column_count ~= toolbar_columns)) then
    -- A recreated toolbar must precede the query and panes, including when
    -- an older open GUI still contains the former horizontal flow.
    content.clear()
    toolbar = nil
  end
  if not valid(content[PREFIX .. "settings_search_label"]) then
    add(content, {type = "label", name = PREFIX .. "settings_search_label", caption = {"mir-browser.search-settings"}})
  end
  local query = content[PREFIX .. "settings_query"]
  if not valid(query) then
    query = add(content, {type = "textfield", name = PREFIX .. "settings_query", text = view.settings_query,
      tooltip = {"mir-browser.search-settings"}})
  elseif not preserve_query then
    query.text = view.settings_query
  end
  if not valid(toolbar) then
    toolbar = add(content, {type = "table", name = PREFIX .. "settings_toolbar", column_count = toolbar_columns})
    add(toolbar, {type = "button", name = PREFIX .. "settings_research", caption = {"mir-browser.settings-scope-research"}})
    add(toolbar, {type = "button", name = PREFIX .. "settings_options", caption = {"mir-browser.settings-scope-options"}})
    if support_exports then
      add(toolbar, {type = "button", name = PREFIX .. "export_settings", caption = {"mir-browser.export-settings"},
        tooltip = {"mir-browser.export-settings-tooltip"}})
      add(toolbar, {type = "button", name = PREFIX .. "export_compact", caption = {"mir-browser.export-compact"},
        tooltip = {"mir-browser.export-compact-tooltip"}})
    end
  end
  if toolbar.style then
    toolbar.style.horizontal_spacing, toolbar.style.vertical_spacing = 8, 4
    toolbar.style.width, toolbar.style.maximal_width = width - 24, width - 24
  end
  for _, name in ipairs({"settings_research", "settings_options", "export_settings", "export_compact"}) do
    local button = toolbar[PREFIX .. name]
    if valid(button) and button.style then
      button.style.width = style_pixels((width - 24 - (toolbar_columns - 1) * 8) / toolbar_columns)
      button.style.height = 28
      if name == "settings_research" or name == "settings_options" then
        button.tooltip = button.caption
        button.toggled = view.settings_scope == (name == "settings_research" and "research" or "options")
      end
    end
  end
  if query.style then query.style.width = math.max(1, width - 24) end
  local toolbar_rows = math.ceil((support_exports and 4 or 2) / toolbar_columns)
  local dynamic_height = math.max(80, available_height - 84 - (toolbar_rows - 1) * 32)
  local panes = library_layout.split_sizes(width, dynamic_height)
  -- The outer page owns overflow. A one-column table must contain both
  -- panes plus its two heading rows, even at the minimum window height.
  if panes.columns == 1 then
    dynamic_height = math.max(dynamic_height, panes.list_height + panes.detail_height + 48)
  end
  local dynamic = content[PREFIX .. "settings_dynamic"]
  if valid(dynamic) and dynamic.column_count ~= panes.columns then
    dynamic.destroy()
    dynamic = nil
  end
  if not valid(dynamic) then
    dynamic = add(content, {type = "table", name = PREFIX .. "settings_dynamic", column_count = panes.columns})
  end
  if dynamic.style and content.style then
    dynamic.style.width = width
    dynamic.style.maximal_width = width
    dynamic.style.height, dynamic.style.maximal_height = dynamic_height, dynamic_height
  end
  local groups = setting_catalogue()
  if groups == nil then
    dynamic.clear()
    add(dynamic, {type = "label", name = PREFIX .. "settings_unavailable", caption = {"mir-browser.detail-unavailable", "settings"}})
    return
  end
  local visible, items = {}, {}
  for _, group in ipairs(groups) do
    if group.scope == view.settings_scope and setting_search_matches(group, view.settings_query, translations) then
      visible[#visible + 1], items[#items + 1] = group, group.title
    end
  end
  local selected_index = 0
  for index, group in ipairs(visible) do if group.key == view.setting_selected then selected_index = index; break end end
  if selected_index == 0 and #visible > 0 then
    selected_index, view.setting_selected = 1, visible[1].key
  end
  local list, detail = dynamic[PREFIX .. "settings_list"], dynamic[PREFIX .. "settings_detail"]
  local created = not valid(list) or not valid(detail) or not valid(dynamic[PREFIX .. "settings_count"])
    or not valid(dynamic[PREFIX .. "settings_scope_label"])
  if created then
    dynamic.clear()
    add(dynamic, {type = "label", name = PREFIX .. "settings_count"})
    add(dynamic, {type = "label", name = PREFIX .. "settings_scope_label"})
    list = add(dynamic, {type = "list-box", name = PREFIX .. "settings_list", items = items, selected_index = selected_index})
    detail = add(dynamic, {type = "scroll-pane", name = PREFIX .. "settings_detail",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
  else detail.clear() end
  dynamic[PREFIX .. "settings_count"].caption = {"mir-browser.settings-count", #visible}
  dynamic[PREFIX .. "settings_scope_label"].caption = {"mir-browser.settings-scope-" .. view.settings_scope}
  dynamic[PREFIX .. "settings_count"].style.width = panes.list_width
  dynamic[PREFIX .. "settings_scope_label"].style.width = panes.detail_width
  local items_changed, selection_changed = update_list_items(list, items, selected_index)
  if list.style then list.style.width, list.style.height = panes.list_width, panes.list_height end
  if (created or items_changed or selection_changed) and selected_index > 0 and type(list.scroll_to_item) == "function" then
    list.scroll_to_item(selected_index, created and "top-third" or "in-view")
  end
  if detail.style then
    detail.style.width, detail.style.height = panes.detail_width, panes.detail_height
    detail.style.maximal_width = panes.detail_width
  end
  local function setting_label(spec, parent, width)
    local label = add(parent or detail, spec)
    if valid(label) and label.style then
      label.style.single_line = false
      label.style.maximal_width = math.max(1, width or panes.detail_width - 16)
    end
    return label
  end
  local selected = visible[selected_index]
  if selected == nil then
    setting_label({type = "label", name = PREFIX .. "settings_empty", caption = {"mir-browser.settings-empty"}})
    return
  end
  local title = setting_label({type = "label", name = PREFIX .. "settings_title", caption = selected.title})
  title.style.font = "default-large-bold"
  setting_label({type = "label", name = PREFIX .. "settings_scope", caption = {"mir-browser.scope-startup"}})
  if selected.externally_supplied then
    setting_label({type = "label", name = PREFIX .. "settings_external", caption = {"mir-browser.settings-external-owner"}})
  end
  library_section(detail, "settings_effective", "mir-browser.effective-values", panes.detail_width)
  local fields = add(detail, {type = "table", name = PREFIX .. "settings_fields", column_count = 2})
  fields.style.width = math.max(1, panes.detail_width - 16)
  fields.style.horizontal_spacing, fields.style.vertical_spacing = 12, 10
  local field_width = math.max(1, style_pixels((panes.detail_width - 40) * .55))
  local value_width = math.max(1, panes.detail_width - 40 - field_width)
  local source = "default"
  for index, field in ipairs(selected.fields) do
    local name = PREFIX .. "setting_" .. index
    local label = setting_label({type = "label", name = name .. "_name", caption = field.caption,
      tooltip = field.description}, fields, field_width)
    label.style.font = "default-semibold"
    local display = setting_display(field.name, field.effective)
    if field.default ~= nil and field.effective ~= field.default then
      display = {"mir-browser.setting-with-default", display, setting_display(field.name, field.default)}
    end
    setting_label({type = "label", name = name .. "_value", caption = display,
      tooltip = {"mir-browser.setting-provenance", setting_display(field.name, field.direct),
        setting_display(field.name, field.default), {"mir-browser.source-" .. field.source}}}, fields, value_width)
    if field.source == "mirset1" then
      source = "mirset1"
      setting_label({type = "label", name = name .. "_profile_marker", caption = {"mir-browser.profile-override"}}, fields, field_width)
      setting_label({type = "label", name = name .. "_source", caption = {"mir-browser.source-mirset1"}}, fields, value_width)
    elseif source ~= "mirset1" and field.source == "direct" then
      source = "direct"
    end
  end
  library_section(detail, "settings_source", "mir-browser.configuration-source", panes.detail_width)
  setting_label({type = "label", name = PREFIX .. "settings_source_summary", caption = {"mir-browser.source-" .. source}})
end

local function queue_name(entry)
  if type(entry) == "string" then return technology_id(entry) end
  local ok, name = pcall(function() return entry and entry.name end)
  return ok and technology_id(name) or nil
end

local function queue_entries(force)
  local ok, queue = pcall(function() return force and force.research_queue end)
  if not ok or queue == nil then return {} end
  local result = {}
  local complete = pcall(function()
    for index, entry in ipairs(queue) do
      if index > MAX_PAGE then error("MIR Library queue limit") end
      local id = queue_name(entry)
      if id and not private_credit_id(id) then result[#result + 1] = id end
    end
  end)
  return complete and result or {}
end

local function update_queue_content(content, player, view)
  if not valid(content) then return end
  local list = content[PREFIX .. "queue_list"]
  if not valid(list) or not valid(content[PREFIX .. "queue_heading"]) then
    content.clear()
    add(content, {type = "label", name = PREFIX .. "queue_guidance", caption = {"mir-browser.native-queue-guidance"}})
    add(content, {type = "button", name = PREFIX .. "queue_open_native", caption = {"mir-browser.open-research"}})
    add(content, {type = "label", name = PREFIX .. "queue_heading", caption = {"mir-browser.queue"}})
    list = add(content, {type = "list-box", name = PREFIX .. "queue_list", items = {}})
    add(content, {type = "label", name = PREFIX .. "queue_empty", caption = {"mir-browser.queue-empty"}})
  end
  local width, height = library_layout.frame_size(player.display_resolution, player.display_scale, view.geometry)
  local available_width = math.max(1, width - 64)
  list.style.width = available_width
  list.style.height = math.max(48, library_layout.tab_content_height(height) - 130)
  local guidance = content[PREFIX .. "queue_guidance"]
  guidance.style.single_line, guidance.style.maximal_width = false, available_width
  local ids, items = queue_entries(player.force), {}
  local context = DISCOVERY_TREE and context_for(player.force) or nil
  for index, id in ipairs(ids) do
    local technology = known_technology(player, id)
    local name
    if DISCOVERY_TREE and not library_model.technology_visible(technology, id, context) then
      name = {"mir-browser.undiscovered-research"}
    else name = technology and technology.localised_name or id end
    items[index] = {"", tostring(index) .. ". ", name}
  end
  local selected_index = 0
  for index, id in ipairs(ids) do if id == view.selected then selected_index = index; break end end
  update_list_items(list, items, selected_index)
  list.visible = #items > 0
  content[PREFIX .. "queue_empty"].visible = #items == 0
end

local function update_availability_content(content, player, view)
  if not valid(content) then return end
  content.clear()
  -- This bounded view has no compiler ledger and no native catalogue pass. It
  -- presents only the authored terminal explanations selected by exact active
  -- mod and named native-owner facts.
  local active_mods = script and script.active_mods or {}
  local effective_streams = type(effective_configuration) == "table" and effective_configuration.streams or nil
  local rows = availability.rows(active_mods, target, player and player.force, view and view.query, effective_streams)
  if #rows == 0 then
    add(content, {type = "label", name = PREFIX .. "availability_empty", caption = {"mir-browser.availability-empty"}})
    return
  end
  for index, row in ipairs(rows) do
    add(content, {
      type = "label",
      name = PREFIX .. "availability_" .. index,
      caption = {"mir-browser.availability-entry",
        {"technology-name.more-infinite-research." .. row.family},
        {"mir-browser.availability-" .. row.reason}}
    })
  end
end

local function report_options(player, view)
  local rows
  if view.report_omissions then
    local active_mods = script and script.active_mods or mods or {}
    local streams = type(effective_configuration) == "table" and effective_configuration.streams or nil
    rows = availability.rows(active_mods, target, player.force, nil, streams)
  end
  return {report_settings = view.report_settings, report_omissions = view.report_omissions, availability_rows = rows}
end

local function help_tools(content)
  local panes = valid(content) and content[PREFIX .. "help_panes"]
  return valid(panes) and panes[PREFIX .. "help_tools"] or nil
end

local function report_panel(content)
  local panes = valid(content) and content[PREFIX .. "help_panes"]
  return valid(panes) and panes[PREFIX .. "report_panel"] or nil
end

local function update_report_preview(content, player, view)
  local panel = report_panel(content)
  local preview = valid(panel) and panel[PREFIX .. "report_preview"]
  if not valid(preview) then return end
  local result, err = diagnostics.preview(player.index, view.selected, report_options(player, view))
  preview.text = result or ("Diagnostic preview unavailable: " .. tostring(err))
end

local function update_help_content(content, player, view)
  if not valid(content) then return end
  local width, height = library_layout.frame_size(player.display_resolution, player.display_scale, view.geometry)
  local sizes = library_layout.split_sizes(math.max(1, width - 48), library_layout.tab_content_height(height))
  local tools, panel = help_tools(content), report_panel(content)
  local settings_box = valid(tools) and tools[PREFIX .. "report_settings"]
  local omissions_box = valid(tools) and tools[PREFIX .. "report_omissions"]
  local preview = valid(panel) and panel[PREFIX .. "report_preview"]
  local complete = valid(tools) and valid(panel) and valid(tools[PREFIX .. "help_versions"])
    and (not diagnostics or (valid(settings_box) and settings_box.type == "checkbox"
      and valid(omissions_box) and omissions_box.type == "checkbox" and valid(preview)
      and preview.type == "text-box" and valid(panel[PREFIX .. "report_select"])
      and valid(tools[PREFIX .. "report_refresh"])))
  if not complete then
    content.clear()
    local panes = add(content, {type = "flow", name = PREFIX .. "help_panes", direction = sizes.columns == 1 and "vertical" or "horizontal"})
    tools = add(panes, {type = "scroll-pane", name = PREFIX .. "help_tools", direction = "vertical"})
    tools.horizontal_scroll_policy = "never"
    panel = add(panes, {type = "flow", name = PREFIX .. "report_panel", direction = "vertical"})
    library_section(tools, "help_installation", "mir-browser.debug-installation", sizes.list_width)
    local active_mods = script and script.active_mods or {}
    add(tools, {type = "label", name = PREFIX .. "help_versions", caption = {"mir-browser.debug-versions",
      active_mods.base or "?", active_mods["more-infinite-research"] or "?"}})
    if diagnostics then
      add(tools, {type = "button", name = PREFIX .. "report_refresh", caption = {"mir-browser.debug-refresh"}})
      library_section(tools, "help_report_options", "mir-browser.report-options", sizes.list_width)
      for _, option in ipairs({"report_settings", "report_omissions"}) do
        add(tools, {type = "checkbox", name = PREFIX .. option, state = view[option],
          caption = {"mir-browser." .. option:gsub("_", "-")}})
      end
      library_section(panel, "help_preview", "mir-browser.report-preview", sizes.detail_width)
      preview = add(panel, {type = "text-box", name = PREFIX .. "report_preview", text = "",
        tooltip = {"mir-browser.report-preview"}})
      preview.read_only, preview.word_wrap = true, true
      add(panel, {type = "button", name = PREFIX .. "report_select", caption = {"mir-browser.report-select"}})
      add(panel, {type = "button", name = PREFIX .. "export_diagnostics", caption = {"mir-browser.export-diagnostics"}})
      add(panel, {type = "label", name = PREFIX .. "report_local", caption = {"mir-browser.report-local"}})
    end
    library_section(tools, "help_configuration", "mir-browser.configuration", sizes.list_width)
    add(tools, {type = "label", name = PREFIX .. "help_profile", caption = {"mir-browser.profile-purpose"}})
    if support_exports then
      add(tools, {type = "button", name = PREFIX .. "export_settings", caption = {"mir-browser.export-settings"},
        tooltip = {"mir-browser.export-settings-tooltip"}})
    end
    library_section(tools, "help_layout", "mir-browser.layout", sizes.list_width)
    add(tools, {type = "button", name = PREFIX .. "layout_reset", caption = {"mir-browser.reset-layout"},
      tooltip = {"mir-browser.layout-reset"}})
    library_section(tools, "help_startup_crash", "mir-browser.startup-crash", sizes.list_width)
    -- The old standalone preview collector no longer ships. Show the current
    -- report/log boundary rather than restoring obsolete instructions.
    add(tools, {type = "label", name = PREFIX .. "help_startup_report", caption = {"mir-browser.export-diagnostics-tooltip"}})
    if diagnostics then update_report_preview(content, player, view) end
  elseif diagnostics and (settings_box.state ~= view.report_settings or omissions_box.state ~= view.report_omissions) then
    settings_box.state, omissions_box.state = view.report_settings, view.report_omissions
    update_report_preview(content, player, view)
  end
  -- Adopt an already-open pane from the preceding layout without replacing
  -- its selected report text or exporting/re-encoding a fresh snapshot.
  local old_privacy = panel[PREFIX .. "export_privacy"]
  if valid(old_privacy) then old_privacy.destroy() end
  local local_only, export = panel[PREFIX .. "report_local"], panel[PREFIX .. "export_diagnostics"]
  if valid(local_only) then local_only.tooltip = {"mir-browser.export-sharing-guidance"} end
  if valid(export) then
    export.tooltip = {"", {"mir-browser.export-diagnostics-tooltip"}, "\n\n", {"mir-browser.export-sharing-guidance"}}
  end
  -- Layout updates do not re-encode or replace the report snapshot/selection.
  tools.style.width, tools.style.height = sizes.list_width, sizes.columns == 1 and sizes.list_height or sizes.detail_height
  panel.style.width = sizes.detail_width
  for _, entry in ipairs({{tools, sizes.list_width}, {panel, sizes.detail_width}}) do
    for _, child in ipairs(entry[1].children) do
      local available = math.max(1, entry[2] - 20)
      child.style.maximal_width = available
      if child.type == "label" then child.style.single_line = false
      elseif child.type == "line" or child.type == "button" then child.style.width = available end
    end
  end
  preview = panel[PREFIX .. "report_preview"]
  if valid(preview) then
    preview.style.width = math.max(1, sizes.detail_width - 20)
    preview.style.height = math.max(40, sizes.detail_height - 144)
  end
end

local function show_export_profile(content, encoded)
  if not valid(content) then return end
  local previous = content[PREFIX .. "export_profile"]
  if valid(previous) then previous.destroy() end
  if type(encoded) ~= "string" then return end
  local preview
  if #encoded <= 1048576 then
    preview = add(content, {type = "text-box", name = PREFIX .. "export_profile", text = encoded,
      tooltip = {"mir-browser.export-sharing-guidance"}})
    preview.read_only, preview.word_wrap = true, true
    if preview.style then
      preview.style.width = math.max(1, math.min(650, (content.style.maximal_width or 650) - 20))
      preview.style.horizontally_stretchable = true
      preview.style.height = 100
    end
    if type(preview.focus) == "function" then preview.focus() end
    if type(preview.select_all) == "function" then preview.select_all() end
  else
    add(content, {type = "label", name = PREFIX .. "export_profile", caption = {"mir-browser.export-profile-file-only"}})
  end
end

local function icon_button(parent, name, sprite, tooltip)
  local control = add(parent, {type = "sprite-button", name = PREFIX .. name,
    style = "frame_action_button", sprite = sprite, tooltip = tooltip})
  return control
end

local function sync_titlebar(frame, width)
  local title = frame[PREFIX .. "title"]
  if not valid(title) then return end
  title.drag_target = frame
  local caption, drag = title[PREFIX .. "title_label"], title[PREFIX .. "drag"]
  if valid(caption) then
    caption.ignored_by_interaction = true
    caption.style.maximal_width = library_layout.title_caption_width(width)
  end
  if valid(drag) then
    drag.ignored_by_interaction = true
    drag.style.height, drag.style.right_margin = library_layout.titlebar_action_size, 4
  end
  for _, name in ipairs({"layout_smaller", "layout_larger", "layout_reset", "close"}) do
    local button = title[PREFIX .. name]
    if valid(button) and button.style then
      if button.style.name ~= "frame_action_button" then button.style.name = "frame_action_button" end
      local size = library_layout.titlebar_action_size
      if button.style.minimal_width ~= size or button.style.maximal_width ~= size then button.style.width = size end
      if button.style.minimal_height ~= size or button.style.maximal_height ~= size then button.style.height = size end
    end
  end
end

local function create_filter_grid(filters, player, view, width)
  local columns, control_width = library_layout.filter_layout(width)
  local grid = add(filters, {type = "table", name = PREFIX .. "filter_grid", column_count = columns})
  grid.style.width, grid.style.horizontal_spacing = math.max(1, width - 64), library_layout.section_gap
  grid.style.vertical_spacing = library_layout.filter_gap
  local function choice(name, caption, items, selected)
    local field = add(grid, {type = "flow", name = PREFIX .. name .. "_field", direction = "vertical"})
    field.style.width, field.style.vertical_spacing = control_width, library_layout.control_gap
    local label = add(field, {type = "label", name = PREFIX .. name .. "_label", caption = {caption}, tooltip = {caption}})
    label.style.maximal_width = control_width
    local control = add(field, {type = "drop-down", name = PREFIX .. name, items = items,
      selected_index = selected, tooltip = {caption}})
    control.style.width, control.style.height = control_width, library_layout.control_height
  end
  local families = family_values()
  choice("family", "mir-browser.filter-scope", family_items(families, player), family_index(families, view.family) or 1)
  choice("status", "mir-browser.filter-status", {{"mir-browser.status-all"}, {"mir-browser.status-ready"},
    {"mir-browser.status-locked"}, {"mir-browser.status-queued"}}, view.status)
  choice("mode", "mir-browser.filter-level", {{"mir-browser.all"}, {"mir-browser.finite"}, {"mir-browser.infinite"}}, view.mode)
  choice("sort", "mir-browser.filter-order", {{"mir-browser.order-progression"}, {"mir-browser.order-native"},
    {"mir-browser.order-name-asc"}, {"mir-browser.order-name-desc"}}, SORT_INDEX[view.sort] or 1)
  choice("visibility", "mir-browser.visibility", {{"mir-browser.visibility-normal"}, {"mir-browser.visibility-hidden"},
    {"mir-browser.not-added"}}, view.visibility)
  return grid
end

local function create_filters(frame, player, view, width)
  local filters = add(frame, {type = "flow", name = PREFIX .. "filters", direction = "vertical"})
  filters.style.width, filters.style.vertical_spacing = math.max(1, width - 64), library_layout.control_gap
  local search = add(filters, {type = "label", name = PREFIX .. "search_label", caption = {"mir-browser.search-label"}})
  search.style.font = "default-semibold"
  local query = add(filters, {type = "textfield", name = PREFIX .. "query", text = view.query,
    tooltip = {"mir-browser.search-label"}})
  query.style.width, query.style.height = math.max(1, width - 64), library_layout.control_height
  create_filter_grid(filters, player, view, width)
  return filters
end

local function create_tabs(frame, player, view)
  local width = library_layout.frame_size(player.display_resolution, player.display_scale, view.geometry)
  local tabs = add(frame, {type = "tabbed-pane", name = PREFIX .. "tabs"})
  for _, tab_name in ipairs(TABS) do
    local tab = add(tabs, {type = "tab", name = PREFIX .. "tab_" .. tab_name,
      caption = {"mir-browser." .. (tab_name == "queue" and "queue-tab" or tab_name)}})
    -- Keep the MIR4 title -> tabs -> page structure. Research-only controls
    -- belong to that page, so changing tabs cannot move the navigation strip.
    local page = add(tabs, {type = "scroll-pane",
      name = PREFIX .. (tab_name == "research" and "research_page" or tab_name .. "_content"),
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"})
    if tab_name == "research" then
      create_filters(page, player, view, width)
      local kind = research_content_type(player, view)
      local spec = {type = kind, name = PREFIX .. "research_content",
        horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"}
      if kind == "table" then spec.column_count = 2 end
      add(page, spec)
    end
    tabs.add_tab(tab, page)
  end
  tabs.selected_tab_index = TAB_INDEX[view.tab] or 1
  return tabs
end

local function sync_frame_layout(player, view, frame)
  local width, height = library_layout.frame_size(player.display_resolution, player.display_scale, view.geometry)
  sync_titlebar(frame, width)
  local pairs_per_row, control_width = library_layout.filter_layout(width)
  local content_width = style_pixels(width - 48)
  local content_height = style_pixels(library_layout.content_height(height, pairs_per_row))
  local page_height = style_pixels(library_layout.tab_content_height(height))
  if frame.style then
    frame.style.width, frame.style.height = width, height
    frame.style.maximal_width = width
  end
  local clamped_location = library_layout.clamp_location(view.location, player.display_resolution,
    player.display_scale, width, height)
  if clamped_location then
    view.location = clamped_location
    frame.location = clamped_location
  end
  local filters = research_filters(frame)
  if valid(filters) and not research_filters_ready(filters) then
    local tabs = frame[PREFIX .. "tabs"]
    if valid(tabs) then tabs.destroy() end
    filters = nil
  end
  if not valid(filters) then
    create_tabs(frame, player, view)
    filters = research_filters(frame)
  end
  if valid(filters) then
    filters.style.width = math.max(1, width - 64)
    local query = research_filter_control(filters, "query")
    if valid(query) then query.style.width = math.max(1, width - 64) end
    local grid = filters[PREFIX .. "filter_grid"]
    if valid(grid) and grid.column_count ~= pairs_per_row then
      -- column_count is native read-only. Keep the query/caret and rebuild
      -- only this small container, restoring choices from the retained view.
      grid.destroy()
      grid = create_filter_grid(filters, player, view, width)
    end
    if valid(grid) then grid.style.width = math.max(1, width - 64) end
    for _, name in ipairs({"family", "status", "mode", "sort", "visibility"}) do
      local control = research_filter_control(filters, name)
      local field = valid(grid) and grid[PREFIX .. name .. "_field"]
      if valid(field) then
        field.style.width = control_width
        field[PREFIX .. name .. "_label"].visible = true
      end
      if valid(control) then control.style.width = control_width end
    end
  end
  local tabs = frame[PREFIX .. "tabs"]
  if valid(tabs) then
    if tabs.style then tabs.style.width = style_pixels(width - 32) end
    for _, tab_name in ipairs(TABS) do
      local page = tab_name == "research" and research_page(frame) or tab_content(frame, tab_name)
      if valid(page) and page.style then
        page.style.width, page.style.maximal_width = content_width, content_width
        page.style.height, page.style.maximal_height = page_height, page_height
      end
    end
    local body = tab_content(frame, "research")
    if valid(body) and body.style then
      body.style.width, body.style.maximal_width = content_width, content_width
      body.style.height, body.style.maximal_height = content_height, content_height
    end
  end
  return width, height, content_width, content_height
end

local function create_frame(player, view)
  local screen = player.gui and player.gui.screen
  if not valid(screen) then return nil end
  local frame = add(screen, {
    type = "frame", name = ROOT, direction = "vertical",
    tags = {[ROOT_TAG] = true}
  })
  if view.location then frame.location = view.location
  elseif type(frame.force_auto_center) == "function" then frame.force_auto_center() end

  local title = add(frame, {type = "flow", name = PREFIX .. "title", direction = "horizontal", tooltip = {"mir-browser.title"}})
  add(title, {type = "label", name = PREFIX .. "title_label", caption = {"mir-browser.title"}, style = "frame_title"})
  local drag = add(title, {type = "empty-widget", name = PREFIX .. "drag", style = "draggable_space_header"})
  drag.style.horizontally_stretchable = true
  drag.style.height = library_layout.titlebar_action_size
  drag.drag_target = frame

  icon_button(title, "layout_smaller", "utility/left_arrow", {"mir-browser.layout-smaller"})
  icon_button(title, "layout_larger", "utility/right_arrow", {"mir-browser.layout-larger"})
  icon_button(title, "layout_reset", "utility/reset", {"mir-browser.layout-reset"})
  icon_button(title, "close", "utility/close", {"mir-browser.close"})

  create_tabs(frame, player, view)
  sync_frame_layout(player, view, frame)
  return frame
end

-- Dynamic list/detail content is rebuilt under a stable root. In particular,
-- query edits preserve the existing text field, native focus and caret.
local function render(player, view, context, preserve_query)
  if not valid(player) or player.connected ~= true then return nil end
  context = context or context_for(player.force)
  local frame = owned_root(player)
  if valid(frame) and not frame_layout_ready(frame, player, view) then
    remember_location(view, frame)
    frame.destroy()
    frame = nil
  end
  if not valid(frame) then
    -- A foreign same-named root is a collision, not a frame this module may
    -- reuse or replace. In particular it must not cause player preferences.
    if valid(named_root(player)) then return nil end
    frame = create_frame(player, view)
  end
  if not valid(frame) then return nil end
  sync_frame_layout(player, view, frame)

  local filters = research_filters(frame)
  local query = valid(filters) and filters[PREFIX .. "query"] or nil
  if valid(query) and not preserve_query then query.text = view.query end
  local family = research_filter_control(filters, "family")
  local families = family_values()
  local selected_family = family_index(families, view.family)
  if selected_family == nil then
    view.family, selected_family = "mir", family_index(families, "mir") or 1
  end
  if valid(family) then
    family.items = family_items(families, player)
    family.selected_index = selected_family
  end
  local visibility = research_filter_control(filters, "visibility")
  if valid(visibility) then visibility.selected_index = view.visibility end
  local mode = research_filter_control(filters, "mode")
  if valid(mode) then mode.selected_index = view.mode end
  local status = research_filter_control(filters, "status")
  if valid(status) then status.selected_index = view.status end
  local sort = research_filter_control(filters, "sort")
  if valid(sort) then sort.selected_index = SORT_INDEX[view.sort] or 1 end
  local tabs = frame[PREFIX .. "tabs"]
  if valid(tabs) then tabs.selected_tab_index = TAB_INDEX[view.tab] or 1 end
  local content = tab_content(frame, view.tab)
  if view.tab == "research" and view.visibility == 3 then
    discard_translation_cache(player.index)
    update_availability_content(content, player, view)
  elseif view.tab == "research" then
    local translations = open_translation_cache(player, view)
    dispatch_translations(player, translations)
    local search_pending = view.query ~= "" and translations ~= nil
      and translation_queue.is_complete(translations.cache, translations.scope) == false
      and translation_queue.needs_maintenance(translations.cache)
    update_research_content(content, player, view, context, translated_labels(translations), search_pending)
    update_discovery_indicator(content, translations)
  elseif view.tab == "settings" then
    local translations = open_translation_cache(player, view)
    local labels = translated_labels(translations)
    update_settings_content(content, view, preserve_query, labels)
    dispatch_translations(player, translations)
  else
    -- A closed Research tab must not retain a local catalogue or spend more
    -- translation work. Issued IDs stay in the small durable ledger.
    discard_translation_cache(player.index)
    if view.tab == "queue" then
      update_queue_content(content, player, view)
    else
      update_help_content(content, player, view)
    end
  end
  set_shortcut(player, true)
  view.open = true
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

function M.set_discovery_visibility_provider(provider)
  if provider ~= nil and type(provider) ~= "function" then error("MIR discovery provider must be a function or nil", 2) end
  discovery_visibility_provider = provider
end

function M.open(player, options)
  if not valid(player) or player.connected ~= true or type(player.index) ~= "number" then return nil end
  local existing = named_root(player)
  if valid(existing) and existing ~= owned_root(player) then return nil end
  local view = view_for(player.index)
  options = type(options) == "table" and options or {}
  local reset_page = false
  if options.tab == "availability" then
    view.tab, view.visibility, reset_page = "research", 3, true
  elseif TAB_INDEX[options.tab] then
    view.tab = options.tab
  end
  if options.settings_scope == "research" or options.settings_scope == "options" then
    view.settings_scope, view.setting_selected = options.settings_scope, nil
  end
  -- The shipped remote browser's search follows its selected or retained tab.
  -- Keep the explicit internal query fields independent from this legacy input.
  if type(options.search) == "string" then
    if view.tab == "settings" then
      view.settings_query, view.setting_selected = text(options.search), nil
    else
      view.query = text(options.search)
    end
    reset_page = true
  end
  if type(options.settings_search) == "string" then
    view.settings_query, view.setting_selected = text(options.settings_search), nil
  end
  if type(options.query) == "string" then
    view.query, reset_page = text(options.query), true
  end
  local family = family_option(options.family)
  if family then
    view.family, reset_page = family, true
  end
  local mode = whole_option(options.mode, 1, 3)
  if mode then view.mode, reset_page = mode, true end
  local status = status_option(options.status)
  if status then view.status, reset_page = status, true end
  local visibility = visibility_option(options.visibility)
  if visibility then view.visibility, reset_page = visibility, true end
  local sort = sort_option(options.sort)
  if sort then
    view.sort, reset_page = sort, true
    if sort == "progression" or sort == "native" then view.stable_sort = sort end
  end
  local selected = technology_id(options.selected)
  if selected and known_technology(player, selected) then
    view.selected, reset_page = selected, true
  end
  if options.hidden ~= nil then
    local hidden = hidden_option(player, options.hidden)
    if hidden then view.hidden, reset_page = hidden, true end
  end
  local page = whole_option(options.page, 1, MAX_PAGE)
  if page then
    -- The current list remains continuous, as the shipped browser's own GUI
    -- did.  Retaining a valid page preserves remote and saved-view semantics.
    view.page = page
  elseif reset_page then
    view.page = 1
  end
  if reset_page then view.scroll = 1 end
  local frame = render(player, view)
  -- Factorio routes Esc/E to this target. Only an explicit open may claim
  -- focus; translation/native refreshes must not displace another GUI.
  if valid(frame) and player.opened ~= frame then player.opened = frame end
  return frame
end

function M.close(player)
  if not valid(player) or type(player.index) ~= "number" then return end
  if not valid(owned_root(player)) then return end
  local view = view_for(player.index)
  if destroy_frame(player, view) then discard_translation_cache(player.index) end
end

function M.on_lua_shortcut(event)
  if not event or event.prototype_name ~= SHORTCUT then return end
  local player = player_for(event.player_index)
  if not player then return end
  local existing = named_root(player)
  if valid(existing) then
    if existing == owned_root(player) then M.close(player) end
    return
  end
  M.open(player)
end

function M.on_gui_text_changed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player then return end
  if element.name == PREFIX .. "query" then
    if not owns_element(player, element, {PREFIX .. "query", PREFIX .. "filters", PREFIX .. "research_page", PREFIX .. "tabs", ROOT}) then return end
    local view = view_for(player.index)
    view.query, view.page, view.scroll = text(element.text), 1, 1
    render(player, view, nil, true)
  elseif element.name == PREFIX .. "settings_query" then
    if not owns_element(player, element, {
      PREFIX .. "settings_query", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    view.settings_query, view.setting_selected = text(element.text), nil
    render(player, view, nil, true)
  end
end

function M.on_gui_selected_tab_changed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {PREFIX .. "tabs", ROOT}) then return end
  local tab = TABS[whole_option(element.selected_tab_index, 1, #TABS) or 0]
  if tab == nil then return end
  local view = view_for(player.index)
  if view.tab == tab then return end
  view.tab = tab
  render(player, view)
end

function M.on_gui_checked_state_changed(event)
  local element = event and event.element
  if not valid(element) or element.type ~= "checkbox" then return end
  local field = element.name == PREFIX .. "report_settings" and "report_settings"
    or element.name == PREFIX .. "report_omissions" and "report_omissions" or nil
  if not diagnostics or not field then return end
  local player = player_for(event and event.player_index)
  if not player or type(element.state) ~= "boolean" then return end
  if not owns_element(player, element, {element.name, PREFIX .. "help_tools", PREFIX .. "help_panes", PREFIX .. "help_content", PREFIX .. "tabs", ROOT}) then return end
  local view = view_for(player.index)
  view[field] = element.state
  update_report_preview(element.parent.parent.parent, player, view)
end

function M.on_gui_selection_state_changed(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event and event.player_index)
  if not player then return end
  if element.name == PREFIX .. "family" then
    if not owns_element(player, element, {
      PREFIX .. "family", PREFIX .. "family_field", PREFIX .. "filter_grid", PREFIX .. "filters", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local family = family_from_index(element.selected_index)
    if family == nil then return end
    view.family = family
    view.page = 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "visibility" then
    if not owns_element(player, element, {
      PREFIX .. "visibility", PREFIX .. "visibility_field", PREFIX .. "filter_grid", PREFIX .. "filters", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local visibility = visibility_option(element.selected_index)
    if visibility == nil then return end
    local view = view_for(player.index)
    view.visibility, view.page, view.scroll = visibility, 1, 1
    render(player, view)
  elseif element.name == PREFIX .. "mode" then
    if not owns_element(player, element, {
      PREFIX .. "mode", PREFIX .. "mode_field", PREFIX .. "filter_grid", PREFIX .. "filters", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local mode = whole_option(element.selected_index, 1, 3)
    if mode == nil then return end
    local view = view_for(player.index)
    view.mode, view.page, view.scroll = mode, 1, 1
    render(player, view)
  elseif element.name == PREFIX .. "status" then
    if not owns_element(player, element, {
      PREFIX .. "status", PREFIX .. "status_field", PREFIX .. "filter_grid", PREFIX .. "filters", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local status = element.selected_index
    view.status = type(status) == "number" and status >= 1 and status <= 4 and math.floor(status) == status and status or 1
    view.page = 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "sort" then
    if not owns_element(player, element, {
      PREFIX .. "sort", PREFIX .. "sort_field", PREFIX .. "filter_grid", PREFIX .. "filters", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local sort = sort_from_index(element.selected_index)
    view.sort = sort
    if sort == "progression" or sort == "native" then view.stable_sort = sort end
    view.page = 1
    view.scroll = 1
    render(player, view)
  elseif element.name == PREFIX .. "results" then
    if not owns_element(player, element, {
      PREFIX .. "results", PREFIX .. "list_pane", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local context = context_for(player.force)
    local rows = rows_for(player, view, context, translated_labels(translation_caches[player.index]))
    local index = element.selected_index
    local row = type(index) == "number" and rows[index] or nil
    if row then
      view.selected = row.id
      view.scroll = index
      render(player, view, context)
    end
  elseif element.name == PREFIX .. "recipe_list" then
    local ordinary = owns_element(player, element, {
      PREFIX .. "recipe_list", PREFIX .. "detail", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    })
    local compact = owns_element(player, element, {
      PREFIX .. "recipe_list", PREFIX .. "research_facts", PREFIX .. "detail", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    })
    if not ordinary and not compact then return end
    local view = view_for(player.index)
    local detail = selected_detail(player, view, context_for(player.force),
      translated_labels(translation_caches[player.index]))
    local index = whole_option(element.selected_index, 1, 512)
    if index then open_recipe_entry(player, detail, index) end
  elseif element.name == PREFIX .. "settings_list" then
    if not owns_element(player, element, {
      PREFIX .. "settings_list", PREFIX .. "settings_dynamic", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    }) then return end
    local groups = setting_catalogue()
    if groups == nil then return end
    local view = view_for(player.index)
    local translations = translated_labels(translation_caches[player.index])
    local visible = {}
    for _, group in ipairs(groups) do
      if group.scope == view.settings_scope and setting_search_matches(group, view.settings_query, translations) then
        visible[#visible + 1] = group
      end
    end
    local group = visible[element.selected_index]
    if group == nil then return end
    view.setting_selected = group.key
    render(player, view)
  elseif element.name == PREFIX .. "queue_list" then
    if not owns_element(player, element, {
      PREFIX .. "queue_list", PREFIX .. "queue_content", PREFIX .. "tabs", ROOT
    }) then return end
    local id = queue_entries(player.force)[element.selected_index]
    if id == nil or known_technology(player, id) == nil then return end
    local view = view_for(player.index)
    view.selected, view.tab, view.page, view.scroll = id, "research", 1, 1
    render(player, view)
  end
end

function M.on_gui_click(event)
  local element = event and event.element
  if not valid(element) then return end
  local player = player_for(event and event.player_index)
  if not player then return end
  if element.name == PREFIX .. "layout_smaller" or element.name == PREFIX .. "layout_larger"
      or element.name == PREFIX .. "layout_reset" then
    if not owns_element(player, element, {element.name, PREFIX .. "title", ROOT})
      and not (element.name == PREFIX .. "layout_reset" and owns_element(player, element, {
        element.name, PREFIX .. "help_tools", PREFIX .. "help_panes", PREFIX .. "help_content", PREFIX .. "tabs", ROOT
      })) then return end
    local reset_layout = element.name == PREFIX .. "layout_reset"
    local view = view_for(player.index)
    if reset_layout then
      view.geometry, view.location = nil, nil
    else
      local delta = element.name == PREFIX .. "layout_larger" and 64 or -64
      view.geometry = library_layout.resize(player.display_resolution, player.display_scale, view.geometry, delta)
    end
    local frame = render(player, view)
    -- Crossing the split/stacked boundary can replace the frame and destroy
    -- the clicked native element. Use the captured action, not that object.
    if reset_layout then
      view.location = nil
      if valid(frame) and type(frame.force_auto_center) == "function" then frame.force_auto_center() end
    end
    return
  end
  if support_exports and (element.name == PREFIX .. "export_settings" or element.name == PREFIX .. "export_compact") then
    local in_settings = owns_element(player, element, {
      element.name, PREFIX .. "settings_toolbar", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    })
    local in_debug = element.name == PREFIX .. "export_settings" and owns_element(player, element, {
      element.name, PREFIX .. "help_tools", PREFIX .. "help_panes", PREFIX .. "help_content", PREFIX .. "tabs", ROOT
    })
    if not in_settings and not in_debug then return end
    local encoded = support_exports.export({player_index = player.index,
      parameter = element.name == PREFIX .. "export_compact" and "--compact" or nil})
    local destination = in_settings and element.parent.parent or report_panel(element.parent.parent.parent)
    show_export_profile(destination, encoded)
    return
  end
  if diagnostics and element.name == PREFIX .. "export_diagnostics" then
    if not owns_element(player, element, {
      element.name, PREFIX .. "report_panel", PREFIX .. "help_panes", PREFIX .. "help_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local encoded, _, report = diagnostics.export(player.index, view.selected, report_options(player, view))
    if report and valid(element.parent[PREFIX .. "report_preview"]) then
      element.parent[PREFIX .. "report_preview"].text = report
    end
    show_export_profile(element.parent, encoded)
    return
  end
  if diagnostics and (element.name == PREFIX .. "report_select" or element.name == PREFIX .. "report_refresh") then
    local pane = element.name == PREFIX .. "report_refresh" and "help_tools" or "report_panel"
    if not owns_element(player, element, {
      element.name, PREFIX .. pane, PREFIX .. "help_panes", PREFIX .. "help_content", PREFIX .. "tabs", ROOT
    }) then return end
    if element.name == PREFIX .. "report_refresh" then
      update_report_preview(element.parent.parent.parent, player, view_for(player.index))
      return
    end
    local preview = element.parent[PREFIX .. "report_preview"]
    if valid(preview) then
      if type(preview.focus) == "function" then preview.focus() end
      if type(preview.select_all) == "function" then preview.select_all() end
    end
    return
  end
  if element.name == PREFIX .. "production_check" then
    if not owns_element(player, element, {
      PREFIX .. "production_check", PREFIX .. "research_facts", PREFIX .. "detail", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local id = technology_id(view.selected)
    local technology = id and known_technology(player, id) or nil
    local panel = element.parent and element.parent[PREFIX .. "production_results"] or nil
    if technology and valid(panel) then show_production_snapshot(panel, player, technology) end
    return
  end
  if element.name == PREFIX .. "close" then
    local in_research_actions = owns_element(player, element, {
      PREFIX .. "close", PREFIX .. "actions", PREFIX .. "list_pane", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    })
    local in_title = owns_element(player, element, {PREFIX .. "close", PREFIX .. "title", ROOT})
    if not in_research_actions and not in_title then return end
    M.close(player)
    return
  end
  if element.name == PREFIX .. "hide" then
    if not owns_element(player, element, {
      PREFIX .. "hide", PREFIX .. "actions", PREFIX .. "list_pane", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local id = technology_id(view.selected)
    if id == nil or not known_technology(player, id) then return end
    if view.hidden[id] then
      view.hidden[id], view.selected = nil, id
      if view.visibility == 2 then view.visibility = 1 end
    else
      local count = 0
      for _, hidden in pairs(view.hidden) do if hidden == true then count = count + 1 end end
      if count >= MAX_HIDDEN then return end
      view.hidden[id], view.selected = true, nil
    end
    view.page, view.scroll = 1, 1
    render(player, view)
    return
  end
  if element.name == PREFIX .. "show_hidden" then
    if not owns_element(player, element, {
      PREFIX .. "show_hidden", PREFIX .. "actions", PREFIX .. "list_pane", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    view.hidden, view.visibility, view.selected = {}, 1, nil
    view.page, view.scroll = 1, 1
    render(player, view)
    return
  end
  if element.name == PREFIX .. "inspect_settings" then
    if not owns_element(player, element, {
      PREFIX .. "inspect_settings", PREFIX .. "actions", PREFIX .. "list_pane", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    local selected = technology_id(view.selected)
    if selected == nil then return end
    local rows = rows_for(player, view, context_for(player.force), translated_labels(translation_caches[player.index]))
    local row
    for _, candidate in ipairs(rows) do if candidate.id == selected then row = candidate; break end end
    local setting = row and row.cap_setting
    local key = settings_group_key(setting)
    if key then
      view.tab, view.settings_scope, view.settings_query, view.setting_selected = "settings", "research", "", key
      render(player, view)
    end
    return
  end
  if element.name == PREFIX .. "settings_research" or element.name == PREFIX .. "settings_options" then
    if not owns_element(player, element, {
      element.name, PREFIX .. "settings_toolbar", PREFIX .. "settings_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    view.settings_scope = element.name == PREFIX .. "settings_options" and "options" or "research"
    view.setting_selected = nil
    render(player, view)
    return
  end
  if element.name == PREFIX .. "queue_open_native" then
    if not owns_element(player, element, {
      PREFIX .. "queue_open_native", PREFIX .. "queue_content", PREFIX .. "tabs", ROOT
    }) then return end
    local view = view_for(player.index)
    if destroy_frame(player, view) then discard_translation_cache(player.index) end
    if type(player.open_technology_gui) == "function" then player.open_technology_gui(nil) end
    return
  end
  if element.name ~= PREFIX .. "open_native" then return end
  if not owns_element(player, element, {
    PREFIX .. "open_native", PREFIX .. "actions", PREFIX .. "list_pane", PREFIX .. "research_content", PREFIX .. "research_page", PREFIX .. "tabs", ROOT
  }) then return end
  local view = view_for(player.index)
  local selected = technology_id(view.selected)
  if selected == nil or private_credit_id(selected) then return end
  local technologies = player.force and player.force.technologies
  if technologies == nil then return end
  local ok, technology = pcall(function() return technologies[selected] end)
  if not ok or not valid(technology) then return end
  if DISCOVERY_TREE and not library_model.technology_visible(technology, selected, context_for(player.force)) then return end
  if destroy_frame(player, view) then discard_translation_cache(player.index) end
  if type(player.open_technology_gui) == "function" then player.open_technology_gui(technology) end
end

function M.on_gui_location_changed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {ROOT}) then return end
  local view = view_for(player.index)
  local remembered = location(element.location)
  if remembered then view.location = remembered end
end

function M.on_gui_closed(event)
  local element = event and event.element
  local player = player_for(event and event.player_index)
  if not player or not owns_element(player, element, {ROOT}) then return end
  M.close(player)
end

local function expire_durable_entry(entry, tick)
  local cache = cache_from_pending(entry_pending(entry))
  if cache == nil then return nil, false end
  translation_queue.maintain(cache, cache.scope, tick)
  local pending = translation_queue.export_pending(cache)
  if pending == nil then return nil, false end
  return pending, true
end

local function release_durable_request(entry, request_id)
  local cache = cache_from_pending(entry_pending(entry))
  if cache == nil then return false, nil end
  local result = translation_queue.complete(cache, cache.scope, request_id, nil)
  return result.released == true, translation_queue.export_pending(cache)
end

local function update_durable_entry(bucket, group, index, entry, pending)
  if type(pending) ~= "table" or #pending == 0 then
    bucket[group][index] = nil
  else
    entry.pending = pending
    bucket[group][index] = entry
  end
end

local function clear_unrooted_view(index)
  local state = existing_state()
  local view = state and state.players[index]
  if type(view) == "table" then view.open, view.refresh_pending = false, false end
end

local function resume_open_retired_view(index)
  local state = existing_state()
  local view = state and state.players[index]
  local player = player_for(index)
  if type(view) == "table" and view.open == true and valid(player)
      and player.connected == true and valid(owned_root(player)) then
    render(player, view, nil, true)
  end
end

local function invalidate_open_translation(index)
  local record = translation_caches[index]
  if record then discard_translation_cache(index) end
  local player = player_for(index)
  if valid(player) and player.connected == true and valid(owned_root(player)) then
    render(player, view_for(index), nil, true)
  else
    clear_unrooted_view(index)
  end
end

function M.on_string_translated(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local index, player = event.player_index, player_for(event.player_index)
  local record = translation_caches[index]
  local rooted = player and player.connected == true and valid(owned_root(player))
  if record and not rooted then
    -- The frame can disappear without our close callback. Retain only the
    -- durable issued window; callbacks then release it without a hidden view.
    discard_translation_cache(index)
    clear_unrooted_view(index)
    record = nil
  end
  if record then
    -- A native locale/force change can be visible before its corresponding
    -- event is delivered. Complete against the live token, never the cached
    -- one, so the old reply releases its ID but cannot label this view.
    local live_scope = scope_for(player, record.scope.generation)
    local scope_matches = live_scope and same_translation_scope(live_scope, record.scope)
    if live_scope == nil then
      live_scope = {
        player_index = record.scope.player_index,
        locale = record.scope.locale,
        force_index = record.scope.force_index,
        generation = record.scope.generation == 0 and 1 or 0
      }
    end
    local label = scope_matches and event.translated == true and type(event.result) == "string"
      and event.result or nil
    local result = translation_queue.complete(record.cache, live_scope, event.id, label)
    if not result.released then return end
    sync_issued_cache(record)
    if result.published and scope_matches and rooted
        and translation_queue.take_refresh(record.cache, record.scope) then
      render(player, view_for(index), nil, true)
    end
    return
  end

  -- With no open local cache a reply is useful only for releasing a durable
  -- request. It never rebuilds a closed view or creates presentation state.
  local state = existing_state()
  local ledger = state and existing_translation_ledger(state) or nil
  if not ledger then return end
  for _, group in ipairs({"active", "retired"}) do
    local entry = ledger[group][index]
    if entry then
      local released, pending = release_durable_request(entry, event.id)
      if released then
        update_durable_entry(ledger, group, index, entry, pending)
        if group == "retired" and ledger.retired[index] == nil then resume_open_retired_view(index) end
      end
      return
    end
  end
end

function M.on_player_locale_changed(event)
  if event and whole_number(event.player_index, 1) then invalidate_open_translation(event.player_index) end
end

function M.on_player_changed_force(event)
  if event and whole_number(event.player_index, 1) then invalidate_open_translation(event.player_index) end
end

function M.on_player_joined_game(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local player = player_for(event.player_index)
  local state = existing_state()
  if player and player.connected == true and state and type(state.players[event.player_index]) == "table" and valid(owned_root(player)) then
    -- A deferred native request may now be issued, but only because this
    -- player's tagged Library is actually open and connected.
    render(player, view_for(event.player_index), nil, true)
  else
    local view = state and state.players[event.player_index]
    if type(view) == "table" then view.open, view.refresh_pending = false, false end
    discard_translation_cache(event.player_index)
  end
end

function M.on_player_left_game(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local state = existing_state()
  local index = event and event.player_index
  local view = state and state.players[index]
  if type(view) == "table" then view.open, view.refresh_pending = false, false end
  if index then discard_translation_cache(index) end
end

-- Player GUI references can outlive the LuaPlayer proxy when an offline
-- player is deleted. Destroy only MIR's tagged window while the player still
-- exists so retained GUI handles are invalidated before the removal event.
function M.on_pre_player_removed(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local player = player_for(event.player_index)
  if player then M.close(player) end
end

-- Research callbacks can precede the engine's final queue/level transition.
-- Mark only relevant owned open views and refresh once on the following tick.
function M.on_native_state_changed(event)
  local state = existing_state()
  if not state then return end
  local force = event and (event.force or event.destination or (event.research and event.research.force))
  for index, view in pairs(state.players) do
    if type(view) == "table" and view.open == true then
      local player = player_for(index)
      if not player or player.connected ~= true or not valid(owned_root(player)) then
        view.open, view.refresh_pending = false, false
        discard_translation_cache(index)
      elseif force == nil or (player.force and player.force.index == force.index) then
        view.refresh_pending = true
      end
    end
  end
end

function M.on_native_refresh_tick()
  local state = existing_state()
  if not state then return end
  local pending = {}
  for index, view in pairs(state.players) do
    if type(view) == "table" and view.refresh_pending == true then
      view.refresh_pending = false
      if whole_number(index, 1) then pending[#pending + 1] = index else view.open = false end
    end
  end
  -- Rendering may allocate durable translation epochs/native request IDs.
  -- Process only the pending views, in a stable player order on every client.
  table.sort(pending)
  for _, index in ipairs(pending) do
    local view, player = state.players[index], player_for(index)
    if view.open == true and player and player.connected == true and valid(owned_root(player)) then
      render(player, view_for(index), nil, true)
    else
      view.open = false
      discard_translation_cache(index)
    end
  end
end

-- The two durable UI flags reconstruct subscriptions without accessing game
-- or changing saved data during on_load. They cache no native research facts.
function M.native_subscription_needs()
  local state = type(storage) == "table" and storage[STORAGE_KEY] or nil
  if type(state) ~= "table" or state.schema ~= SCHEMA or type(state.players) ~= "table" then
    return false, false
  end
  local open, pending = false, false
  for index, view in pairs(state.players) do
    if whole_number(index, 1) and type(view) == "table" and view.open == true then
      open = true
      pending = pending or view.refresh_pending == true
    end
  end
  return open, pending
end

function M.on_player_removed(event)
  if not event or not whole_number(event.player_index, 1) then return end
  local state = existing_state()
  if not state then return end
  local index = event.player_index
  state.players[index] = nil
  local preserved = state.legacy_browser
  if type(preserved) == "table" and type(preserved.players) == "table" and preserved.players[index] ~= nil then
    -- Preserve original history, but never import its personal choices into a
    -- different account that later receives the same native player index.
    if type(preserved.retired_players) ~= "table" then preserved.retired_players = {} end
    preserved.retired_players[index] = true
  end
  discard_translation_cache(index)
  local ledger = existing_translation_ledger(state)
  if not ledger then return end
  local active = ledger.active[index]
  if active ~= nil and ledger.retired[index] == nil then
    -- LuaPlayer indices are reusable after removal. Retain even an unfamiliar
    -- active record rather than assuming it has no engine-issued IDs.
    ledger.retired[index] = active
    ledger.active[index] = nil
  elseif active == nil then
    ledger.active[index] = nil
  end
end

function M.on_translation_maintenance(event)
  local tick = event and event.tick
  if not whole_number(tick, 0) then return end
  local state = existing_state()
  local ledger = state and existing_translation_ledger(state) or nil
  if not ledger then return end

  for _, index in ipairs(ordered_player_indices(ledger.active)) do
    local entry = ledger.active[index]
    local record = translation_caches[index]
    local player = player_for(index)
    local rooted = player and player.connected == true and valid(owned_root(player))
    if record and record.ledger == ledger and rooted then
      translation_queue.maintain(record.cache, record.scope, tick)
      sync_issued_cache(record)
      if translation_queue.take_refresh(record.cache, record.scope) then
        render(player, view_for(index), nil, true)
      else
        dispatch_translations(player, record)
      end
    elseif record and record.ledger == ledger then
      -- A closed, disconnected, or externally destroyed root retains no local
      -- labels/catalogue. Its persisted issued window is expiry-only.
      clear_unrooted_view(index)
      discard_translation_cache(index)
      local durable = ledger.active[index]
      if durable then
        local pending, handled = expire_durable_entry(durable, tick)
        if handled then update_durable_entry(ledger, "active", index, durable, pending) end
      end
    else
      local pending, handled = expire_durable_entry(entry, tick)
      if handled then update_durable_entry(ledger, "active", index, entry, pending) end
    end
  end
  for _, index in ipairs(ordered_player_indices(ledger.retired)) do
    local entry = ledger.retired[index]
    local pending, handled = expire_durable_entry(entry, tick)
    if handled then update_durable_entry(ledger, "retired", index, entry, pending) end
    -- A reused index receives no new request while its prior lifetime has an
    -- issued ID. Once the retained window has drained, an already open owned
    -- view may resume normally; a closed or disconnected player remains
    -- expiry-only and receives no hidden render or dispatch.
    if ledger.retired[index] == nil and translation_caches[index] == nil then resume_open_retired_view(index) end
  end
end

-- Lifecycle callbacks deliberately do not initialize player state.  A later
-- explicit open reconstructs the frame from a normalized saved view.
function M.on_init()
end

-- Published 4.7 stored the browser at storage.mir.research_browser and used
-- view schema 3.  Copy a bounded convenience snapshot into a private
-- preservation envelope, whose provenance points back to the untouched
-- published bucket for full fidelity. Migrate only the fields this first
-- Library slice supports. Existing MIR5 views win so a repeated configuration
-- change cannot overwrite a newer choice. This explicit configuration event
-- visits every saved player record (O(P)); it deliberately does not truncate
-- migration candidates.
function M.on_configuration_changed()
  reconnect_translation_caches()
  declaration_cache = nil
  setting_groups_cache = nil
  setting_prototype_cache = nil
  local legacy = legacy_browser_state()
  local legacy_players = legacy and legacy.players
  if type(legacy_players) == "table" then
    local candidates = {}
    for index, historical_view in pairs(legacy_players) do
      local normalized_index = player_index(index)
      if normalized_index and type(historical_view) == "table" and not legacy_player_retired(existing_state(), normalized_index) then
        candidates[#candidates + 1] = {index = normalized_index, view = historical_view}
      end
    end
    if #candidates > 0 then
      local state = existing_state() or ensure_state()
      local preserved = state.legacy_browser
      if type(preserved) ~= "table" then
        preserved = {
          version = LEGACY_SNAPSHOT_VERSION,
          source = "storage.mir.research_browser",
          authoritative_source = "storage.mir.research_browser",
          players = {},
          snapshot_status = {}
        }
        state.legacy_browser = preserved
      elseif type(preserved.players) ~= "table" then
        preserved.players = {}
      end
      if type(preserved.snapshot_status) ~= "table" then preserved.snapshot_status = {} end

      for _, candidate in ipairs(candidates) do
        local index, historical_view = candidate.index, candidate.view
        if preserved.players[index] == nil then
          local snapshot, status = legacy_snapshot(historical_view)
          preserved.players[index] = snapshot
          preserved.snapshot_status[index] = status
        end
        if type(state.players[index]) ~= "table" then
          state.players[index] = legacy_view_as_private(historical_view)
        else
          carry_report_choices(state.players[index], historical_view)
        end
      end

      -- game.get_player(uint32) and LuaGuiElement child lookup/destroy are
      -- documented by the local 2.1 runtime API.  No player is created here:
      -- a headless native process cannot establish GUI-client evidence.
      for _, candidate in ipairs(candidates) do
        local player = player_for(candidate.index)
        if player then
          local view = local_view(state.players[candidate.index])
          state.players[candidate.index] = view
          rebuild_owned_legacy_root(player, view)
        end
      end
    end
  end

  -- Older views have no subscription flags. Recover them only here, where
  -- native players/GUI are available; a closed or foreign frame stays closed.
  local current = existing_state()
  if current then
    for index, view in pairs(current.players) do
      if type(view) == "table" then
        local snapshots = type(current.legacy_browser) == "table" and current.legacy_browser.players or nil
        if not legacy_player_retired(current, index) then
          carry_report_choices(view, type(snapshots) == "table" and snapshots[index] or nil)
        end
        local player = player_for(index)
        view.open = player ~= nil and player.connected == true and valid(owned_root(player))
        view.refresh_pending = view.open
      end
    end
  end

  -- Configuration may change the compact catalogue. Keep engine-issued IDs,
  -- but give every open view a new caller epoch before it can publish labels.
  local open = ordered_player_indices(translation_caches)
  for _, index in ipairs(open) do invalidate_open_translation(index) end
end

-- Reconnect plain working references only. No saved field, native object,
-- authored catalogue, GUI or request is touched during load/client catch-up.
function M.on_load()
  reconnect_translation_caches()
end

-- Read-only on-load-safe decision. Do not call ensure_state here: malformed or
-- absent private state has no outstanding request this callback can own.
function M.subscription_needs()
  local state = type(storage) == "table" and storage[STORAGE_KEY] or nil
  local ledger = existing_translation_ledger(state)
  if not ledger then return false end
  for _, group in ipairs({ledger.active, ledger.retired}) do
    for _, entry in pairs(group) do
      if entry_pending(entry) then return true end
    end
  end
  return false
end

return M
