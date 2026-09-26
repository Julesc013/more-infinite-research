local core = require("prototypes.mir.runtime.research_browser_core")
local factorio_catalogue = require("prototypes.mir.runtime.research_browser_factorio_catalogue")
local mir_provider = require("prototypes.mir.runtime.research_browser_mir_provider")
local actions = require("prototypes.mir.runtime.research_browser_actions")
local runtime_state = require("prototypes.mir.runtime.state")
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local streams = require("prototypes.mir.streams.registry")
local M = {requires_features = {"settings_profiles"}}
local ROOT, PREFIX, SHORTCUT = "mir_research_browser", "mir_browser_", "mir-research-browser"
local TRANSLATION_LIMIT = 512
local VIEW_SCHEMA = 2
local translations = {}

local function state()
  local value = runtime_state.bucket("research_browser")
  value.players = value.players or {}
  return value
end
local function default_view()
  return {
    schema = VIEW_SCHEMA,
    mode = 1,
    status = 1,
    page = 1,
    search = "",
    tab = "research",
    effect_page = 1,
    family = "mir",
    sort = "progression"
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
  result.schema = VIEW_SCHEMA
  all[player.index] = result
  result.sort = result.sort == "name-asc" and "name-asc"
    or result.sort == "name-desc" and "name-desc"
    or result.sort == "native" and "native"
    or "progression"
  return result
end
local function catalogue(force)
  local result = factorio_catalogue.snapshot(force)
  if not result then return nil end
  -- Dynamic cap/level facts must be refreshed with the copied Force snapshot.
  -- Only the pure core is cache-safe; provider state is never retained here.
  result.enrichment = mir_provider.snapshot(force)
  result.family_names = core.family_names(result.enrichment)
  return result
end
local function translation_cache(player)
  local cache = translations[player.index]
  if not cache or cache.locale ~= player.locale then
    cache = {locale = player.locale, values = {}, requested = {}, requests = 0}
    translations[player.index] = cache
  end
  return cache
end
local function localized_search(player)
  return translation_cache(player).values
end
local function request_visible_translations(player, page, selected)
  local cache = translation_cache(player)
  local function request(technology)
    if not technology or cache.requests >= TRANSLATION_LIMIT
      or cache.values[technology.name] ~= nil or cache.requested[technology.name] then return end
    local id = player.request_translation(technology.localised_name)
    if type(id) == "number" then
      cache.requested[technology.name] = id
      cache.requested[id] = technology.name
      cache.requests = cache.requests + 1
    end
  end
  for _, row in ipairs(page.rows) do request(player.force.technologies[row.key]) end
  request(selected and player.force.technologies[selected])
end
local function label(parent, caption)
  local element = parent.add{type = "label", caption = caption}
  element.style.single_line = false
  element.style.maximal_width = 720
  return element
end
local function fact_label(parent, key, caption)
  local element = parent.add{
    type = "label",
    name = PREFIX .. "fact_" .. key,
    caption = caption,
    tags = {mir_browser_fact = key}
  }
  element.style.single_line = false
  element.style.maximal_width = 720
  return element
end
local function button(parent, action, caption, tags)
  tags = tags or {}; tags.mir_browser = action
  return parent.add{type = "button", caption = caption, tags = tags}
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
  local frame = player.gui.screen[ROOT]
  if frame then frame.destroy() end
  if not preserve_shortcut_state then set_shortcut_toggled(player, false) end
end
local function family_caption(family)
  if family == "mir" then return {"mir-browser.scope-mir"} end
  if family == "all" then return {"mir-browser.scope-all"} end
  if family == "external" then return {"mir-browser.scope-native"} end
  local stream = streams.view()[family]
  return stream and stream.localised_name or {"mir-browser.scope-mir"}
end

local function same_value(left, right)
  return type(left) == type(right) and left == right
end

local function shown_value(value)
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
    return "MIRSET1 profile: active | recognized=" .. tostring(summary.recognized)
      .. " | unknown=" .. tostring(summary.unknown) .. " | invalid=" .. tostring(summary.invalid)
      .. " | valid imported entries determine effective startup values | restart-required=true"
  end
  if summary.state == "invalid" then
    return "MIRSET1 profile: invalid and ignored | error=" .. shown_value(summary.error)
      .. " | effective startup values use raw direct settings | restart-required=true"
  end
  return "MIRSET1 profile: not configured | effective startup values use raw direct settings | restart-required=true"
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

local function startup_setting_caption(prototype, comparison)
  return {"", prototype.localised_name, " (startup): default=", shown_value(comparison.default),
    " | raw-direct=", shown_value(comparison.raw_direct), " | effective=", shown_value(comparison.effective),
    " | source=", comparison.source, " | restart-required=true"}
end

local function settings_rows(player, parent, v)
  local groups, assigned = {}, {}
  local profile_summary = imported_profile_summary()
  local search = string.lower(v.search or "")
  local function group(key, title, specs)
    local names, matches = {}, search == "" or string.find(string.lower(key), search, 1, true)
    for _, spec in ipairs(specs) do
      local prototype = prototypes.mod_setting[spec.name]
      if prototype and prototype.mod == "more-infinite-research" then
        names[#names + 1] = spec.name
        assigned[spec.name] = true
        if string.find(string.lower(spec.name), search, 1, true) then matches = true end
      end
    end
    if matches and #names > 0 then groups[#groups + 1] = {key = key, title = title, names = names} end
  end
  for key, stream in pairs(streams.view()) do
    group(key, stream.localised_name or {"technology-name.more-infinite-research." .. key}, settings_catalog.stream_setting_specs(key, stream))
  end
  for _, spec in ipairs(settings_catalog.base_extension_specs()) do
    group(spec.key, {"technology-name." .. (spec.locale_key or spec.key)}, settings_catalog.base_extension_setting_specs(spec.key))
  end
  for name, prototype in pairs(prototypes.mod_setting) do
    if prototype.mod == "more-infinite-research" and not assigned[name] then group(name, prototype.localised_name, {{name = name}}) end
  end
  table.sort(groups, function(a,b) return a.key < b.key end)
  local pages = math.max(1, math.ceil(#groups / core.page_size))
  v.page = math.min(v.page, pages)
  label(parent, {"mir-browser.startup-note"})
  fact_label(parent, "profile_import", profile_summary_caption(profile_summary))
  button(parent, "export", {"mir-browser.export"})
  local rows = parent.add{type = "table", column_count = 2}
  for i = (v.page - 1) * core.page_size + 1, math.min(v.page * core.page_size, #groups) do
    local g = groups[i]
    local title = label(rows, g.title); title.tooltip = g.key
    local values_column = rows.add{type = "flow", direction = "vertical"}
    for _, name in ipairs(g.names) do
      local prototype = prototypes.mod_setting[name]
      local scope = prototype.setting_type
      local values = scope == "runtime-global" and settings.global or scope == "runtime-per-user" and settings.get_player_settings(player) or settings.startup
      local value = scope == "startup" and startup_settings.get(name) or values[name].value
      local caption = {"", prototype.localised_name, " (", scope, "): "}
      if scope == "startup" then
        local field = label(values_column, startup_setting_caption(
          prototype, startup_comparison(name, prototype, profile_summary)))
        field.tooltip = prototype.localised_description
      elseif type(value) == "boolean" and (scope ~= "runtime-global" or player.admin) then
        values_column.add{type = "checkbox", state = value, caption = caption, tags = {mir_browser = "setting", setting = name}}
      else
        caption[#caption + 1] = shown_value(value)
        local field = label(values_column, caption); field.tooltip = prototype.localised_description
      end
    end
  end
  return pages
end

local render
local function add_technology_icon(parent, technology)
  return parent.add{type = "sprite", sprite = "technology/" .. technology.name, tooltip = technology.localised_name}
end
local function add_science_icons(parent, technology)
  local science = parent.add{type = "flow", direction = "horizontal"}
  label(science, {"mir-browser.science"})
  for _, ingredient in ipairs(technology.research_unit_ingredients) do
    science.add{type = "sprite", sprite = "item/" .. ingredient.name, tooltip = {"item-name." .. ingredient.name}}
  end
end
local function add_prerequisite_icons(parent, technology)
  local prerequisites = {}
  for _, prerequisite in pairs(technology.prerequisites) do prerequisites[#prerequisites + 1] = prerequisite end
  if #prerequisites == 0 then return end
  table.sort(prerequisites, function(left, right) return left.name < right.name end)
  local row = parent.add{type = "flow", direction = "horizontal"}
  label(row, {"mir-browser.prerequisites"})
  for index, prerequisite in ipairs(prerequisites) do
    if index <= 8 then add_technology_icon(row, prerequisite) end
  end
  if #prerequisites > 8 then label(row, {"mir-browser.prerequisites-more", #prerequisites - 8}) end
end
local function status_caption(technology)
  if technology.researched then return {"mir-browser.status-complete"} end
  if technology.queued then return {"mir-browser.status-queued"} end
  if technology.available then return {"mir-browser.status-ready"} end
  return {"mir-browser.status-locked"}
end
local function detail(player, parent, v, c)
  local portable = v.selected and core.detail(c, v.selected, c.enrichment)
  local tech = portable and player.force.technologies[portable.technology.key]
  if not tech then return end
  local heading = parent.add{type = "flow", direction = "horizontal"}
  add_technology_icon(heading, tech)
  label(heading, tech.localised_name)
  label(parent, tech.localised_description)
  local enrichment = portable.enrichment or {}
  label(parent, {"mir-browser.family", family_caption(portable.technology.family)})
  label(parent, status_caption(portable.technology))
  if portable.technology.cap then
    label(parent, {"mir-browser.level-cap", tech.level, portable.technology.cap})
  elseif tech.level and tech.level > 1 then
    label(parent, {"mir-browser.level", tech.level})
  end
  if enrichment.recipe_benefits then
    local count = #enrichment.recipe_benefits
    if enrichment.next_level_has_effective_benefit then
      label(parent, {"mir-browser.next-benefit", count})
    else
      label(parent, {"mir-browser.no-next-benefit", count})
    end
  elseif portable.technology.family ~= "external" then
    label(parent, {"mir-browser.mir-benefit"})
  end
  add_science_icons(parent, tech)
  add_prerequisite_icons(parent, tech)
  local enqueue = button(parent, "enqueue", {"mir-browser.enqueue"}, {technology = tech.name})
  enqueue.enabled = actions.can_enqueue(player, tech, defines.input_action.start_research)
  button(parent, "open-vanilla", {"controls.open-technology-gui"}, {technology = tech.name})
  button(parent, "toggle-hide", v.hidden and v.hidden[tech.name] and {"mir-browser.show"} or {"mir-browser.hide"}, {technology = tech.name})
end
local function filter_dropdown(parent, caption, items, selected_index, action)
  local field = parent.add{type = "flow", direction = "vertical"}
  label(field, caption)
  return field.add{type = "drop-down", items = items, selected_index = selected_index, tags = {mir_browser = action}}
end
local function has_family(family_names, family)
  for _, candidate in ipairs(family_names) do if candidate == family then return true end end
  return false
end
render = function(player)
  local v = view(player)
  local c = catalogue(player.force)
  if c and v.family == "mir" and not has_family(c.family_names, "mir") then v.family = "all" end
  if c and v.family == "mir" and v.selected then
    local families = c.enrichment and c.enrichment.families
    if type(families) ~= "table" or type(families[v.selected]) ~= "string" then
      v.selected, v.effect_page = nil, 1
    end
  end
  remove_legacy_top_button(player)
  close(player, true)
  if not c then
    set_shortcut_toggled(player, false)
    player.print({"mir-browser.catalogue-limit", core.catalogue_limit})
    return
  end
  local frame = player.gui.screen.add{type = "frame", name = ROOT, direction = "vertical", caption = {"mir-browser.title"}}
  frame.auto_center = true
  local scale = player.display_scale or 1
  frame.style.maximal_height = math.max(240, math.floor(player.display_resolution.height / scale) - 80)
  local bar = frame.add{type = "flow"}
  button(bar, "research", {"mir-browser.research"})
  button(bar, "settings", {"mir-browser.settings"})
  button(bar, "refresh", {"mir-browser.refresh"})
  button(bar, "close", {"mir-browser.close"})
  local search = frame.add{type = "textfield", name = PREFIX .. "search", text = v.search, tags = {mir_browser = "search"}}
  search.tooltip = {"mir-browser.search"}
  local body = frame.add{type = "scroll-pane", direction = "vertical"}
  body.style.maximal_height = math.max(140, frame.style.maximal_height - 140)
  local pages
  if v.tab == "settings" then pages = settings_rows(player, body, v)
  else
    local filters = body.add{type = "flow", direction = "horizontal"}
    filter_dropdown(filters, {"mir-browser.filter-level"}, {{"mir-browser.all-levels"}, {"mir-browser.finite"}, {"mir-browser.infinite"}}, v.mode, "mode")
    filter_dropdown(filters, {"mir-browser.filter-status"}, {{"mir-browser.all-status"}, {"mir-browser.available"}, {"mir-browser.locked"}, {"mir-browser.queued"}}, v.status, "status")
    local sort_index = v.sort == "native" and 2 or v.sort == "name-asc" and 3 or v.sort == "name-desc" and 4 or 1
    filter_dropdown(filters, {"mir-browser.filter-order"}, {{"mir-browser.order-progression"}, {"mir-browser.order-native"}, {"mir-browser.order-name-asc"}, {"mir-browser.order-name-desc"}}, sort_index, "sort")
    local family_index = 1
    for i,name in ipairs(c.family_names) do if name == v.family then family_index = i end end
    local family_items = {}
    for _, family in ipairs(c.family_names) do family_items[#family_items + 1] = family_caption(family) end
    filter_dropdown(filters, {"mir-browser.filter-scope"}, family_items, family_index, "family")
    local queue = body.add{type = "flow", direction = "vertical"}
    label(queue, {"mir-browser.queue"})
    for i, tech in ipairs(player.force.research_queue or {}) do
      if i <= 10 then button(queue, "select", tech.localised_name, {technology = tech.name}) end
    end
    if #(player.force.research_queue or {}) > 10 then label(queue, {"mir-browser.queue-more", #(player.force.research_queue or {}) - 10}) end
    local has_hidden = false
    for name, is_hidden in pairs(v.hidden or {}) do
      if is_hidden == true and player.force.technologies[name] then has_hidden = true; break end
    end
    if has_hidden then
      local recovery = body.add{type = "flow", direction = "horizontal", tags = {mir_browser_section = "hidden-recovery"}}
      button(recovery, "show-hidden", {"mir-browser.show-hidden"})
    end
    local page = core.query(c, v, c.enrichment, localized_search(player))
    v.page, pages = page.page, page.pages
    request_visible_translations(player, page, v.selected)
    label(body, {"mir-browser.count", page.count})
    for _, row in ipairs(page.rows) do
      local technology = player.force.technologies[row.key]
      if technology then
        local item = body.add{type = "flow", direction = "horizontal"}
        add_technology_icon(item, technology)
        button(item, "select", technology.localised_name, {technology = row.key})
        label(item, status_caption(row))
      end
    end
    detail(player, body, v, c)
  end
  local nav = frame.add{type = "flow"}
  button(nav, "prev", "<").enabled = v.page > 1
  label(nav, tostring(v.page) .. " / " .. tostring(pages))
  button(nav, "next", ">").enabled = v.page < pages
  player.opened = frame
  set_shortcut_toggled(player, true)
end
local function refresh_open(force)
  for _, player in pairs(game.connected_players) do
    if (not force or player.force.index == force.index) and player.gui.screen[ROOT] then render(player) end
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
  if not (player and element and element.valid) then return end
  local tags = element.tags
  local action = tags.mir_browser
  if not action then return end
  if action == "close" then close(player); return end
  local v = view(player)
  if action == "select" then v.selected = tags.technology; v.effect_page = 1
  elseif action == "enqueue" then
    local tech = player.force.technologies[tags.technology]
    if actions.can_enqueue(player, tech, defines.input_action.start_research) then
      if not player.force.add_research(tech) then player.print({"mir-browser.enqueue-failed"}) end
    else player.print({"mir-browser.enqueue-failed"}) end
  elseif action == "open-vanilla" then
    local tech = player.force.technologies[tags.technology]
    if tech and tech.valid then
      close(player)
      player.open_technology_gui(tech)
      return
    end
  elseif action == "toggle-hide" then
    toggle_hidden(v, player.force, tags.technology)
  elseif action == "show-hidden" then
    if set_hidden(v, player.force, {}) then v.page = 1 end
  elseif action == "prev" then v.page = math.max(1, v.page - 1)
  elseif action == "next" then v.page = v.page + 1
  elseif action == "effects-prev" then v.effect_page = math.max(1, v.effect_page - 1)
  elseif action == "effects-next" then v.effect_page = v.effect_page + 1
  elseif action == "settings" or action == "research" then v.tab = action; v.page = 1
  elseif action == "export" then export(player)
  elseif action == "refresh" then end
  render(player)
end
local function selection(event)
  local player = event_player(event)
  if not (player and event.element and event.element.valid) then return end
  local action = event.element.tags.mir_browser
  if action ~= "mode" and action ~= "status" and action ~= "family" and action ~= "sort" then return end
  local v = view(player)
  if action == "family" then
    local c = catalogue(player.force); if not c then return end
    v.family = c.family_names[event.element.selected_index]
  elseif action == "sort" then
    v.sort = ({"progression", "native", "name-asc", "name-desc"})[event.element.selected_index] or "progression"
  else v[action] = event.element.selected_index end
  v.page = 1; render(player)
end
function M.on_init()
  for _, player in pairs(game.players) do
    remove_legacy_top_button(player)
    set_shortcut_toggled(player, false)
  end
end
function M.on_configuration_changed()
  translations = {}
  for _, player in pairs(game.players) do
    view(player)
    remove_legacy_top_button(player)
  end
  refresh_open()
  for _, player in pairs(game.players) do
    if not player.gui.screen[ROOT] then set_shortcut_toggled(player, false) end
  end
end
function M.on_research_finished(event) refresh_open(event.research.force) end
M.on_research_reversed = M.on_research_finished
M.on_research_queued = M.on_research_finished
function M.on_technology_effects_reset() refresh_open() end
function M.on_force_reset(event) refresh_open(event and event.force) end
function M.on_forces_merged() refresh_open() end
local function translated(event)
  local player = event_player(event)
  local cache = player and translations[player.index]
  if not cache or cache.locale ~= player.locale or type(event.id) ~= "number" then return end
  local technology = cache.requested[event.id]
  if not technology then return end
  cache.requested[event.id] = nil
  if event.translated and type(event.result) == "string" then
    cache.values[technology] = string.sub(event.result, 1, core.detail_string_limit)
  else
    cache.values[technology] = ""
  end
  if player.gui.screen[ROOT] and view(player).search ~= "" then render(player) end
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
          v.search = string.sub(options.search, 1, 160)
          reset_page = true
        end
        if options.tab == "settings" or options.tab == "research" then
          v.tab = options.tab
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
  script.on_event(defines.events.on_gui_click, click)
  script.on_event(defines.events.on_gui_selection_state_changed, selection)
  script.on_event(defines.events.on_string_translated, translated)
  script.on_event(defines.events.on_lua_shortcut, shortcut)
  script.on_event(defines.events.on_gui_confirmed, function(event)
    local player = event_player(event)
    if player and event.element and event.element.valid and event.element.tags.mir_browser == "search" then
      local v = view(player); v.search = string.sub(event.element.text, 1, 160); v.page = 1; render(player)
    end
  end)
  script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local player = event_player(event); local element = event.element
    if not (player and element and element.valid and element.tags.mir_browser == "setting") then return end
    local name = element.tags.setting; local prototype = prototypes.mod_setting[name]
    if not prototype or prototype.mod ~= "more-infinite-research" then return end
    local scope = prototype.setting_type
    if scope == "startup" or (scope == "runtime-global" and not player.admin) then return end
    local values = scope == "runtime-global" and settings.global or settings.get_player_settings(player)
    if values[name] and type(values[name].value) == "boolean" then values[name] = {value = element.state} end
  end)
  script.on_event(defines.events.on_gui_closed, function(event)
    if event.element and event.element.valid and event.element.name == ROOT then close(event_player(event)) end
  end)
  script.on_event(defines.events.on_player_created, function(event)
    local player = event_player(event)
    remove_legacy_top_button(player)
    set_shortcut_toggled(player, false)
  end)
  script.on_event(defines.events.on_player_removed, function(event)
    state().players[event.player_index] = nil
    translations[event.player_index] = nil
  end)
  script.on_event(defines.events.on_player_locale_changed, function(event)
    translations[event.player_index] = nil
    local player = event_player(event); if player and player.gui.screen[ROOT] then render(player) end
  end)
  script.on_event(defines.events.on_player_changed_force, function(event)
    local player = event_player(event); if player.gui.screen[ROOT] then render(player) end
  end)
  for _, id in ipairs{defines.events.on_player_display_resolution_changed, defines.events.on_player_display_scale_changed} do
    script.on_event(id, function(event)
      local player = event_player(event); if player.gui.screen[ROOT] then render(player) end
    end)
  end
  for _, id in ipairs{defines.events.on_research_started, defines.events.on_research_cancelled} do
    script.on_event(id, function() refresh_open() end)
  end
end
return M
