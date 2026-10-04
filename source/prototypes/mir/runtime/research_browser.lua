local core = require("prototypes.mir.runtime.research_browser_core")
local translation_queue = core.translation_queue
local factorio_catalogue = require("prototypes.mir.runtime.research_browser_factorio_catalogue")
local mir_provider = require("prototypes.mir.runtime.research_browser_mir_provider")
local runtime_state = require("prototypes.mir.runtime.state")
local factorio_runtime_state = require("prototypes.mir.platform.factorio.runtime_state")
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local streams = require("prototypes.mir.streams.registry")
local M = {requires_features = {"settings_profiles"}}
local ROOT, PREFIX, SHORTCUT = "mir_research_browser", "mir_browser_", "mir-research-browser"
local RESEARCH_LIST_WIDTH, RESEARCH_DETAIL_WIDTH = 360, 320
local RESEARCH_LIST_MIN_WIDTH, RESEARCH_DETAIL_MIN_WIDTH = 240, 280
local RESEARCH_PANES_MIN_HEIGHT, RESEARCH_FILTERS_HEIGHT, RESEARCH_HIDDEN_RECOVERY_HEIGHT = 80, 124, 32
local RESEARCH_BODY_MAX_HEIGHT = 420
-- Translation IDs are asynchronous and per-player.  Keep the work window
-- small so a large catalogue neither monopolizes a tick nor stops after an
-- arbitrary lifetime number of successful translations.
-- Do not share passive repair's 60-tick registration; Factorio has one
-- handler per interval within this mod.
local TRANSLATION_MAINTENANCE_TICKS = 61
local SEARCH_REFRESH_TICKS, SEARCH_SETTLE_TICKS = 3, 6
local VIEW_SCHEMA = 3
local render
local refresh_scheduled_forces
local refresh_scheduled_searches
local update_research_results
local update_navigation
local update_translation_index

local function state()
  local value = runtime_state.bucket("research_browser")
  value.players = value.players or {}
  value.pending_force_refresh = type(value.pending_force_refresh) == "table" and value.pending_force_refresh or {}
  value.pending_search_refresh = type(value.pending_search_refresh) == "table" and value.pending_search_refresh or {}
  return value
end

local TAB_NAMES = {"research", "queue", "settings", "help"}
local function dimensions(player)
  local resolution, scale = player.display_resolution, player.display_scale
  scale = type(scale) == "number" and scale > 0 and scale or 1
  local screen_width = math.floor((resolution and resolution.width or 1920) / scale)
  local screen_height = math.floor((resolution and resolution.height or 1080) / scale)
  local saved = state().players[player.index]
  local geometry = saved and saved.geometry or {}
  local width = math.min(screen_width - 24, geometry.width or math.max(640, math.floor(screen_width * 0.5)))
  local height = math.min(screen_height - 24, geometry.height or math.max(400, math.floor(screen_height * 0.75)))
  return math.max(240, width), math.max(220, height)
end
local function research_pane_widths(player)
  local width = dimensions(player) - 64
  if width < 400 then return width, width, true end
  local list = math.floor((width - 12) * 0.40)
  return list, width - 12 - list, false
end
local function settings_pane_widths(player) return research_pane_widths(player) end
local function tab_content(frame, tab)
  local tabs = frame and frame[PREFIX .. "tabs"]
  return tabs and tabs[PREFIX .. tab .. "_content"]
end
local function active_body(player, tab)
  local content = tab_content(player.gui.screen[ROOT], tab)
  return content and content[PREFIX .. "body"]
end
local function research_panes_height(results)
  -- GuiStyle.height is write-only. The bounded maximum is readable and stays
  -- on the retained results flow when a settled localized index replaces its
  -- child panes.
  local height = results and results.valid and results.style.maximal_height
  if type(height) ~= "number" or height <= 0 then return RESEARCH_PANES_MIN_HEIGHT end
  return math.max(RESEARCH_PANES_MIN_HEIGHT, height)
end

-- The one-tick coalescer is installed only while an open force has pending
-- work. This reader is deliberately separate from state(): on_load may
-- rebind an existing subscription but must never create or repair persisted state.
local function saved_pending_force_refresh()
  local root = factorio_runtime_state.root()
  local namespace = type(root) == "table" and root.mir
  local browser = type(namespace) == "table" and namespace.research_browser
  local pending = type(browser) == "table" and browser.pending_force_refresh
  return type(pending) == "table" and pending or nil
end

local function set_force_refresh_subscription(active)
  script.on_nth_tick(1, active and refresh_scheduled_forces or nil)
end

local function saved_pending_search_refresh()
  local root = factorio_runtime_state.root()
  local namespace = type(root) == "table" and root.mir
  local browser = type(namespace) == "table" and namespace.research_browser
  local pending = type(browser) == "table" and browser.pending_search_refresh
  return type(pending) == "table" and pending or nil
end

local function set_search_refresh_subscription(active)
  script.on_nth_tick(SEARCH_REFRESH_TICKS, active and refresh_scheduled_searches or nil)
end

-- Factorio can deliver a translation callback after a save/load or a
-- configuration change. Retain only plain records in the established runtime
-- bucket so those issued IDs still occupy their shared bounded window; no
-- LuaObject is retained in this cache.
local function translation_state()
  local value = state()
  value.translations = type(value.translations) == "table" and value.translations or {}
  value.translation_locale_generations = type(value.translation_locale_generations) == "table"
    and value.translation_locale_generations or {}
  return value.translations, value.translation_locale_generations
end

local function next_locale_generation(generations, cache, player_index)
  local previous = generations[player_index]
  if type(previous) ~= "number" or previous < 0 or previous ~= math.floor(previous) then
    previous = type(cache) == "table" and cache.locale_generation or 0
  end
  previous = math.max(0, previous) + 1
  generations[player_index] = previous
  return previous
end
local function default_view()
  return {
    schema = VIEW_SCHEMA,
    mode = 1,
    status = 1,
    page = 1,
    search = "",
    tab = "research",
    setting_selection = nil,
    settings_scope = "research",
    effect_page = 1,
    family = "mir",
    sort = "progression",
    stable_sort = "progression",
    settings_search = "",
    visibility = 1
  }
end
local function has_legacy_default_scope_and_order(value)
  if type(value) ~= "table" or value.schema ~= nil then return false end
  return value.family == "all" and value.sort == "name-asc"
end
local function view(player)
  local all = state().players
  local result = all[player.index]
  if type(result) ~= "table" then result = default_view() end
  -- 4.2's former scope/order default was all research in alphabetical order.
  -- Selection, hiding, search, and the other filters remain personal state;
  -- only that legacy scope/order pair changes.
  if has_legacy_default_scope_and_order(result) then
    result.family = "mir"
    result.sort = "progression"
  end
  result.settings_search = type(result.settings_search) == "string" and result.settings_search or ""
  result.visibility = result.visibility == 2 and 2 or result.visibility == 3 and 3 or 1
  result.schema = VIEW_SCHEMA
  all[player.index] = result
  result.sort = result.sort == "name-asc" and "name-asc"
    or result.sort == "name-desc" and "name-desc"
    or result.sort == "native" and "native"
    or "progression"
  result.stable_sort = result.stable_sort == "native" and "native" or "progression"
  if result.sort == "native" or result.sort == "progression" then result.stable_sort = result.sort end
  result.tab = result.tab == "settings" and "settings"
    or result.tab == "queue" and "queue"
    or result.tab == "help" and "help"
    or "research"
  if type(result.setting_selection) ~= "string" or #result.setting_selection > core.detail_string_limit then
    result.setting_selection = nil
  end
  result.settings_scope = result.settings_scope == "options" and "options" or "research"
  return result
end

local function needs_name_index(v)
  return v.tab == "research" and (v.search ~= "" or v.sort == "name-asc" or v.sort == "name-desc")
end
local catalogue_cache = {}
local function catalogue(force)
  local cached = catalogue_cache[force.index]
  if cached and cached.tick == game.tick then return cached.value end
  local result = factorio_catalogue.snapshot(force)
  if not result then return nil end
  -- Dynamic cap/level facts must be refreshed with the copied Force snapshot.
  -- Only the pure core is cache-safe; provider state is never retained here.
  result.enrichment = mir_provider.list_snapshot(force)
  result.family_names = core.family_names(result.enrichment)
  catalogue_cache[force.index] = {tick = game.tick, value = result}
  return result
end

local function resolved_detail(force, catalogue_snapshot, technology_id)
  if not catalogue_snapshot then return nil, "invalid-catalogue" end
  local enrichment = catalogue_snapshot.enrichment
  if type(technology_id) == "string" and enrichment and enrichment.families[technology_id]
      and not enrichment.details[technology_id] then
    local selected = mir_provider.selected_detail(force, technology_id)
    if selected then enrichment.details[technology_id] = selected
    else return nil, {"mir-browser.live-detail-unavailable"} end
  end
  return core.detail(catalogue_snapshot, technology_id, enrichment)
end

local function translation_cache(player)
  local translations, locale_generations = translation_state()
  local cache = translations[player.index]
  if type(cache) ~= "table" then
    cache = translation_queue.new(player.locale, next_locale_generation(locale_generations, nil, player.index))
    translations[player.index] = cache
  elseif cache.locale ~= player.locale then
    translation_queue.invalidate_locale(cache, player.locale,
      next_locale_generation(locale_generations, cache, player.index))
  end
  return cache
end

local function catalogue_translation_token(catalogue_snapshot)
  local names = {}
  for _, row in ipairs(catalogue_snapshot.rows or {}) do names[#names + 1] = row.key end
  -- The Factorio adapter already sorts the bounded technology-ID list.  Keep
  -- this exact token only in the player-local host cache: it is never source
  -- of research policy or shared game state.
  return names, table.concat(names, "\30")
end

local function ensure_translation_catalogue(player, catalogue_snapshot)
  local cache = translation_cache(player)
  local names, token = catalogue_translation_token(catalogue_snapshot)
  if cache.catalogue_token ~= token then translation_queue.reset_catalogue(cache, names, token) end
  return cache
end

local function pump_translation_requests(player, cache)
  if not (player and player.valid and player.connected) then return end
  local work = 0
  while translation_queue.can_request(cache) and work < translation_queue.request_work_limit do
    local key = translation_queue.pop(cache)
    if not key then break end
    work = work + 1
    local technology = player.force.technologies[key]
    if technology then
      translation_queue.dispatch(cache, key, game.tick, function()
        return player.request_translation(technology.localised_name)
      end)
    else
      -- request_translation may decline malformed data without issuing an ID;
      -- it never consumes a pending slot in that case.
      translation_queue.request_declined(cache, key)
    end
  end
end

local function unresolved_translations(cache)
  return translation_queue.unresolved(cache)
end

local function refresh_translated_view(player, cache)
  if not translation_queue.consume_refresh(cache) then return end
  local frame = player and player.valid and player.gui.screen[ROOT]
  if not (frame and frame.valid) then return end
  local v = view(player)
  if v.tab ~= "research" then return end
  local body = active_body(player, "research")
  local results = body and body[PREFIX .. "research_results"]
  if not (body and body.valid and results and results.valid) then return end
  -- A partial index only changes lookup metadata. Native captions already
  -- show through Factorio immediately, so do not rescan the force catalogue
  -- or rebuild detail/rows for every eight completed translations.
  if not translation_queue.complete(cache) then
    update_translation_index(results, cache, v)
    return
  end
  if v.search == "" and v.sort ~= "name-asc" and v.sort ~= "name-desc" then
    update_translation_index(results, cache, v)
    return
  end
  -- An active search may depend on the localized index and Name ordering has
  -- deliberately waited for this settled generation. Rebuild once now, while
  -- retaining the frame, fields, filters and scroll pane.
  local c = catalogue(player.force)
  if not c or ensure_translation_catalogue(player, c) ~= cache then return end
  if not translation_queue.complete(cache) then
    if needs_name_index(v) then pump_translation_requests(player, cache) end
    update_translation_index(results, cache, v)
    return
  end
  local pages = update_research_results(player, results, v, c, cache)
  update_navigation(frame, v, pages)
end
local function label(parent, caption, maximum_width)
  local element = parent.add{type = "label", caption = caption}
  element.style.single_line = false
  element.style.maximal_width = maximum_width or 720
  return element
end
local function fact_label(parent, key, caption, maximum_width)
  local element = parent.add{
    type = "label",
    name = PREFIX .. "fact_" .. key,
    caption = caption,
    tags = {mir_browser_fact = key}
  }
  element.style.single_line = false
  element.style.maximal_width = maximum_width or 720
  return element
end
local function section(parent, caption, width)
  local divider = parent.add{type = "line", direction = "horizontal"}
  divider.style.width = width
  divider.style.top_margin, divider.style.bottom_margin = 10, 4
  local heading = label(parent, caption, width)
  heading.style.font = "default-bold"
  heading.style.bottom_margin = 4
  return heading
end

update_translation_index = function(results, cache, v)
  -- Share the fixed count row instead of adding another child below a short
  -- list. Localization progress must not enlarge the retained result region.
  local list = results and results[PREFIX .. "research_list"]
  local indicator = list and list.valid and list[PREFIX .. "result_count"]
  if not (indicator and indicator.valid) then return end
  local count = indicator.tags.mir_browser_count or 0
  local unresolved = unresolved_translations(cache)
  if unresolved <= 0 or not needs_name_index(v) then
    indicator.caption, indicator.tooltip = {"mir-browser.count", count}, nil
    indicator.tags = {mir_browser_count = count}
    return
  end
  local name_order = v.sort == "name-asc" or v.sort == "name-desc"
  local caption = name_order and {"mir-browser.indexing-name", unresolved}
    or {"mir-browser.indexing", unresolved}
  indicator.caption = {"", {"mir-browser.count", count}, " · ", caption}
  indicator.tooltip = caption
  indicator.tags = {mir_browser_count = count, mir_browser_fact = "translation_index"}
end

local function button(parent, action, caption, tags)
  tags = tags or {}; tags.mir_browser = action
  return parent.add{type = "button", caption = caption, tags = tags}
end

local function icon_button(parent, action, sprite, tooltip)
  local control = parent.add{
    type = "sprite-button", style = "tool_button", sprite = sprite,
    tooltip = tooltip, tags = {mir_browser = action}
  }
  control.style.width, control.style.height = 32, 32
  return control
end
local function set_shortcut_toggled(player, toggled)
  if player and player.valid and player.set_shortcut_toggled then
    player.set_shortcut_toggled(SHORTCUT, toggled == true)
  end
end
local function remove_legacy_top_button(player)
  local legacy = player and player.gui and player.gui.top and player.gui.top[PREFIX .. "open"]
  if legacy then legacy.destroy() end
end
local function close(player, preserve_shortcut_state)
  if not player then return end
  local pending = state().pending_search_refresh
  pending[player.index] = nil
  if next(pending) == nil then set_search_refresh_subscription(false) end
  local frame = player.gui.screen[ROOT]
  if frame then
    view(player).location = frame.location
    frame.destroy()
  end
  if not preserve_shortcut_state then set_shortcut_toggled(player, false) end
end
local function family_caption(family)
  if family == "mir" then return {"mir-browser.scope-mir"} end
  if family == "all" then return {"mir-browser.scope-all"} end
  if family == "external" then return {"mir-browser.scope-native"} end
  local stream = streams.view()[family]
  local fallback = tostring(family):gsub("[-_]", " "):gsub("^%l", string.upper)
  return stream and {"?", stream.localised_name or {"technology-name.more-infinite-research." .. family}, fallback} or fallback
end

local function same_value(left, right)
  return type(left) == type(right) and left == right
end

local function shown_value(value)
  if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
    local compact = string.format("%.6g", value)
    return tonumber(compact) == value and compact or "≈ " .. compact
  end
  local shown = tostring(value)
  if #shown > 120 then return string.sub(shown, 1, 117) .. "..." end
  return shown
end

-- Startup settings apply before a save loads. The surface shows the current
-- resolver result, but it never writes startup values or activates bad input.
local function imported_profile_summary()
  local imported = settings.startup and settings.startup[codec.import_setting_name]
  local text = imported and imported.value
  if type(text) ~= "string" or text == "" then return {state = "none"} end
  local decoded, err = codec.decode(text)
  if not decoded then return {state = "invalid", error = tostring(err or "decode failed")} end
  local recognized, unknown, invalid = codec.count_recognized_settings(decoded)
  return {
    state = "active",
    profile = decoded,
    recognized = recognized,
    unknown = unknown,
    invalid = invalid
  }
end

local function profile_summary_caption(summary)
  if summary.state == "active" then
    return {"mir-browser.profile-active", summary.recognized, summary.invalid}
  end
  if summary.state == "invalid" then
    return {"mir-browser.profile-invalid"}
  end
  return {"mir-browser.profile-none"}
end

local function startup_comparison(name, prototype, profile_summary)
  local direct = settings.startup and settings.startup[name]
  local raw_direct = direct and direct.value
  local effective = startup_settings.get(name)
  local source = same_value(raw_direct, effective) and "direct" or "unresolved"
  if profile_summary.state == "active" then
    local imported = profile_summary.profile.settings and profile_summary.profile.settings[name]
    if imported ~= nil and settings_catalog.validate_value(name, imported)
        and same_value(imported, effective) then source = "mirset1" end
  end
  return {default = prototype.default_value, raw_direct = raw_direct, effective = effective, source = source}
end

local function setting_field_caption(name, key, prototype)
  if name == "ips-effect-per-level-" .. key or name == "mir-effect-per-level-" .. key then
    local stream = streams.view()[key]
    local effect = stream and stream.descriptor and stream.descriptor.effect
    return {"mir-browser.setting-effect-per-level" .. (effect and effect.unit == "percent" and "-percent" or "")}
  end
  -- The group already names the research. Only its six standard controls can
  -- use a shorter field name; other settings retain their authored identity.
  for _, field in ipairs({"enable", "cost-base", "cost-linear-increment", "cost-growth", "max-level", "research-time"}) do
    if name == "ips-" .. field .. "-" .. key or name == "mir-" .. field .. "-" .. key then
      return {"mir-browser.setting-" .. field}
    end
  end
  if name ~= key then return prototype.localised_name end
end

local function startup_setting_caption(name, key, prototype, comparison)
  local caption = setting_field_caption(name, key, prototype)
  local value = name:find("%-max%-level%-", 1) and comparison.effective == 0
    and {"mir-browser.setting-unlimited"} or shown_value(comparison.effective)
  return caption and {"", caption, ": ", value} or value
end

local function settings_rows(player, parent, v)
  local groups, assigned = {}, {}
  local profile_summary = imported_profile_summary()
  local function search_text(value)
    return string.lower(value):gsub("[-_]", " "):gsub("%s+", " ")
  end
  local search = search_text(v.settings_search or "")
  local function group(key, title, specs, scope)
    local names, matches = {}, search == "" or string.find(search_text(key), search, 1, true)
    for _, spec in ipairs(specs) do
      local prototype = prototypes.mod_setting[spec.name]
      if prototype and prototype.mod == "more-infinite-research" then
        names[#names + 1] = spec.name
        assigned[spec.name] = true
        if string.find(search_text(spec.name), search, 1, true) then matches = true end
      end
    end
    if matches and #names > 0 then groups[#groups + 1] = {key = key, title = title, names = names, scope = scope} end
  end
  for key, stream in pairs(streams.view()) do
    local required_item = type(stream.required_items) == "table" and stream.required_items[1]
    local fallback = type(required_item) == "string" and required_item or key
    fallback = fallback:gsub("[-_]", " "):gsub("^%l", string.upper)
    group(key, {"?", stream.localised_name or {"technology-name.more-infinite-research." .. key}, fallback},
      settings_catalog.stream_setting_specs(key, stream), "research")
  end
  for _, spec in ipairs(settings_catalog.base_extension_specs()) do
    group(spec.key, {"technology-name." .. (spec.locale_key or spec.key)}, settings_catalog.base_extension_setting_specs(spec.key), "research")
  end
  for name, prototype in pairs(prototypes.mod_setting) do
    if prototype.mod == "more-infinite-research" and not assigned[name] then group(name, prototype.localised_name, {{name = name}}, "options") end
  end
  local visible = {}
  for _, g in ipairs(groups) do if g.scope == v.settings_scope then visible[#visible + 1] = g end end
  groups = visible
  table.sort(groups, function(a,b) return a.key < b.key end)
  local selected
  for _, g in ipairs(groups) do if g.key == v.setting_selection then selected = g end end
  selected = selected or groups[1]
  v.setting_selection = selected and selected.key or nil
  local list_width, detail_width, stacked = settings_pane_widths(player)
  local toolbar = parent[PREFIX .. "settings_toolbar"]
  if not toolbar then
    toolbar = parent.add{type = "flow", name = PREFIX .. "settings_toolbar"}
    button(toolbar, "settings-research", {"mir-browser.settings-scope-research"})
    button(toolbar, "settings-options", {"mir-browser.settings-scope-options"})
  end
  local panes = parent[PREFIX .. "settings_panes"]
  if not panes then panes = parent.add{type = "flow", name = PREFIX .. "settings_panes", direction = stacked and "vertical" or "horizontal"} end
  local list = panes[PREFIX .. "settings_list"]
  if not list then list = panes.add{type = "list-box", name = PREFIX .. "settings_list", items = {}, tags = {mir_browser = "setting-list", mir_browser_section = "settings-list"}} end
  local items, keys, selected_index = {}, {}, 0
  for i,g in ipairs(groups) do
    items[i], keys[i] = g.title, g.key
    if selected and selected.key == g.key then selected_index = i end
  end
  local token = table.concat(keys, "\30")
  if v.settings_list_token ~= token or #list.items ~= #items then list.items = items; v.settings_list_token = token end
  v.setting_keys = keys
  list.selected_index = selected_index
  local pane_height = math.max(80, research_panes_height(parent) - 44)
  list.style.width, list.style.height = list_width, stacked and math.floor(pane_height * 0.32) or pane_height
  local detail = panes[PREFIX .. "settings_detail"]
  if not detail then detail = panes.add{type = "scroll-pane", name = PREFIX .. "settings_detail", direction = "vertical", tags = {mir_browser_section = "settings-detail"}} end
  detail.horizontal_scroll_policy = "never"
  detail.style.width, detail.style.height = detail_width, stacked and math.floor(pane_height * 0.65) or pane_height
  local detail_token = (selected and selected.key or "") .. ":" .. v.settings_scope
  if #detail.children > 0 and v.settings_detail_token == detail_token then return end
  v.settings_detail_token = detail_token
  detail.clear()
  if #groups == 0 then label(detail, {"mir-browser.settings-empty"}, detail_width - 24) end
  if selected then
    label(detail, selected.title, detail_width - 24).style.font = "default-large-bold"
    label(detail, {"mir-browser.scope-startup"}, detail_width - 24)
    section(detail, {"mir-browser.effective-values"}, detail_width - 24)
    local fields = detail.add{type = "table", column_count = 2}
    fields.style.horizontal_spacing = 12
    fields.style.vertical_spacing = 10
    local field_width = math.floor((detail_width - 40) * 0.55)
    local value_width = detail_width - 40 - field_width
    for _, name in ipairs(selected.names) do
      local prototype = prototypes.mod_setting[name]
      local scope = prototype.setting_type
      local values = scope == "runtime-global" and settings.global or scope == "runtime-per-user" and settings.get_player_settings(player) or settings.startup
      local value = values and values[name] and values[name].value
      local field_caption = name == selected.key and {"mir-browser.value"}
        or setting_field_caption(name, selected.key, prototype) or prototype.localised_name
      local caption = label(fields, field_caption, field_width)
      caption.style.font = "default-semibold"
      caption.tooltip = prototype.localised_description
      if scope == "startup" then
        local comparison = startup_comparison(name, prototype, profile_summary)
        local effective = comparison.effective
        local display = type(effective) == "boolean"
          and {"mir-browser.setting-" .. (effective and "on" or "off")}
          or (name:find("%-max%-level%-", 1) and effective == 0
            and {"mir-browser.setting-unlimited"} or shown_value(effective))
        if not same_value(effective, comparison.default) then
          local default = type(comparison.default) == "boolean"
            and {"mir-browser.setting-" .. (comparison.default and "on" or "off")}
            or (name:find("%-max%-level%-", 1) and comparison.default == 0
              and {"mir-browser.setting-unlimited"} or shown_value(comparison.default))
          display = {"mir-browser.setting-with-default", display, default}
        end
        local field = label(fields, display, value_width)
        field.tags = {mir_browser_setting = name, mir_browser_read_only = true}
        field.tooltip = {"mir-browser.setting-provenance", shown_value(comparison.raw_direct),
          shown_value(comparison.default), {"mir-browser.source-" .. comparison.source}}
        if comparison.source == "mirset1" then
          label(fields, {"mir-browser.profile-override"}, field_width)
          label(fields, {"mir-browser.source-mirset1"}, value_width)
        end
      elseif type(value) == "boolean" and (scope ~= "runtime-global" or player.admin) then
        fields.add{type = "checkbox", state = value, caption = "", tags = {mir_browser = "setting", setting = name}}
      else
        label(fields, shown_value(value), value_width)
      end
    end
    section(detail, {"mir-browser.configuration-source"}, detail_width - 24)
    fact_label(detail, "profile_import", profile_summary_caption(profile_summary), detail_width - 24)
  end
  return 1
end

local function add_technology_icon(parent, technology, size)
  local icon = parent.add{type = "sprite", style = "recipe_tooltip_horizontal_image",
    sprite = "technology/" .. technology.name, resize_to_sprite = false, tooltip = technology.localised_name}
  icon.style.width = size or 32
  icon.style.height = size or 32
  return icon
end
local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value >= 0
end
local function displayed_number(value)
  if not finite_nonnegative(value) then return nil end
  local rounded = math.floor(value * 100 + 0.5) / 100
  local text = string.format("%.2f", rounded)
  text = string.gsub(text, "0+$", "")
  return (string.gsub(text, "%.$", ""))
end
local function displayed_percent(value)
  return displayed_number(value * 100)
end
local function add_research_cost(parent, technology, maximum_width)
  if #technology.research_unit_ingredients == 0 then return end
  local units = displayed_number(technology.research_unit_count)
  -- Runtime research energy uses ticks; prototype unit.time uses seconds.
  -- Keep this as the unmodified unit duration, independent of lab speed/UPS.
  local ticks = technology.research_unit_energy
  local seconds = finite_nonnegative(ticks) and displayed_number(ticks / 60)
  if units and seconds then fact_label(parent, "research_cost", {"mir-browser.research-cost", units, seconds}, maximum_width) end
end
local function add_science_icons(parent, technology, maximum_width)
  if #technology.research_unit_ingredients == 0 then return end
  label(parent, {"mir-browser.science"}, maximum_width)
  local science = parent.add{type = "table", column_count = math.max(1, math.min(8, math.floor((maximum_width or 720) / 40)))}
  for _, ingredient in ipairs(technology.research_unit_ingredients) do
    local amount = displayed_number(ingredient.amount)
    science.add{
      type = "sprite",
      sprite = "item/" .. ingredient.name,
      tooltip = amount and {"mir-browser.science-ingredient", amount, {"item-name." .. ingredient.name}}
        or {"item-name." .. ingredient.name}
    }
  end
end
local function productivity_summary(benefits)
  if type(benefits) ~= "table" or #benefits == 0 then return nil end
  local summary = {count = 0}
  for _, benefit in ipairs(benefits) do
    local increment = benefit and benefit.effect_change
    local current = benefit and benefit.current_productivity_bonus
    local maximum = benefit and benefit.maximum_productivity
    if not finite_nonnegative(increment) or increment <= 0
      or not finite_nonnegative(current) or not finite_nonnegative(maximum) or current > maximum then
      return nil
    end
    summary.count = summary.count + 1
    summary.increment_min = summary.increment_min and math.min(summary.increment_min, increment) or increment
    summary.increment_max = summary.increment_max and math.max(summary.increment_max, increment) or increment
    summary.current_min = summary.current_min and math.min(summary.current_min, current) or current
    summary.current_max = summary.current_max and math.max(summary.current_max, current) or current
    summary.maximum_min = summary.maximum_min and math.min(summary.maximum_min, maximum) or maximum
    summary.maximum_max = summary.maximum_max and math.max(summary.maximum_max, maximum) or maximum
  end
  return summary
end
local function add_productivity_summary(parent, benefits, maximum_width)
  local summary = productivity_summary(benefits)
  if not summary then return end
  local increment_min, increment_max = displayed_percent(summary.increment_min), displayed_percent(summary.increment_max)
  local current_min, current_max = displayed_percent(summary.current_min), displayed_percent(summary.current_max)
  local maximum_min, maximum_max = displayed_percent(summary.maximum_min), displayed_percent(summary.maximum_max)
  if not (increment_min and increment_max and current_min and current_max and maximum_min and maximum_max) then return end
  if increment_min == increment_max then
    fact_label(parent, "productivity_increment", {"mir-browser.productivity-increment", increment_min}, maximum_width)
  else
    fact_label(parent, "productivity_increment", {"mir-browser.productivity-increment-range", increment_min, increment_max}, maximum_width)
  end
  if current_min == current_max and maximum_min == maximum_max then
    fact_label(parent, "productivity_current_cap", {"mir-browser.productivity-current-cap", current_min, maximum_min}, maximum_width)
  else
    fact_label(parent, "productivity_current_cap", {"mir-browser.productivity-current-cap-range", current_min, current_max, maximum_min, maximum_max}, maximum_width)
  end
end
local function add_prerequisite_icons(parent, technology, maximum_width)
  local prerequisites = {}
  for _, prerequisite in pairs(technology.prerequisites) do prerequisites[#prerequisites + 1] = prerequisite end
  if #prerequisites == 0 then return end
  table.sort(prerequisites, function(left, right) return left.name < right.name end)
  label(parent, {"mir-browser.prerequisites"}, maximum_width)
  local row = parent.add{type = "table", column_count = math.max(1, math.min(8, math.floor((maximum_width or 720) / 40)))}
  for index, prerequisite in ipairs(prerequisites) do
    add_technology_icon(row, prerequisite)
  end

end
local function status_caption(technology, native_technology)
  if technology.researched then return {"mir-browser.status-complete"} end
  if technology.queued then return {"mir-browser.status-queued"} end
  if technology.available then return {"mir-browser.status-ready"} end
  if native_technology and native_technology.enabled == false then return {"mir-browser.status-disabled"} end
  return {"mir-browser.status-locked"}
end
local function research_setting_specs(portable)
  -- This independent witness describes the controller's own startup binding,
  -- not a compiler action or ownership claim. Its declared key came from the
  -- validated policy construction; native technology names are not decoded.
  local runtime_binding = portable and portable.runtime_settings_binding
  local declared = runtime_binding and runtime_binding.binding and runtime_binding.binding.declared_key
  if runtime_binding and runtime_binding.source == "generated-stream" then
    local stream = streams.get(declared)
    if stream and runtime_binding.binding.setting_name == "ips-max-level-" .. declared then
      return declared, settings_catalog.stream_setting_specs(declared, stream)
    end
  elseif runtime_binding and runtime_binding.source == "base-continuation" then
    for _, spec in ipairs(settings_catalog.base_extension_specs()) do
      if spec.key == declared and runtime_binding.binding.setting_name == "mir-max-level-" .. declared then
        return declared, settings_catalog.base_extension_setting_specs(declared)
      end
    end
  end
end
local function add_research_startup_settings(parent, portable, maximum_width)
  local key, specs = research_setting_specs(portable)
  if not specs then return end
  local profile_summary = imported_profile_summary()
  local rows = {}
  for _, spec in ipairs(specs) do
    local prototype = prototypes.mod_setting[spec.name]
    if prototype and prototype.mod == "more-infinite-research" and prototype.setting_type == "startup" then
      local comparison = startup_comparison(spec.name, prototype, profile_summary)
      if settings_catalog.validate_value(spec.name, comparison.effective) then
        rows[#rows + 1] = {name = spec.name, prototype = prototype, comparison = comparison}
      end
    end
  end
  if #rows == 0 then return end
  section(parent, {"mir-browser.research-startup-settings"}, maximum_width)
  label(parent, {"mir-browser.scope-startup"}, maximum_width)
  for _, row in ipairs(rows) do
    local field
    if type(row.comparison.effective) == "boolean" then
      field = parent.add{
        type = "checkbox", state = row.comparison.effective,
        caption = setting_field_caption(row.name, key, row.prototype) or ""
      }
      field.enabled = false
    else
      field = label(parent, startup_setting_caption(row.name, key, row.prototype, row.comparison), maximum_width)
    end
    field.tags = {
      mir_browser_setting = row.name, mir_browser_read_only = true,
      mir_browser_research_technology = portable.technology.key
    }
  end
end
local function detail(player, parent, v, c, width)
  if not v.selected then label(parent, {"mir-browser.no-results"}, width - 24); return end
  local portable, reason = resolved_detail(player.force, c, v.selected)
  local tech = portable and player.force.technologies[portable.technology.key]
  if not tech then
    label(parent, {"mir-browser.detail-unavailable", reason or "no-selection"}, width - 24)
    return
  end
  local container = parent
  local pane_height = parent.style.maximal_height
  local recipe_index = core.detail_recipe_index(c, tech.name, c.enrichment)
  local has_recipes = recipe_index and #recipe_index.ids > 0
  local compact_detail = pane_height < 200
  local recipe_height = has_recipes and math.min(#recipe_index.ids * 28 + 8, math.max(32, math.floor(pane_height * 0.28))) or 0
  parent = container.add{type = "scroll-pane", name = PREFIX .. "research_facts", direction = "vertical"}
  parent.horizontal_scroll_policy = "never"
  parent.style.width = width
  parent.style.height = has_recipes and not compact_detail and math.max(60, pane_height - recipe_height - 70) or pane_height
  local maximum_width = math.max(120, width - 16)
  local heading_width = math.max(120, maximum_width - 56)
  local heading = parent.add{type = "flow", direction = "horizontal"}
  add_technology_icon(heading, tech, 48)
  label(heading, tech.localised_name, heading_width).style.font = "default-large-bold"
  local enrichment = portable.enrichment or {}
  -- Provider ownership, compiler disposition, route sentinels, and raw
  -- setting provenance remain in the copied DTO for governed consumers. They
  -- are not player-facing research facts in this library surface.
  section(parent, {"mir-browser.benefits"}, maximum_width)
  if not has_recipes then label(parent, {"?", tech.localised_description, ""}, maximum_width) end
  local runtime_binding = portable.runtime_settings_binding
  local registered_binding = runtime_binding and research_setting_specs(portable)
  local effective_cap = portable.technology.cap
    or (registered_binding and runtime_binding.state == "finite" and runtime_binding.selected_effective)
  if enrichment.recipe_benefits then
    local count = enrichment.recipe_benefit_count or #enrichment.recipe_benefits
    if not enrichment.next_level_has_effective_benefit then
      label(parent, {"mir-browser.no-next-benefit", count}, maximum_width)
    end
  end
  local summary = recipe_index and recipe_index.summary
  if summary and summary.count > 0 then
    local low, high = displayed_percent(summary.effect_change_min), displayed_percent(summary.effect_change_max)
    fact_label(parent, "productivity_increment", low == high and {"mir-browser.productivity-increment", low}
      or {"mir-browser.productivity-increment-range", low, high}, maximum_width)
    local current_low, current_high = displayed_percent(summary.current_productivity_bonus_min), displayed_percent(summary.current_productivity_bonus_max)
    local maximum_low, maximum_high = displayed_percent(summary.maximum_productivity_min), displayed_percent(summary.maximum_productivity_max)
    fact_label(parent, "productivity_current_cap", current_low == current_high and maximum_low == maximum_high
      and {"mir-browser.productivity-current-cap", current_low, maximum_low}
      or {"mir-browser.productivity-current-cap-range", current_low, current_high, maximum_low, maximum_high}, maximum_width)
  end
  section(parent, {"mir-browser.research-requirements"}, maximum_width)
  label(parent, status_caption(portable.technology, tech), maximum_width)
  if effective_cap then
    label(parent, {"mir-browser.level-cap", tech.level, effective_cap}, maximum_width)
  elseif tech.level and tech.level > 1 then label(parent, {"mir-browser.level", tech.level}, maximum_width) end
  add_research_cost(parent, tech, maximum_width)
  add_science_icons(parent, tech, maximum_width)
  add_prerequisite_icons(parent, tech, maximum_width)
  section(parent, {"mir-browser.actions"}, maximum_width)
  button(parent, "open-vanilla", {"mir-browser.open-research"}, {technology = tech.name}).tooltip = {"mir-browser.native-queue-guidance"}
  button(parent, "toggle-hide", v.hidden and v.hidden[tech.name] and {"mir-browser.show"} or {"mir-browser.hide"}, {technology = tech.name}).tooltip = {"mir-browser.hide-tooltip"}
  button(parent, "inspect-settings", {"mir-browser.inspect-settings"}, {technology = tech.name}).enabled = registered_binding ~= nil or portable.technology.family ~= "external"
  add_research_startup_settings(parent, portable, maximum_width)
  if has_recipes then
    local recipe_parent = compact_detail and parent or container
    label(recipe_parent, {"mir-browser.affected-recipes"}, width - 24).style.font = "default-bold"
    local items = {}
    for i,id in ipairs(recipe_index.ids) do
      local recipe = player.force.recipes[id]
      items[i] = {"", "[img=recipe/" .. id .. "] ", recipe and recipe.prototype.localised_name or id}
    end
    v.recipe_ids = recipe_index.ids
    local list = recipe_parent.add{type = compact_detail and "drop-down" or "list-box", name = PREFIX .. "recipe_entries", items = items, tags = {mir_browser = "recipe-list", mir_browser_section = "recipe-list"}}
    list.style.width = compact_detail and width - 24 or width
    if not compact_detail then list.style.height = recipe_height end
    list.tooltip = {"mir-browser.recipe-select-hint"}
    if not compact_detail then label(container, {"mir-browser.recipe-select-hint"}, width - 24) end
  end
end
local function filter_dropdown(parent, caption, items, selected_index, action, width)
  local field = parent.add{type = "flow", direction = "vertical"}
  if parent.tags.compact ~= true then label(field, caption, width) end
  local dropdown = field.add{type = "drop-down", items = items, selected_index = selected_index, tags = {mir_browser = action}, tooltip = caption}
  dropdown.style.width = width
  return dropdown
end
local function has_family(family_names, family)
  for _, candidate in ipairs(family_names) do if candidate == family then return true end end
  return false
end

local function query_view(v, cache)
  return {
    mode = v.mode, status = v.status, page = v.page, search = v.search,
    family = v.family, sort = v.sort, hidden = v.hidden,
    fallback_sort = v.stable_sort,
    name_index_ready = translation_queue.complete(cache)
  }
end

local function prioritize_visible_translations(cache, page, selected)
  local keys = {}
  if type(selected) == "string" then keys[#keys + 1] = selected end
  for _, row in ipairs(page.rows or {}) do keys[#keys + 1] = row.key end
  local token = table.concat(keys, "\30")
  if cache.priority_token ~= token then
    translation_queue.prioritize(cache, keys)
    cache.priority_token = token
  end
end

-- The catalogue snapshot is already bounded and query() records whether the
-- current selection remains in the full filtered result before it slices one
-- page. Do not run another ordering pass merely to retain Browse detail.
local function selected_subject_is_visible(player, page, selected)
  return type(selected) == "string" and player.force.technologies[selected]
    and page and page.selected_visible == true
end

local function select_first_visible_subject(player, v, page)
  if selected_subject_is_visible(player, page, v.selected) then return end
  v.selected, v.effect_page = nil, 1
  for _, row in ipairs(page.rows or {}) do
    if type(row.key) == "string" and player.force.technologies[row.key] then
      v.selected = row.key
      return
    end
  end
end

local function queue_rows(player, queue, v)
  local entries = player.force.research_queue or {}
  local maximum_width = dimensions(player) - 96
  local list = queue[PREFIX .. "queue_list"]
  if not list then
    label(queue, {"mir-browser.native-queue-guidance"}, maximum_width)
    button(queue, "open-vanilla", {"controls.open-technology-gui"})
    label(queue, {"mir-browser.queue"})
    list = queue.add{type = "list-box", name = PREFIX .. "queue_list", items = {}, tags = {mir_browser = "queue-list"}}
    list.style.width = maximum_width
    list.style.height = math.max(48, queue.style.maximal_height - 130)
    local empty = label(queue, {"mir-browser.queue-empty"}, maximum_width)
    empty.name = PREFIX .. "queue_empty"
  end
  local items, keys, token = {}, {}, {}
  for index, technology in ipairs(entries) do
    items[index] = {"", tostring(index) .. ". ", technology.localised_name}
    keys[index], token[index] = technology.name, technology.name .. ":" .. technology.level
  end
  token = table.concat(token, "\30")
  if v.queue_token ~= token or #list.items ~= #items then list.items = items; v.queue_token = token end
  v.queue_keys = keys
  queue[PREFIX .. "queue_empty"].visible = #items == 0
  return 1
end

local omission_reasons = {
  covered_by_existing_infinite_native_modifier = "not-added-provided",
  covered_by_existing_infinite_recipe_productivity = "not-added-provided",
  covered_by_planned_stream = "not-added-grouped",
  covered_by_planned_operation = "not-added-grouped",
  no_valid_effect_targets = "not-added-no-effect",
  no_available_direct_effects = "not-added-no-effect",
  no_useful_native_effect_increment = "not-added-no-effect",
  automatic_family_not_reviewed = "not-added-review",
  disabled = "not-added-disabled",
  no_matching_recipes = "not-added-no-recipe",
  no_lab_compatible_science = "not-added-no-science",
  ["configured-material-cap-before-continuation"] = "not-added-material-cap",
  ["no-continuation-headroom"] = "not-added-material-headroom",
  recipe_productivity_unsupported = "not-added-unsupported"
}

local function bounded_string(value)
  return type(value) == "string" and value ~= "" and #value <= core.detail_string_limit
end

local function omission_reason_caption(reason)
  local key = omission_reasons[reason]
  if key then return {"mir-browser." .. key} end
  for _, requirement in ipairs{{"mod", "not-added-needs-mod"}, {"item", "not-added-needs-item"}, {"fluid", "not-added-needs-fluid"}} do
    local identity = reason:match("^missing required " .. requirement[1] .. " ([%w_%-%.]+)$")
    if identity then return {"mir-browser." .. requirement[2], identity} end
  end
  return {"mir-browser.not-added-generic"}
end

-- This display is deliberately a terminal viewer. Its provider envelope is
-- validated again at the UI edge and omitted rows have no technology action,
-- queue action, or deep link. A malformed row yields no player claim.
local function availability_rows(player, parent, v)
  local envelope = mir_provider.omissions(player.force)
  if type(envelope) ~= "table" or envelope.schema ~= 1
      or envelope.kind ~= "portable-research-omissions" or type(envelope.rows) ~= "table"
      or #envelope.rows > core.catalogue_limit then
    label(parent, {"mir-browser.availability-unavailable"})
    return 1
  end
  local row_count = 0
  for index in pairs(envelope.rows) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
      label(parent, {"mir-browser.availability-unavailable"})
      return 1
    end
    row_count = row_count + 1
  end
  if row_count ~= #envelope.rows then
    label(parent, {"mir-browser.availability-unavailable"})
    return 1
  end
  local rows, seen, stream_definitions = {}, {}, streams.view()
  for index = 1, #envelope.rows do
    local row = envelope.rows[index]
    if type(row) ~= "table"
        or not bounded_string(row.stream_id) or not bounded_string(row.reason)
        or not bounded_string(row.decision_fingerprint) or row.status ~= "not-added"
        or (row.technology_id ~= nil and not bounded_string(row.technology_id)) then
      label(parent, {"mir-browser.availability-unavailable"})
      return 1
    end
    local identity = row.stream_id .. "\0" .. (row.technology_id or "")
    local stream = stream_definitions[row.stream_id]
    if seen[identity] or not stream then
      label(parent, {"mir-browser.availability-unavailable"})
      return 1
    end
    seen[identity] = true
    -- Omitted streams may describe items supplied only by an absent mod. Their
    -- authored name then contains an item-name key that this player cannot
    -- translate; keep the authored name when valid and show a readable stable
    -- identity otherwise.
    local required_item = type(stream.required_items) == "table" and stream.required_items[1]
    local fallback_name = type(required_item) == "string" and required_item or row.stream_id
    fallback_name = fallback_name:gsub("[-_]", " "):gsub("^%l", string.upper)
    local fallback_caption = type(required_item) == "string"
      and {"", {"description.productivity-bonus"}, ": ", fallback_name}
      or fallback_name
    rows[#rows + 1] = {
      caption = {"?", stream.localised_name or {"technology-name.more-infinite-research." .. row.stream_id}, fallback_caption},
      reason = row.reason
    }
  end
  if #rows == 0 then
    label(parent, {"mir-browser.availability-empty"})
    return 1
  end

  local width = dimensions(player) - 96
  local items = {}
  for index, row in ipairs(rows) do items[index] = row.caption end
  local selected = math.min(#items, math.max(1, v.omission_selection or 1))
  local list = parent.add{type = "list-box", items = items, selected_index = selected,
    tags = {mir_browser = "omission-list", mir_browser_section = "availability"}}
  list.style.width = width
  list.style.height = math.max(32, parent.style.maximal_height - 104)
  local explanation = label(parent, omission_reason_caption(rows[selected].reason), width)
  explanation.name = PREFIX .. "omission_reason"
  explanation.style.font = "default-semibold"
  return 1
end

-- This is the only part of Browse that translation callbacks may rebuild.
-- The surrounding frame, fixed filters, navigation and search text field are
-- intentionally retained, so localized discovery can finish in place.
update_research_results = function(player, results, v, c, cache)
  local list_width, detail_width, stacked = research_pane_widths(player)
  local panes_height = research_panes_height(results)
  local list_column = results[PREFIX .. "research_list"]
  if not list_column then
    list_column = results.add{type = "flow", name = PREFIX .. "research_list", direction = "vertical"}
    list_column.add{type = "label", name = PREFIX .. "result_count"}
    list_column.add{type = "list-box", name = PREFIX .. "research_entries", items = {}, tags = {mir_browser = "research-list", mir_browser_section = "research-list"}}
  end
  local list = list_column[PREFIX .. "research_entries"]
  local detail_pane = results[PREFIX .. "research_detail"]
  if not detail_pane then
    detail_pane = results.add{type = "flow", name = PREFIX .. "research_detail", direction = "vertical", tags = {mir_browser_section = "research-detail"}}
  end
  list_column.style.width = list_width
  list.style.width, list.style.height = list_width, stacked and math.floor(panes_height * 0.30) or math.max(28, panes_height - 28)
  detail_pane.style.width, detail_pane.style.height = detail_width, stacked and math.floor(panes_height * 0.62) or panes_height
  local query = query_view(v, cache)
  if v.visibility == 2 then query.hidden = nil end
  local found = core.query_all(c, query, c.enrichment, cache.values, v.selected)
  if v.visibility == 2 then
    local hidden = {}
    for _, row in ipairs(found.rows) do if v.hidden and v.hidden[row.key] then hidden[#hidden + 1] = row end end
    found.rows, found.count, found.selected_visible = hidden, #hidden, false
    for _, row in ipairs(hidden) do if row.key == v.selected then found.selected_visible = true end end
  end
  select_first_visible_subject(player, v, found)
  local items, keys, token, selected_index = {}, {}, {}, 0
  for i,row in ipairs(found.rows) do
    local tech = player.force.technologies[row.key]
    items[i] = {"", "[img=technology/" .. row.key .. "] ", tech.localised_name}
    keys[i], token[i] = row.key, row.key .. ":" .. tostring(tech.level)
    if row.key == v.selected then selected_index = i end
  end
  token = table.concat(token, "\30")
  if v.result_token ~= token or #list.items ~= #items then list.items = items; v.result_token = token end
  v.result_keys = keys
  list.selected_index = selected_index
  local count_label = list_column[PREFIX .. "result_count"]
  count_label.caption, count_label.tags = {"mir-browser.count", found.count}, {mir_browser_count = found.count}
  count_label.style.width, count_label.style.height = list_width, 24
  local technology = v.selected and player.force.technologies[v.selected]
  local detail_token = table.concat({v.selected or "", tostring(v.visibility), tostring(player.force.index),
    tostring(technology and technology.level), tostring(technology and technology.researched),
    tostring(v.hidden and v.hidden[v.selected]), player.locale}, ":")
  local replace_detail = #detail_pane.children == 0 or v.detail_token ~= detail_token
  if replace_detail then detail_pane.clear(); v.detail_token = detail_token end
  if v.visibility == 3 then
    list_column.visible = false
    detail_pane.style.width = dimensions(player) - 64
    detail_pane.style.height = panes_height
    if replace_detail then
    local omissions = detail_pane.add{type = "flow", direction = "vertical"}
    omissions.style.width, omissions.style.height = detail_pane.style.maximal_width, detail_pane.style.maximal_height
    availability_rows(player, omissions, v)
    end
  else
    list_column.visible = true
    if replace_detail then detail(player, detail_pane, v, c, detail_width) end
  end
  if needs_name_index(v) then prioritize_visible_translations(cache, found, v.selected); pump_translation_requests(player, cache) end
  update_translation_index(results, cache, v)
  return 1
end

update_navigation = function() end -- Developer query paging is independent of player navigation.

local function report_text(player)
  local v = view(player)
  local lines = {"MIR Research Library", "Factorio: " .. tostring(script.active_mods.base),
    "MIR: " .. tostring(script.active_mods["more-infinite-research"]),
    "Selected research: " .. tostring(v.selected or "none"),
    "", "ACTIVE MODS"}
  local names = {}
  for name in pairs(script.active_mods) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do lines[#lines + 1] = name .. " " .. script.active_mods[name] end
  if v.report_settings then
    lines[#lines + 1] = "\nEFFECTIVE MIR STARTUP SETTINGS"
    local settings_names = {}
    for name, prototype in pairs(prototypes.mod_setting) do
      if prototype.mod == "more-infinite-research" and prototype.setting_type == "startup"
          and name ~= codec.import_setting_name then settings_names[#settings_names + 1] = name end
    end
    table.sort(settings_names)
    for _, name in ipairs(settings_names) do lines[#lines + 1] = name .. " = " .. tostring(startup_settings.get(name)) end
  end
  if v.report_omissions then
    local envelope = mir_provider.omissions(player.force)
    lines[#lines + 1] = "\nGENERATION DECISIONS"
    if envelope and envelope.rows then
      lines[#lines + 1] = "Omitted research: " .. #envelope.rows
      for i = 1, math.min(250, #envelope.rows) do
        local row = envelope.rows[i]
        lines[#lines + 1] = row.stream_id .. ": " .. row.reason
      end
      if #envelope.rows > 250 then lines[#lines + 1] = "Summary limited to first 250 decisions." end
    else lines[#lines + 1] = "Omission explanations unavailable or invalid." end
  end
  return table.concat(lines, "\n")
end
local function debug_rows(player, body, v, width)
  if #body.children > 0 then return end
  local left_width, right_width, stacked = research_pane_widths(player)
  local height = body.style.maximal_height
  local panes = body.add{type = "flow", direction = stacked and "vertical" or "horizontal"}
  local tools = panes.add{type = "scroll-pane", direction = "vertical"}
  tools.horizontal_scroll_policy = "never"
  tools.style.width, tools.style.height = left_width, stacked and math.floor(height * 0.45) or height
  local text_width = left_width - 20
  section(tools, {"mir-browser.debug-installation"}, text_width)
  label(tools, {"mir-browser.debug-versions", script.active_mods.base, script.active_mods["more-infinite-research"]}, text_width)
  button(tools, "debug-refresh", {"mir-browser.debug-refresh"}).tooltip = {"mir-browser.debug-refresh-tooltip"}
  section(tools, {"mir-browser.report-options"}, text_width)
  for _, option in ipairs{{"report_settings", "report-settings"}, {"report_omissions", "report-omissions"}} do
    local checkbox = tools.add{type = "checkbox", state = v[option[1]] == true, caption = {"mir-browser." .. option[2]}, tags = {mir_browser = option[1]}}
    checkbox.style.maximal_width = text_width
  end
  section(tools, {"mir-browser.configuration"}, text_width)
  label(tools, {"mir-browser.profile-purpose"}, text_width)
  button(tools, "export", {"mir-browser.export"})
  section(tools, {"mir-browser.layout"}, text_width)
  button(tools, "layout-reset", {"mir-browser.reset-layout"})
  section(tools, {"mir-browser.startup-crash"}, text_width)
  label(tools, {"mir-browser.startup-report"}, text_width)
  local preview = panes.add{type = "flow", name = PREFIX .. "report_panel", direction = "vertical"}
  preview.style.width = right_width
  local preview_height = stacked and math.floor(height * 0.50) or height
  section(preview, {"mir-browser.report-preview"}, right_width - 8)
  local text = preview.add{type = "text-box", name = PREFIX .. "report", text = report_text(player)}
  text.read_only, text.word_wrap = true, true
  text.style.width, text.style.height = right_width, math.max(40, preview_height - 144)
  button(preview, "report-select", {"mir-browser.report-select"})
  button(preview, "report-export", {"mir-browser.report-export"})
  local status = label(preview, v.report_status or {"mir-browser.report-local"}, right_width - 8)
  status.name = PREFIX .. "report_status"
  status.tooltip = v.report_destination
end
local function debug_preview(player)
  local body = active_body(player, "help")
  local panes = body and body.children[1]
  return panes and panes[PREFIX .. "report_panel"]
end

render = function(player)
  local v = view(player)
  local width, height = dimensions(player)
  local frame = player.gui.screen[ROOT]
  if frame and not frame[PREFIX .. "tabs"] then close(player, true); frame = nil end
  if not frame then
    frame = player.gui.screen.add{type = "frame", name = ROOT, direction = "vertical"}
    local title = frame.add{type = "flow", name = PREFIX .. "title"}
    title.add{type = "label", caption = {"mir-browser.title"}, style = "frame_title"}
    local drag = title.add{type = "empty-widget", style = "draggable_space_header"}
    drag.style.horizontally_stretchable = true
    drag.style.height = 24
    drag.drag_target = frame
    icon_button(title, "layout-smaller", "utility/left_arrow", {"mir-browser.layout-smaller"})
    icon_button(title, "layout-larger", "utility/right_arrow", {"mir-browser.layout-larger"})
    icon_button(title, "layout-reset", "utility/reset", {"mir-browser.layout-reset"})
    icon_button(title, "close", "utility/close", {"mir-browser.close"})
    local tabs = frame.add{type = "tabbed-pane", name = PREFIX .. "tabs", tags = {mir_browser = "tabs"}}
    local captions = {"research", "queue-tab", "settings", "help"}
    for i,name in ipairs(TAB_NAMES) do
      local tab = tabs.add{type = "tab", caption = {"mir-browser." .. captions[i]}}
      local content = tabs.add{type = "flow", name = PREFIX .. name .. "_content", direction = "vertical"}
      tabs.add_tab(tab, content)
    end
    if v.location then frame.location = v.location else frame.force_auto_center() end
    v.result_token, v.settings_list_token = nil, nil
  end
  frame.style.width, frame.style.height = width, height
  local tabs = frame[PREFIX .. "tabs"]
  local layout_token = tostring(width) .. ":" .. tostring(height)
  if v.layout_token ~= layout_token then
    for _, name in ipairs(TAB_NAMES) do tabs[PREFIX .. name .. "_content"].clear() end
    v.result_token, v.settings_list_token = nil, nil
    v.layout_token = layout_token
    if v.location then
      local scale = player.display_scale
      frame.location = {x = math.max(0, math.min(v.location.x, player.display_resolution.width - width * scale)),
        y = math.max(0, math.min(v.location.y, player.display_resolution.height - height * scale))}
    else frame.force_auto_center() end
  end
  tabs.style.width, tabs.style.height = width - 24, height - 62
  for i,name in ipairs(TAB_NAMES) do if name == v.tab then tabs.selected_tab_index = i end end
  local content = tab_content(frame, v.tab)
  content.style.width, content.style.height = width - 48, height - 112
  local body = content[PREFIX .. "body"]
  if not body then
    if v.tab == "research" or v.tab == "settings" then
      label(content, {"mir-browser." .. (v.tab == "settings" and "search-settings-label" or "search-label")}, width - 64).style.font = "default-semibold"
      local search = content.add{type = "textfield", name = PREFIX .. "search", text = v.tab == "settings" and v.settings_search or v.search,
        tags = {mir_browser = "search", mir_browser_tab = v.tab}, tooltip = {"mir-browser." .. (v.tab == "settings" and "search-settings" or "search")}}
      search.style.width = width - 64
    end
    body = content.add{type = "flow", name = PREFIX .. "body", direction = "vertical"}
  end
  body.style.width, body.style.height = width - 64, height - ((v.tab == "research" or v.tab == "settings") and 170 or 136)
  if v.tab == "research" or v.tab == "settings" then
    local search = content[PREFIX .. "search"]
    search.style.width = width - 64
    local text = v.tab == "settings" and v.settings_search or v.search
    if search.text ~= text then search.text = text end
  end
  if v.tab == "research" then
    local c = catalogue(player.force)
    if not c then label(body, {"mir-browser.catalogue-limit", core.catalogue_limit}); return end
    local cache = ensure_translation_catalogue(player, c)
    if not has_family(c.family_names, v.family) then v.family = "all" end
    local filters = body[PREFIX .. "filters"]
    if not filters then
      filters = body.add{type = "table", name = PREFIX .. "filters", column_count = 2, tags = {compact = height < 600}}
      filters.style.horizontal_spacing = 12
      local field_width = math.floor((width - 80) / 2)
      local family_items = {}
      for _, family in ipairs(c.family_names) do family_items[#family_items + 1] = family_caption(family) end
      v.family_names = c.family_names
      local family_index = 1
      for i,family in ipairs(c.family_names) do if family == v.family then family_index = i end end
      filter_dropdown(filters, {"mir-browser.filter-scope"}, family_items, family_index, "family", field_width)
      filter_dropdown(filters, {"mir-browser.filter-status"}, {{"mir-browser.all-status"}, {"mir-browser.available"}, {"mir-browser.locked"}, {"mir-browser.queued"}}, v.status, "status", field_width)
      filter_dropdown(filters, {"mir-browser.filter-level"}, {{"mir-browser.all-levels"}, {"mir-browser.finite"}, {"mir-browser.infinite"}}, v.mode, "mode", field_width)
      filter_dropdown(filters, {"mir-browser.filter-order"}, {{"mir-browser.order-progression"}, {"mir-browser.order-native"}, {"mir-browser.order-name-asc"}, {"mir-browser.order-name-desc"}}, v.sort == "native" and 2 or v.sort == "name-asc" and 3 or v.sort == "name-desc" and 4 or 1, "sort", field_width)
      filter_dropdown(filters, {"mir-browser.visibility"}, {{"mir-browser.visibility-normal"}, {"mir-browser.visibility-hidden"}, {"mir-browser.not-added"}}, v.visibility, "visibility", field_width)
    end
    local indices = {mode = v.mode, status = v.status, visibility = v.visibility,
      sort = v.sort == "native" and 2 or v.sort == "name-asc" and 3 or v.sort == "name-desc" and 4 or 1}
    for i,family in ipairs(v.family_names or {}) do if family == v.family then indices.family = i end end
    for _,field in pairs(filters.children) do
      for _,control in pairs(field.children) do
        if control.type == "drop-down" then
          local selected = indices[control.tags.mir_browser] or 1
          if control.selected_index ~= selected then control.selected_index = selected end
        end
      end
    end
    local results = body[PREFIX .. "research_results"]
    local _,_,stacked = research_pane_widths(player)
    if not results then results = body.add{type = "flow", name = PREFIX .. "research_results", direction = stacked and "vertical" or "horizontal"} end
    results.style.height = math.max(48, body.style.maximal_height - (height < 600 and 110 or 190))
    update_research_results(player, results, v, c, cache)
  elseif v.tab == "settings" then settings_rows(player, body, v)
  elseif v.tab == "queue" then
    queue_rows(player, body, v)
  else debug_rows(player, body, v, width) end
  if not player.opened or player.opened ~= frame then player.opened = frame end
  set_shortcut_toggled(player, true)
end

local function refresh_search_results(player)
  if player.gui.screen[ROOT] then render(player) end
end
refresh_scheduled_searches = function(event)
  local pending = state().pending_search_refresh
  for player_index, due_tick in pairs(pending) do
    if type(player_index) ~= "number" or player_index < 1 or player_index ~= math.floor(player_index)
        or type(due_tick) ~= "number" or due_tick <= event.tick then
      pending[player_index] = nil
      local player = type(player_index) == "number" and player_index >= 1
        and player_index == math.floor(player_index) and game.get_player(player_index)
      if player and player.valid then refresh_search_results(player) end
    end
  end
  if next(pending) == nil then set_search_refresh_subscription(false) end
end
local function refresh_open(force)
  if force then catalogue_cache[force.index] = nil else catalogue_cache = {} end
  for _, player in pairs(game.connected_players) do
    if (not force or player.force.index == force.index) and player.gui.screen[ROOT] then
      view(player).detail_token = nil
      render(player)
    end
  end
end
local function export(player)
  local profile = codec.current_profile{value_resolver = startup_settings.get, compact = true}
  local text, err = codec.encode(profile)
  if not text then player.print(tostring(err)); return end
  local decoded = codec.decode(text)
  local _, _, invalid = codec.count_recognized_settings(decoded)
  if invalid ~= 0 then player.print({"mir-browser.invalid-profile"}); return end
  helpers.write_file("more-infinite-research/settings/browser-profile.txt", text .. "\n", false, player.index)
  player.print({"mir-browser.exported"})
end
local function event_player(event)
  return event.player_index and game.get_player(event.player_index)
end
local function owned_element(player, element)
  if not (player and element and element.valid) then return false end
  local root = player.gui.screen[ROOT]
  while element and element.valid do
    if element == root then return true end
    element = element.parent
  end
  return false
end
local function owned_root(player, element)
  return player and element and element.valid and element == player.gui.screen[ROOT]
end
local function set_hidden(v, force, values)
  if type(values) ~= "table" then return false end
  local count, hidden = 0, {}
  for index, technology in pairs(values) do
    if type(index) ~= "number" or index < 1 or index > core.catalogue_limit or index ~= math.floor(index) or type(technology) ~= "string" then return false end
    count = count + 1
    if count > core.catalogue_limit or hidden[technology] or not force.technologies[technology] then return false end
    hidden[technology] = true
  end
  if #values ~= count then return false end
  for index = 1, count do if type(values[index]) ~= "string" then return false end end
  v.hidden = hidden
  return true
end
local function toggle_hidden(v, force, technology)
  if type(technology) ~= "string" or not force.technologies[technology] then return false end
  local values, current = {}, type(v.hidden) == "table" and v.hidden or {}
  for name, is_hidden in pairs(current) do
    if is_hidden == true and type(name) == "string" and name ~= technology and force.technologies[name] then values[#values + 1] = name end
  end
  if current[technology] ~= true then values[#values + 1] = technology end
  table.sort(values)
  local changed = set_hidden(v, force, values)
  if changed then v.page = 1 end
  return changed
end
local function click(event)
  local player = event_player(event)
  local element = event.element
  if not owned_element(player, element) then return end
  local tags = element.tags
  local action = tags.mir_browser
  if not action or (element.type ~= "button" and element.type ~= "sprite-button") then return end
  if action == "close" then close(player); return end
  local v = view(player)
  if action == "select" then
    v.selected, v.effect_page = tags.technology, 1
    if v.tab == "queue" then v.tab, v.page = "research", 1 end
  elseif action == "setting-select" then
    if v.tab == "settings" and type(tags.setting_key) == "string" then v.setting_selection = tags.setting_key end
  elseif action == "settings-research" or action == "settings-options" then
    if v.tab == "settings" then
      v.settings_scope, v.page, v.setting_selection = action == "settings-options" and "options" or "research", 1, nil
    end
  elseif action == "queue-up" or action == "queue-down" or action == "enqueue" then
    -- Old saved controls and delayed events cannot bypass the prototype's native handoff.
    player.print({"mir-browser.native-queue-guidance"})
    return
  elseif action == "open-vanilla" then
    local tech = tags.technology and player.force.technologies[tags.technology]
    close(player)
    player.open_technology_gui(tech and tech.valid and tech or nil)
    return
  elseif action == "toggle-hide" then
    toggle_hidden(v, player.force, tags.technology)
  elseif action == "inspect-settings" then
    local c = catalogue(player.force)
    local portable = resolved_detail(player.force, c, tags.technology)
    local key = portable and research_setting_specs(portable)
    if not key and portable then key = portable.technology.family end
    if key then v.tab, v.settings_scope, v.settings_search, v.setting_selection = "settings", "research", "", key end
  elseif action == "show-hidden" then
    if set_hidden(v, player.force, {}) then v.page = 1 end
  elseif action == "layout-smaller" or action == "layout-larger" or action == "layout-reset" then
    local width, height = dimensions(player)
    local delta = action == "layout-larger" and 64 or -64
    if action == "layout-reset" then
      v.geometry, v.location = nil, nil
      player.gui.screen[ROOT].force_auto_center()
    else v.geometry = {width = math.max(360, width + delta), height = math.max(360, height + delta)} end
    v.layout_token = nil
    -- A deliberate layout operation may rebuild pane internals; the root remains alive.
    local tabs = player.gui.screen[ROOT][PREFIX .. "tabs"]
    for _, name in ipairs(TAB_NAMES) do tabs[PREFIX .. name .. "_content"].clear() end
    v.result_token, v.settings_list_token = nil, nil
  elseif action == "report-export" then
    local path = "more-infinite-research/reports/browser-" .. player.index .. "-" .. game.tick .. ".txt"
    helpers.write_file(path, report_text(player) .. "\n", false, player.index)
    player.print({"mir-browser.report-written", "script-output/" .. path})
    v.report_status = {"mir-browser.report-saved", "browser-" .. player.index .. "-" .. game.tick .. ".txt"}
    v.report_destination = "script-output/" .. path
    local status = debug_preview(player)[PREFIX .. "report_status"]
    status.caption, status.tooltip = v.report_status, v.report_destination
  elseif action == "report-select" then
    local field = debug_preview(player)[PREFIX .. "report"]
    field.focus(); field.select_all(); return
  elseif action == "debug-refresh" then
    catalogue_cache[player.force.index] = nil
    v.detail_token = nil
    debug_preview(player)[PREFIX .. "report"].text = report_text(player)
    return
  elseif action == "export" then export(player)
  elseif action == "refresh" then
    local translations = translation_state()
    local cache = translations[player.index]
    if cache then cache.priority_token = nil end
  else return end
  render(player)
end
local function selection(event)
  local player = event_player(event)
  if not owned_element(player, event.element) then return end
  local action = event.element.tags.mir_browser
  if action == "queue-list" then
    local v = view(player)
    local technology = (v.queue_keys or {})[event.element.selected_index]
    if technology and player.force.technologies[technology] then
      v.selected, v.tab, v.visibility = technology, "research", 1
      v.search, v.family, v.status, v.mode = "", "all", 1, 1
      render(player)
    end
    return
  end
  if action == "omission-list" then
    local v = view(player)
    local index = event.element.selected_index
    local envelope = mir_provider.omissions(player.force)
    local row = envelope and envelope.rows and envelope.rows[index]
    if row and bounded_string(row.reason) then
      v.omission_selection = index
      event.element.parent[PREFIX .. "omission_reason"].caption = omission_reason_caption(row.reason)
    end
    return
  end
  if action == "recipe-list" then
    local v = view(player)
    local id = (v.recipe_ids or {})[event.element.selected_index]
    if id and prototypes.recipe[id] then player.open_factoriopedia_gui(prototypes.recipe[id]) end
    return
  end
  if action == "research-list" or action == "setting-list" then
    local v = view(player)
    local index = event.element.selected_index
    if action == "research-list" then v.selected = (v.result_keys or {})[index]
    else v.setting_selection = (v.setting_keys or {})[index] end
    render(player); return
  end
  if action ~= "mode" and action ~= "status" and action ~= "family" and action ~= "sort" and action ~= "visibility" then return end
  local v = view(player)
  if action == "family" then
    local c = catalogue(player.force); if not c then return end
    v.family = (v.family_names or c.family_names)[event.element.selected_index]
  elseif action == "sort" then
    v.sort = ({"progression", "native", "name-asc", "name-desc"})[event.element.selected_index] or "progression"
    if v.sort == "progression" or v.sort == "native" then v.stable_sort = v.sort end
  else v[action] = event.element.selected_index end
  v.page = 1; render(player)
end
function M.on_init()
  mir_provider.invalidate_omissions()
  set_force_refresh_subscription(false)
  set_search_refresh_subscription(false)
  for _, player in pairs(game.players) do
    remove_legacy_top_button(player)
    set_shortcut_toggled(player, false)
  end
end
function M.on_configuration_changed()
  catalogue_cache = {}
  mir_provider.invalidate_omissions()
  state().pending_force_refresh = {}
  set_force_refresh_subscription(false)
  state().pending_search_refresh = {}
  set_search_refresh_subscription(false)
  local translations, locale_generations = translation_state()
  for player_index, cache in pairs(translations) do
    local player = game.get_player(player_index)
    if player and player.valid and type(cache) == "table" then
      -- New prototype/configuration facts need a new catalogue generation,
      -- but Factorio cannot cancel the old IDs. Keep them until callback or
      -- timeout so configuration reload cannot create an unbounded window.
      translation_queue.invalidate_locale(cache, player.locale,
        next_locale_generation(locale_generations, cache, player_index))
    else
      translations[player_index] = nil
      locale_generations[player_index] = nil
    end
  end
  for _, player in pairs(game.players) do
    local v = view(player)
    v.layout_token, v.settings_detail_token, v.detail_token = nil, nil, nil
    remove_legacy_top_button(player)
  end
  refresh_open()
  for _, player in pairs(game.players) do
    if not player.gui.screen[ROOT] then set_shortcut_toggled(player, false) end
  end
end

local function schedule_open_force_refresh(force)
  if not force then return end
  catalogue_cache[force.index] = nil
  for _, player in pairs(game.connected_players) do
    if player.force.index == force.index and player.gui.screen[ROOT] then
      local pending = state().pending_force_refresh
      local was_empty = next(pending) == nil
      pending[force.name] = true
      if was_empty then set_force_refresh_subscription(true) end
      return
    end
  end
end

function M.on_research_finished(event) schedule_open_force_refresh(event.research and event.research.force) end
M.on_research_reversed = M.on_research_finished
M.on_research_queued = M.on_research_finished
function M.on_technology_effects_reset() refresh_open() end
function M.on_force_reset(event) refresh_open(event and event.force) end
function M.on_forces_merged() refresh_open() end
local function translated(event)
  local player = event_player(event)
  local translations, locale_generations = translation_state()
  local cache = player and translations[player.index]
  if not cache or type(event.id) ~= "number" then return end
  -- Event ordering around a locale change is not a proof boundary.  If a
  -- pre-change callback arrives before its locale event, retire its generation
  -- here so it frees the slot without publishing an old-locale label.
  if cache.locale ~= player.locale then
    translation_queue.invalidate_locale(cache, player.locale,
      next_locale_generation(locale_generations, cache, player.index))
  end
  local result = event.translated and type(event.result) == "string"
    and string.sub(event.result, 1, core.detail_string_limit) or nil
  -- A stale callback still releases its retained pending slot, but its label
  -- cannot enter the current locale/catalogue index.
  local current_generation = translation_queue.completed(cache, event.id, result)
  if player.gui.screen[ROOT] then
    if needs_name_index(view(player)) then pump_translation_requests(player, cache) end
    if current_generation then refresh_translated_view(player, cache) end
  end
end

local function maintain_translations(event)
  local translations, locale_generations = translation_state()
  for player_index, cache in pairs(translations) do
    local player = game.get_player(player_index)
    if not (player and player.valid) then
      translations[player_index] = nil
      locale_generations[player_index] = nil
    else
      translation_queue.expire(cache, event.tick)
      -- Work continues only while the player has this surface open. A close
      -- keeps already requested results but does not spend translation work.
      if player.gui.screen[ROOT] then
        if needs_name_index(view(player)) then pump_translation_requests(player, cache) end
        refresh_translated_view(player, cache)
      end
    end
  end
end

-- Research completion can arrive in a burst. Build the force catalogue once
-- on the next tick only when an affected player is actually viewing it; a
-- closed library has no catalogue work to coalesce.
refresh_scheduled_forces = function()
  local pending = state().pending_force_refresh
  for force_name in pairs(pending) do
    pending[force_name] = nil
    local force = game.forces[force_name]
    if force then refresh_open(force) end
  end
  set_force_refresh_subscription(false)
end

function M.on_load()
  local pending = saved_pending_force_refresh()
  local active = false
  for force_name, scheduled in pairs(pending or {}) do
    if type(force_name) == "string" and scheduled == true then active = true; break end
  end
  set_force_refresh_subscription(active)
  local search_pending = saved_pending_search_refresh()
  local search_active = false
  for player_index, due_tick in pairs(search_pending or {}) do
    if type(player_index) == "number" and type(due_tick) == "number" then search_active = true; break end
  end
  set_search_refresh_subscription(search_active)
end

local function shortcut(event)
  if event.prototype_name ~= SHORTCUT then return end
  local player = event_player(event)
  if not player then return end
  if player.gui.screen[ROOT] then close(player) else render(player) end
end
function M.register()
  remote.add_interface("more-infinite-research-browser", {
    open = function(player_index, options)
      local player = game.get_player(player_index)
      if not player then return false end
      local v = view(player)
      if type(options) == "table" then
        local reset_page = false
        local requested_page = nil
        if options.mode == 1 or options.mode == 2 or options.mode == 3 then
          v.mode = options.mode
          reset_page = true
        end
        if type(options.search) == "string" then
          v[(options.tab or v.tab) == "settings" and "settings_search" or "search"] = string.sub(options.search, 1, 160)
          reset_page = true
        end
        if options.tab == "settings" or options.tab == "research"
            or options.tab == "queue" or options.tab == "availability" or options.tab == "help" then
          v.tab = options.tab == "availability" and "research" or options.tab
          if options.tab == "availability" then v.visibility = 3 else v.visibility = 1 end
          reset_page = true
        end
        if options.settings_scope == "research" or options.settings_scope == "options" then
          v.settings_scope = options.settings_scope
          v.setting_selection = nil
          reset_page = true
        end
        if type(options.status) == "number" and options.status >= 1 and options.status <= 4 and options.status == math.floor(options.status) then
          v.status = options.status
          reset_page = true
        end
        if type(options.family) == "string" then
          local c = catalogue(player.force)
          if c and has_family(c.family_names, options.family) then
            v.family = options.family
            reset_page = true
          end
        end
        if options.sort == "progression" or options.sort == "native"
            or options.sort == "name-asc" or options.sort == "name-desc" then
          v.sort = options.sort
          if v.sort == "progression" or v.sort == "native" then v.stable_sort = v.sort end
          reset_page = true
        end
        if type(options.selected) == "string" and player.force.technologies[options.selected] then
          v.selected = options.selected
          v.effect_page = 1
          reset_page = true
        end
        if options.hidden ~= nil and set_hidden(v, player.force, options.hidden) then
          reset_page = true
        end
        if type(options.page) == "number" and options.page >= 1 and options.page <= core.catalogue_limit and options.page == math.floor(options.page) then
          requested_page = options.page
        end
        if requested_page then v.page = requested_page elseif reset_page then v.page = 1 end
      end
      render(player)
      return player.gui.screen[ROOT] ~= nil
    end
  })
  commands.add_command("mir-research", {"mir-browser.command"}, function(event)
    local player = event_player(event); if player then render(player) end
  end)
  script.on_event(defines.events.on_gui_selected_tab_changed, function(event)
    local player, element = event_player(event), event.element
    if not (owned_element(player, element) and element.tags.mir_browser == "tabs") then return end
    view(player).tab = TAB_NAMES[element.selected_tab_index] or "research"
    render(player)
  end)
  script.on_event(defines.events.on_gui_location_changed, function(event)
    local player = event_player(event)
    if owned_root(player, event.element) then view(player).location = event.element.location end
  end)
  script.on_event(defines.events.on_gui_click, click)
  script.on_event(defines.events.on_gui_selection_state_changed, selection)
  script.on_event(defines.events.on_gui_text_changed, function(event)
    local player = event_player(event)
    local element = event.element
    if not (owned_element(player, element) and element.tags.mir_browser == "search") then return end
    local v = view(player)
    if v.tab ~= "research" and v.tab ~= "settings" then return end
    local search = type(event.text) == "string" and event.text or element.text
    search = string.sub(search, 1, 160)
    local key = v.tab == "settings" and "settings_search" or "search"
    if v[key] == search then return end
    v[key], v.page = search, 1
    local pending = state().pending_search_refresh
    local was_empty = next(pending) == nil
    pending[player.index] = event.tick + SEARCH_SETTLE_TICKS
    if was_empty then set_search_refresh_subscription(true) end
  end)
  script.on_event(defines.events.on_string_translated, translated)
  script.on_nth_tick(TRANSLATION_MAINTENANCE_TICKS, maintain_translations)
  script.on_event(defines.events.on_lua_shortcut, shortcut)
  script.on_event(defines.events.on_gui_confirmed, function(event)
    local player = event_player(event)
    if owned_element(player, event.element) and event.element.tags.mir_browser == "search" then
      local v = view(player)
      local key = v.tab == "settings" and "settings_search" or "search"
      v[key], v.page = string.sub(event.element.text, 1, 160), 1
      local pending = state().pending_search_refresh
      pending[player.index] = nil
      if next(pending) == nil then set_search_refresh_subscription(false) end
      refresh_search_results(player)
    end
  end)
  script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = event_player(event); local element = event.element
    if not owned_element(player, element) then return end
    local action = element.tags.mir_browser
    if action == "report_settings" or action == "report_omissions" then
      view(player)[action] = element.state
      local preview = debug_preview(player)
      if preview then preview[PREFIX .. "report"].text = report_text(player) end
      return
    end
    if action ~= "setting" then return end
    local name = element.tags.setting; local prototype = prototypes.mod_setting[name]
    if not prototype or prototype.mod ~= "more-infinite-research" then return end
    local scope = prototype.setting_type
    if scope == "startup" or (scope == "runtime-global" and not player.admin) then return end
    local values = scope == "runtime-global" and settings.global or settings.get_player_settings(player)
    if values[name] and type(values[name].value) == "boolean" then values[name] = {value = element.state} end
  end)
  script.on_event(defines.events.on_gui_closed, function(event)
    local player = event_player(event)
    if owned_root(player, event.element) then close(player) end
  end)
  script.on_event(defines.events.on_player_created, function(event)
    local player = event_player(event)
    remove_legacy_top_button(player)
    set_shortcut_toggled(player, false)
  end)
  script.on_event(defines.events.on_player_removed, function(event)
    state().players[event.player_index] = nil
    state().pending_search_refresh[event.player_index] = nil
    if next(state().pending_search_refresh) == nil then set_search_refresh_subscription(false) end
    local translations, locale_generations = translation_state()
    translations[event.player_index] = nil
    locale_generations[event.player_index] = nil
  end)
  script.on_event(defines.events.on_player_locale_changed, function(event)
    local player = event_player(event)
    if player then
      local translations, locale_generations = translation_state()
      local cache = translations[event.player_index]
      if cache then
        translation_queue.invalidate_locale(cache, player.locale,
          next_locale_generation(locale_generations, cache, event.player_index))
      end
      if player.gui.screen[ROOT] then render(player) end
    end
  end)
  script.on_event(defines.events.on_player_changed_force, function(event)
    local player = event_player(event)
    if player then
      local translations = translation_state()
      local cache = translations[event.player_index]
      if cache then
        -- A force change can replace the catalogue under the same locale.
        -- Keep issued IDs and their window accounting; render will install
        -- the new catalogue generation.
        translation_queue.reset_catalogue(cache, {}, nil)
      end
      if player.gui.screen[ROOT] then render(player) end
    end
  end)
  for _, id in ipairs{defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed} do
    script.on_event(id, function(event)
      local player = event_player(event); if player.gui.screen[ROOT] then render(player) end
    end)
  end
  for _, id in ipairs{defines.events.on_research_started, defines.events.on_research_cancelled} do
    script.on_event(id, function(event)
      schedule_open_force_refresh(event.research and event.research.force or event.force)
    end)
  end
  script.on_event(defines.events.on_research_moved, function(event)
    schedule_open_force_refresh(event.force)
  end)
end
return M
