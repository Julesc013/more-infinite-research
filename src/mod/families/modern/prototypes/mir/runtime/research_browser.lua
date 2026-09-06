local model = require("prototypes.mir.runtime.research_browser_model")
local runtime_state = require("prototypes.mir.runtime.state")
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local streams = require("prototypes.mir.streams.registry")
local M = {requires_features = {"settings_profiles"}}
local ROOT, PREFIX = "mir_research_browser", "mir_browser_"
local catalogues = {}

local function state()
  local value = runtime_state.bucket("research_browser")
  value.players = value.players or {}
  return value
end
local function view(player)
  local all = state().players
  all[player.index] = all[player.index] or {mode = 1, status = 1, page = 1, search = "", tab = "research", effect_page = 1, family = "all"}
  return all[player.index]
end
local function data(name)
  local prototype = prototypes.mod_data and prototypes.mod_data[name]
  return prototype and prototype.data or {}
end
local function catalogue(force)
  if catalogues[force.index] then return catalogues[force.index] end
  local result = {names = {}, caps = {}, families = {}, decisions = {}, family_names = {"all", "external"}}
  local known = {all = true, external = true}
  for name in pairs(force.technologies) do
    if #result.names >= model.catalogue_limit then return nil end
    result.names[#result.names + 1] = name
  end
  table.sort(result.names)
  for _, binding in ipairs(data("more-infinite-research-maximum-level-policy").bindings or {}) do
    if type(binding.selected) == "number" and binding.selected > 0 then result.caps[binding.technology] = binding.selected end
  end
  for _, row in ipairs(data("more-infinite-research-generation-plan").rows or {}) do
    if row.technology_id then
      result.families[row.technology_id] = row.stream_id
      result.decisions[row.technology_id] = row
      if row.stream_id and not known[row.stream_id] then
        known[row.stream_id] = true
        result.family_names[#result.family_names + 1] = row.stream_id
      end
    end
  end
  table.sort(result.family_names)
  catalogues[force.index] = result
  return result
end
local function label(parent, caption)
  local element = parent.add{type = "label", caption = caption}
  element.style.single_line = false
  element.style.maximal_width = 720
  return element
end
local function button(parent, action, caption, tags)
  tags = tags or {}; tags.mir_browser = action
  return parent.add{type = "button", caption = caption, tags = tags}
end
local function close(player)
  local frame = player.gui.screen[ROOT]
  if frame then frame.destroy() end
end
local function launch_button(player)
  if not player.gui.top[PREFIX .. "open"] then
    player.gui.top.add{type = "button", name = PREFIX .. "open", caption = {"mir-browser.title"}, tags = {mir_browser = "open"}}
  end
end
local function settings_rows(player, parent, v)
  local groups, assigned = {}, {}
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
  local pages = math.max(1, math.ceil(#groups / model.page_size))
  v.page = math.min(v.page, pages)
  label(parent, {"mir-browser.startup-note"})
  button(parent, "export", {"mir-browser.export"})
  local rows = parent.add{type = "table", column_count = 2}
  for i = (v.page - 1) * model.page_size + 1, math.min(v.page * model.page_size, #groups) do
    local g = groups[i]
    local title = label(rows, g.title); title.tooltip = g.key
    local values_column = rows.add{type = "flow", direction = "vertical"}
    for _, name in ipairs(g.names) do
      local prototype = prototypes.mod_setting[name]
      local scope = prototype.setting_type
      local values = scope == "runtime-global" and settings.global or scope == "runtime-per-user" and settings.get_player_settings(player) or settings.startup
      local value = scope == "startup" and startup_settings.get(name) or values[name].value
      local caption = {"", prototype.localised_name, " (", scope, "): "}
      if scope ~= "startup" and type(value) == "boolean" and (scope ~= "runtime-global" or player.admin) then
        values_column.add{type = "checkbox", state = value, caption = caption, tags = {mir_browser = "setting", setting = name}}
      else
        local shown = tostring(value)
        if #shown > 120 then shown = string.sub(shown, 1, 117) .. "..." end
        caption[#caption + 1] = shown
        local field = label(values_column, caption); field.tooltip = prototype.localised_description
      end
    end
  end
  return pages
end

local render
local function detail(player, parent, v, c)
  local tech = v.selected and player.force.technologies[v.selected]
  if not tech then return end
  label(parent, {"", tech.localised_name, " (", tech.name, ")"})
  label(parent, tech.localised_description)
  local decision = c.decisions[tech.name]
  label(parent, {"mir-browser.family-owner", c.families[tech.name] or "external", tech.name, decision and decision.action or "external"})
  if c.caps[tech.name] then label(parent, {"mir-browser.cap", c.caps[tech.name]}) end
  local ingredients = parent.add{type = "flow"}
  for _, ingredient in ipairs(tech.research_unit_ingredients) do
    ingredients.add{type = "sprite", sprite = "item/" .. ingredient.name, tooltip = {"item-name." .. ingredient.name}}
  end
  local enqueue = button(parent, "enqueue", {"mir-browser.enqueue"}, {technology = tech.name})
  enqueue.enabled = model.can_enqueue(player, tech, defines.input_action.start_research)
  local effects = tech.prototype.effects
  local pages = math.max(1, math.ceil(#effects / model.page_size))
  v.effect_page = math.min(v.effect_page or 1, pages)
  for i = (v.effect_page - 1) * model.page_size + 1, math.min(v.effect_page * model.page_size, #effects) do
    local effect = effects[i]
    label(parent, (effect.recipe or effect.ammo_category or effect.type) .. " : " .. tostring(effect.modifier or effect.change or effect.bonus or effect.type))
  end
  if pages > 1 then
    local nav = parent.add{type = "flow"}
    button(nav, "effects-prev", "<").enabled = v.effect_page > 1
    label(nav, tostring(v.effect_page) .. " / " .. tostring(pages))
    button(nav, "effects-next", ">").enabled = v.effect_page < pages
  end
  label(parent, {"mir-browser.omission-note"})
end
render = function(player)
  local v = view(player)
  local c = catalogue(player.force)
  close(player)
  if not c then player.print({"mir-browser.catalogue-limit", model.catalogue_limit}); return end
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
    local filters = body.add{type = "flow"}
    filters.add{type = "drop-down", items = {{"mir-browser.all"}, {"mir-browser.finite"}, {"mir-browser.infinite"}}, selected_index = v.mode, tags = {mir_browser = "mode"}}
    filters.add{type = "drop-down", items = {{"mir-browser.all"}, {"mir-browser.available"}, {"mir-browser.locked"}, {"mir-browser.queued"}}, selected_index = v.status, tags = {mir_browser = "status"}}
    local family_index = 1
    for i,name in ipairs(c.family_names) do if name == v.family then family_index = i end end
    filters.add{type = "drop-down", items = c.family_names, selected_index = family_index, tags = {mir_browser = "family"}}
    local queue = body.add{type = "flow", direction = "vertical"}
    label(queue, {"mir-browser.queue"})
    for i, tech in ipairs(player.force.research_queue or {}) do
      if i <= 10 then button(queue, "select", tech.localised_name, {technology = tech.name}) end
    end
    if #(player.force.research_queue or {}) > 10 then label(queue, {"mir-browser.queue-more", #(player.force.research_queue or {}) - 10}) end
    local page = model.page(c.names, player.force, v, c.caps, c.families)
    v.page, pages = page.page, page.pages
    label(body, {"mir-browser.count", page.count})
    for _, name in ipairs(page.rows) do
      button(body, "select", player.force.technologies[name].localised_name, {technology = name})
    end
    detail(player, body, v, c)
  end
  local nav = frame.add{type = "flow"}
  button(nav, "prev", "<").enabled = v.page > 1
  label(nav, tostring(v.page) .. " / " .. tostring(pages))
  button(nav, "next", ">").enabled = v.page < pages
  player.opened = frame
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
    if model.can_enqueue(player, tech, defines.input_action.start_research) then
      if not player.force.add_research(tech) then player.print({"mir-browser.enqueue-failed"}) end
    else player.print({"mir-browser.enqueue-failed"}) end
  elseif action == "prev" then v.page = math.max(1, v.page - 1)
  elseif action == "next" then v.page = v.page + 1
  elseif action == "effects-prev" then v.effect_page = math.max(1, v.effect_page - 1)
  elseif action == "effects-next" then v.effect_page = v.effect_page + 1
  elseif action == "settings" or action == "research" then v.tab = action; v.page = 1
  elseif action == "export" then export(player)
  elseif action == "refresh" then catalogues[player.force.index] = nil end
  render(player)
end
local function selection(event)
  local player = event_player(event)
  if not (player and event.element and event.element.valid) then return end
  local action = event.element.tags.mir_browser
  if action ~= "mode" and action ~= "status" and action ~= "family" then return end
  local v = view(player)
  if action == "family" then
    local c = catalogue(player.force); if not c then return end
    v.family = c.family_names[event.element.selected_index]
  else v[action] = event.element.selected_index end
  v.page = 1; render(player)
end
function M.on_init()
  for _, player in pairs(game.players) do launch_button(player) end
end
function M.on_configuration_changed()
  catalogues = {}
  for _, player in pairs(game.players) do launch_button(player) end
  refresh_open()
end
function M.on_research_finished(event) refresh_open(event.research.force) end
M.on_research_reversed = M.on_research_finished
M.on_research_queued = M.on_research_finished
function M.on_technology_effects_reset() refresh_open() end
function M.on_forces_merged() catalogues = {}; refresh_open() end
function M.register()
  remote.add_interface("more-infinite-research-browser", {
    open = function(player_index, options)
      local player = game.get_player(player_index)
      if not player then return false end
      local v = view(player)
      if type(options) == "table" then
        if options.mode == 1 or options.mode == 2 or options.mode == 3 then v.mode = options.mode end
        if type(options.search) == "string" then v.search = string.sub(options.search, 1, 160) end
        if options.tab == "settings" or options.tab == "research" then v.tab = options.tab end
        if type(options.status) == "number" and options.status >= 1 and options.status <= 4 and options.status == math.floor(options.status) then v.status = options.status end
        if type(options.selected) == "string" and player.force.technologies[options.selected] then v.selected = options.selected; v.effect_page = 1 end
        v.page = 1
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
  script.on_event(defines.events.on_player_created, function(event) launch_button(event_player(event)) end)
  script.on_event(defines.events.on_player_removed, function(event) state().players[event.player_index] = nil end)
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
