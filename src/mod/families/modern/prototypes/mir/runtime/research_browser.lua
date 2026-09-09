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
local ROOT, PREFIX = "mir_research_browser", "mir_browser_"

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
local function catalogue(force)
  local result = factorio_catalogue.snapshot(force)
  if not result then return nil end
  -- Dynamic cap/level facts must be refreshed with the copied Force snapshot.
  -- Only the pure core is cache-safe; provider state is never retained here.
  result.enrichment = mir_provider.snapshot(force)
  result.family_names = core.family_names(result.enrichment)
  return result
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
  local pages = math.max(1, math.ceil(#groups / core.page_size))
  v.page = math.min(v.page, pages)
  label(parent, {"mir-browser.startup-note"})
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
local function joined_ingredients(ingredients)
  local parts = {}
  for _, ingredient in ipairs(ingredients or {}) do
    parts[#parts + 1] = ingredient.name .. " x" .. tostring(ingredient.amount)
  end
  return table.concat(parts, ", ")
end
local function setting_caption(setting)
  return setting.name
    .. " | default=" .. tostring(setting.default)
    .. " | raw-direct=" .. tostring(setting.raw_direct)
    .. " | effective=" .. tostring(setting.effective)
    .. " | source=" .. setting.source
    .. " | changed=" .. tostring(setting.changed)
    .. " | changed-from-default=" .. tostring(setting.changed_from_default)
    .. " | restart-required=" .. tostring(setting.restart_required)
end
local function benefit_caption(recipes)
  local parts = {}
  for _, recipe in ipairs(recipes or {}) do
    parts[#parts + 1] = recipe.recipe_id
      .. " current-productivity=" .. tostring(recipe.current_productivity_bonus)
      .. " maximum-productivity=" .. tostring(recipe.maximum_productivity)
      .. " next-level-effective=" .. tostring(recipe.next_level_has_effective_benefit)
  end
  return table.concat(parts, " | ")
end
local function detail(player, parent, v, c)
  local portable = v.selected and core.detail(c, v.selected, c.enrichment)
  local tech = portable and player.force.technologies[portable.technology.key]
  if not tech then return end
  label(parent, {"", tech.localised_name, " (", tech.name, ")"})
  label(parent, tech.localised_description)
  local enrichment = portable.enrichment or {}
  label(parent, {"mir-browser.family-owner", portable.technology.family, tech.name, enrichment.action or "external"})
  if portable.technology.cap then label(parent, {"mir-browser.cap", portable.technology.cap}) end
  if enrichment.owner and enrichment.compiler_disposition and enrichment.final_science and enrichment.settings then
    fact_label(parent, "affected_recipes", "Affected recipes: " .. table.concat(enrichment.owner.affected_recipe_ids or {}, ", "))
    local disposition = enrichment.compiler_disposition
    fact_label(parent, "compiler_disposition", "Compiler disposition: " .. disposition.inclusion
      .. " | action=" .. disposition.action .. " | reason=" .. disposition.reason)
    fact_label(parent, "route_exclusions", "Route exclusions: " .. disposition.route_exclusions.state
      .. " | exact-recipe-ids=" .. table.concat(disposition.route_exclusions.recipe_ids or {}, ", "))
    fact_label(parent, "science", "Final science: " .. joined_ingredients(enrichment.final_science.ingredients)
      .. " | rationale=" .. enrichment.final_science.rationale)
    fact_label(parent, "next_level", "Next level has effective benefit: "
      .. tostring(enrichment.next_level_has_effective_benefit)
      .. " | current-level=" .. tostring(enrichment.current_level)
      .. " | effective-cap=" .. tostring(enrichment.effective_cap))
    fact_label(parent, "recipe_benefits", "Affected recipe benefit facts: " .. benefit_caption(enrichment.recipe_benefits))
    fact_label(parent, "maximum_setting", setting_caption(enrichment.settings.maximum_level))
    fact_label(parent, "enabled_setting", setting_caption(enrichment.settings.enabled))
    fact_label(parent, "startup_restart", "Startup settings require restart; this browser does not mutate startup settings.")
  else
    local ingredients = parent.add{type = "flow"}
    for _, ingredient in ipairs(tech.research_unit_ingredients) do
      ingredients.add{type = "sprite", sprite = "item/" .. ingredient.name, tooltip = {"item-name." .. ingredient.name}}
    end
  end
  local enqueue = button(parent, "enqueue", {"mir-browser.enqueue"}, {technology = tech.name})
  enqueue.enabled = actions.can_enqueue(player, tech, defines.input_action.start_research)
  button(parent, "toggle-hide", v.hidden and v.hidden[tech.name] and {"mir-browser.show"} or {"mir-browser.hide"}, {technology = tech.name})
  local effects = tech.prototype.effects
  local pages = math.max(1, math.ceil(#effects / core.page_size))
  v.effect_page = math.min(v.effect_page or 1, pages)
  for i = (v.effect_page - 1) * core.page_size + 1, math.min(v.effect_page * core.page_size, #effects) do
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
  if not c then player.print({"mir-browser.catalogue-limit", core.catalogue_limit}); return end
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
    local has_hidden = false
    for name, is_hidden in pairs(v.hidden or {}) do
      if is_hidden == true and player.force.technologies[name] then has_hidden = true; break end
    end
    if has_hidden then
      local recovery = body.add{type = "flow", direction = "horizontal", tags = {mir_browser_section = "hidden-recovery"}}
      button(recovery, "show-hidden", {"mir-browser.show-hidden"})
    end
    local page = core.query(c, v, c.enrichment)
    v.page, pages = page.page, page.pages
    label(body, {"mir-browser.count", page.count})
    for _, row in ipairs(page.rows) do
      button(body, "select", player.force.technologies[row.key].localised_name, {technology = row.key})
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
  for _, player in pairs(game.players) do launch_button(player) end
  refresh_open()
end
function M.on_research_finished(event) refresh_open(event.research.force) end
M.on_research_reversed = M.on_research_finished
M.on_research_queued = M.on_research_finished
function M.on_technology_effects_reset() refresh_open() end
function M.on_forces_merged() refresh_open() end
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
