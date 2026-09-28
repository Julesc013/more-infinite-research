local core = require("prototypes.mir.runtime.research_browser_core")
local translation_queue = core.translation_queue
local factorio_catalogue = require("prototypes.mir.runtime.research_browser_factorio_catalogue")
local mir_provider = require("prototypes.mir.runtime.research_browser_mir_provider")
local actions = require("prototypes.mir.runtime.research_browser_actions")
local runtime_state = require("prototypes.mir.runtime.state")
local factorio_runtime_state = require("prototypes.mir.platform.factorio.runtime_state")
local startup_settings = require("prototypes.mir.runtime.startup_settings")
local codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")
local streams = require("prototypes.mir.streams.registry")
local M = {requires_features = {"settings_profiles"}}
local ROOT, PREFIX, SHORTCUT = "mir_research_browser", "mir_browser_", "mir-research-browser"
local RESEARCH_LIST_WIDTH, RESEARCH_DETAIL_WIDTH = 360, 460
local RESEARCH_LIST_MIN_WIDTH, RESEARCH_DETAIL_MIN_WIDTH = 240, 280
local RESEARCH_PANES_MIN_HEIGHT, RESEARCH_FILTERS_HEIGHT, RESEARCH_HIDDEN_RECOVERY_HEIGHT = 80, 56, 32
-- Translation IDs are asynchronous and per-player.  Keep the work window
-- small so a large catalogue neither monopolizes a tick nor stops after an
-- arbitrary lifetime number of successful translations.
-- Do not share passive repair's 60-tick registration; Factorio has one
-- handler per interval within this mod.
local TRANSLATION_MAINTENANCE_TICKS = 61
local VIEW_SCHEMA = 2
local render
local refresh_scheduled_forces
local update_research_results
local update_navigation
local update_translation_index

local function state()
  local value = runtime_state.bucket("research_browser")
  value.players = value.players or {}
  value.pending_force_refresh = type(value.pending_force_refresh) == "table" and value.pending_force_refresh or {}
  return value
end

local function research_pane_widths(player)
  local resolution = player and player.display_resolution
  local scale = player and player.display_scale
  local width = resolution and resolution.width
  if type(width) ~= "number" or width <= 0 or type(scale) ~= "number" or scale <= 0 then
    return RESEARCH_LIST_WIDTH, RESEARCH_DETAIL_WIDTH
  end
  -- Leave room for the frame edge, its scrollbar, and Factorio's native chrome.
  -- At a normal desktop width this keeps the intended 360/460 split; narrower
  -- displays reduce both columns proportionally down to readable lower bounds.
  local normal_width = RESEARCH_LIST_WIDTH + RESEARCH_DETAIL_WIDTH
  local minimum_width = RESEARCH_LIST_MIN_WIDTH + RESEARCH_DETAIL_MIN_WIDTH
  local available = math.floor(width / scale) - 96
  local total = math.max(minimum_width, math.min(normal_width, available))
  local list_width = math.floor(total * RESEARCH_LIST_WIDTH / normal_width)
  list_width = math.max(RESEARCH_LIST_MIN_WIDTH, math.min(RESEARCH_LIST_WIDTH, list_width))
  local detail_width = total - list_width
  if detail_width < RESEARCH_DETAIL_MIN_WIDTH then
    detail_width = RESEARCH_DETAIL_MIN_WIDTH
    list_width = total - detail_width
  end
  return list_width, detail_width
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
    effect_page = 1,
    family = "mir",
    sort = "progression",
    stable_sort = "progression"
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
  result.stable_sort = result.stable_sort == "native" and "native" or "progression"
  if result.sort == "native" or result.sort == "progression" then result.stable_sort = result.sort end
  result.tab = result.tab == "settings" and "settings"
    or result.tab == "queue" and "queue"
    or result.tab == "availability" and "availability"
    or "research"
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
  local body = frame[PREFIX .. "body"]
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
    pump_translation_requests(player, cache)
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

update_translation_index = function(results, cache, v)
  -- The index belongs to the retained list column.  Translation callbacks can
  -- therefore update this one small label without replacing the list, detail,
  -- search field, or fixed Browse controls.
  local list = results and results[PREFIX .. "research_list"]
  local parent = list and list.valid and list or results
  if not (parent and parent.valid) then return end
  local indicator = parent[PREFIX .. "fact_translation_index"]
  local unresolved = unresolved_translations(cache)
  if unresolved <= 0 then
    if indicator and indicator.valid then indicator.destroy() end
    return
  end
  local name_order = v.sort == "name-asc" or v.sort == "name-desc"
  local caption = name_order and {"mir-browser.indexing-name", unresolved}
    or {"mir-browser.indexing", unresolved}
  if indicator and indicator.valid then
    indicator.caption = caption
  else
    fact_label(parent, "translation_index", caption, list and list.style.maximal_width - 16 or nil)
  end
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
  local value = shown_value(comparison.effective)
  return caption and {"", caption, ": ", value} or value
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
  local title_width, value_width = research_pane_widths(player)
  for i = (v.page - 1) * core.page_size + 1, math.min(v.page * core.page_size, #groups) do
    local g = groups[i]
    label(rows, g.title, title_width - 16)
    local values_column = rows.add{type = "flow", direction = "vertical"}
    values_column.style.maximal_width = value_width - 16
    for _, name in ipairs(g.names) do
      local prototype = prototypes.mod_setting[name]
      local scope = prototype.setting_type
      local values = scope == "runtime-global" and settings.global or scope == "runtime-per-user" and settings.get_player_settings(player) or settings.startup
      local value = scope == "startup" and startup_settings.get(name) or values[name].value
      local caption = {"", prototype.localised_name, " (", scope, "): "}
      if scope == "startup" then
        local comparison = startup_comparison(name, prototype, profile_summary)
        if type(comparison.effective) == "boolean" then
          local field = values_column.add{
            type = "checkbox", state = comparison.effective,
            caption = setting_field_caption(name, g.key, prototype) or "",
            tags = {mir_browser_setting = name, mir_browser_read_only = true}
          }
          field.enabled = false
        else
          local field = label(values_column, startup_setting_caption(name, g.key, prototype, comparison), value_width - 16)
          field.tags = {mir_browser_setting = name, mir_browser_read_only = true}
        end
      elseif type(value) == "boolean" and (scope ~= "runtime-global" or player.admin) then
        values_column.add{type = "checkbox", state = value, caption = caption, tags = {mir_browser = "setting", setting = name}}
      else
        caption[#caption + 1] = shown_value(value)
        label(values_column, caption, value_width - 16)
      end
    end
  end
  return pages
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
  local units = displayed_number(technology.research_unit_count)
  -- Runtime research energy uses ticks; prototype unit.time uses seconds.
  -- Keep this as the unmodified unit duration, independent of lab speed/UPS.
  local ticks = technology.research_unit_energy
  local seconds = finite_nonnegative(ticks) and displayed_number(ticks / 60)
  if units and seconds then fact_label(parent, "research_cost", {"mir-browser.research-cost", units, seconds}, maximum_width) end
end
local function add_science_icons(parent, technology, maximum_width)
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
    if index <= 8 then add_technology_icon(row, prerequisite) end
  end
  if #prerequisites > 8 then label(parent, {"mir-browser.prerequisites-more", #prerequisites - 8}, maximum_width) end
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
  label(parent, {"mir-browser.research-startup-settings"}, maximum_width)
  label(parent, {"mir-browser.startup-note"}, maximum_width)
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
  local portable = v.selected and core.detail(c, v.selected, c.enrichment)
  local tech = portable and player.force.technologies[portable.technology.key]
  if not tech then return end
  local maximum_width = math.max(120, width - 16)
  local heading_width = math.max(120, maximum_width - 56)
  local heading = parent.add{type = "flow", direction = "horizontal"}
  add_technology_icon(heading, tech, 48)
  label(heading, tech.localised_name, heading_width)
  label(parent, tech.localised_description, maximum_width)
  local enrichment = portable.enrichment or {}
  -- Provider ownership, compiler disposition, route sentinels, and raw
  -- setting provenance remain in the copied DTO for governed consumers. They
  -- are not player-facing research facts in this library surface.
  label(parent, {"mir-browser.family", family_caption(portable.technology.family)}, maximum_width)
  label(parent, status_caption(portable.technology, tech), maximum_width)
  local runtime_binding = portable.runtime_settings_binding
  local registered_binding = runtime_binding and research_setting_specs(portable)
  local effective_cap = portable.technology.cap
    or (registered_binding and runtime_binding.state == "finite" and runtime_binding.selected_effective)
  if effective_cap then
    label(parent, {"mir-browser.level-cap", tech.level, effective_cap}, maximum_width)
  elseif tech.level and tech.level > 1 then
    label(parent, {"mir-browser.level", tech.level}, maximum_width)
  end
  add_research_cost(parent, tech, maximum_width)
  if enrichment.recipe_benefits then
    local count = #enrichment.recipe_benefits
    if enrichment.next_level_has_effective_benefit then
      label(parent, {"mir-browser.next-benefit", count}, maximum_width)
    else
      label(parent, {"mir-browser.no-next-benefit", count}, maximum_width)
    end
  elseif portable.technology.family ~= "external" then
    label(parent, {"mir-browser.mir-benefit"}, maximum_width)
  end
  add_productivity_summary(parent, enrichment.recipe_benefits, maximum_width)
  add_science_icons(parent, tech, maximum_width)
  add_prerequisite_icons(parent, tech, maximum_width)
  local enqueue = button(parent, "enqueue", {"mir-browser.enqueue"}, {technology = tech.name})
  enqueue.enabled = actions.can_enqueue(player, tech, defines.input_action.start_research)
  button(parent, "open-vanilla", {"controls.open-technology-gui"}, {technology = tech.name})
  button(parent, "toggle-hide", v.hidden and v.hidden[tech.name] and {"mir-browser.show"} or {"mir-browser.hide"}, {technology = tech.name})
  add_research_startup_settings(parent, portable, maximum_width)
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
  if #entries == 0 then
    label(queue, {"mir-browser.queue-empty"})
    return 1
  end
  label(queue, {"mir-browser.queue"})
  local pages = math.max(1, math.ceil(#entries / core.page_size))
  v.page = math.min(v.page, pages)
  for index = (v.page - 1) * core.page_size + 1, math.min(v.page * core.page_size, #entries) do
    local technology = entries[index]
    if technology then
      local row = queue.add{type = "flow", direction = "horizontal"}
      label(row, tostring(index) .. ".")
      button(row, "select", technology.localised_name, {technology = technology.name})
      for _, direction in ipairs{-1, 1} do
        local adjacent = entries[index + direction]
        local action = direction == -1 and "queue-up" or "queue-down"
        local control = button(row, action, direction == -1 and "↑" or "↓", {
          index = index, technology = technology.name,
          adjacent = adjacent and adjacent.name or ""
        })
        control.enabled = actions.can_move(player, entries, index, direction, defines.input_action.move_research)
        control.tooltip = direction == -1 and {"controls.move-up"} or {"controls.move-down"}
      end
    end
  end
  return pages
end

local omission_reasons = {
  covered_by_existing_infinite_native_modifier = "not-added-provided",
  covered_by_planned_stream = "not-added-grouped",
  no_valid_effect_targets = "not-added-no-effect",
  automatic_family_not_reviewed = "not-added-review"
}

local function bounded_string(value)
  return type(value) == "string" and value ~= "" and #value <= core.detail_string_limit
end

-- This display is deliberately a terminal viewer. Its provider envelope is
-- validated again at the UI edge and omitted rows have no technology action,
-- queue action, or deep link. A malformed row yields no player claim.
local function availability_rows(force, parent, v)
  local envelope = mir_provider.omissions(force)
  if type(envelope) ~= "table" or envelope.schema ~= 1
      or envelope.kind ~= "portable-research-omissions" or type(envelope.rows) ~= "table"
      or #envelope.rows > core.catalogue_limit then
    label(parent, {"mir-browser.availability-empty"})
    return 1
  end
  local row_count = 0
  for index in pairs(envelope.rows) do
    if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then
      label(parent, {"mir-browser.availability-empty"})
      return 1
    end
    row_count = row_count + 1
  end
  if row_count ~= #envelope.rows then
    label(parent, {"mir-browser.availability-empty"})
    return 1
  end
  local rows, seen, stream_definitions = {}, {}, streams.view()
  for index = 1, #envelope.rows do
    local row = envelope.rows[index]
    if type(row) ~= "table"
        or not bounded_string(row.stream_id) or not bounded_string(row.reason)
        or not bounded_string(row.decision_fingerprint) or row.status ~= "not-added"
        or (row.technology_id ~= nil and not bounded_string(row.technology_id)) then
      label(parent, {"mir-browser.availability-empty"})
      return 1
    end
    local identity = row.stream_id .. "\0" .. (row.technology_id or "")
    local stream = stream_definitions[row.stream_id]
    if seen[identity] or not stream then
      label(parent, {"mir-browser.availability-empty"})
      return 1
    end
    seen[identity] = true
    rows[#rows + 1] = {
      caption = stream.localised_name or {"technology-name.more-infinite-research." .. row.stream_id},
      reason = row.reason
    }
  end
  if #rows == 0 then
    label(parent, {"mir-browser.availability-empty"})
    return 1
  end
  local pages = math.max(1, math.ceil(#rows / core.page_size))
  v.page = math.min(v.page, pages)
  for index = (v.page - 1) * core.page_size + 1, math.min(v.page * core.page_size, #rows) do
    local row = rows[index]
    local item = parent.add{type = "flow", direction = "vertical", tags = {mir_browser_section = "availability"}}
    label(item, row.caption)
    label(item, {"mir-browser.not-added"})
    label(item, {"mir-browser." .. (omission_reasons[row.reason] or "not-added-generic")})
  end
  return pages
end

-- This is the only part of Browse that translation callbacks may rebuild.
-- The surrounding frame, fixed filters, navigation and search text field are
-- intentionally retained, so localized discovery can finish in place.
update_research_results = function(player, results, v, c, cache)
  results.clear()
  local page = core.query(c, query_view(v, cache), c.enrichment, cache.values, v.selected)
  v.page = page.page
  select_first_visible_subject(player, v, page)
  prioritize_visible_translations(cache, page, v.selected)
  pump_translation_requests(player, cache)
  local list_width, detail_width = research_pane_widths(player)
  local panes_height = research_panes_height(results)
  local list = results.add{
    type = "scroll-pane", name = PREFIX .. "research_list", direction = "vertical",
    tags = {mir_browser_section = "research-list"}
  }
  list.style.width = list_width
  list.style.maximal_width = list_width
  list.style.height = panes_height
  list.style.maximal_height = panes_height
  list.horizontal_scroll_policy = "never"
  list.vertical_scroll_policy = "auto"
  local detail_pane = results.add{
    type = "scroll-pane", name = PREFIX .. "research_detail", direction = "vertical",
    tags = {mir_browser_section = "research-detail"}
  }
  detail_pane.style.width = detail_width
  detail_pane.style.maximal_width = detail_width
  detail_pane.style.height = panes_height
  detail_pane.style.maximal_height = panes_height
  detail_pane.horizontal_scroll_policy = "never"
  detail_pane.vertical_scroll_policy = "auto"
  detail(player, detail_pane, v, c, detail_width)
  update_translation_index(results, cache, v)
  label(list, {"mir-browser.count", page.count}, list_width - 16)
  for index, row in ipairs(page.rows) do
    local technology = player.force.technologies[row.key]
    if technology then
      local item = list.add{type = "flow", direction = "vertical"}
      local heading = item.add{type = "flow", direction = "horizontal"}
      add_technology_icon(heading, technology)
      local selected = v.selected == row.key
      local select = button(heading, "select", technology.localised_name, {
        technology = row.key,
        mir_browser_selected = selected and "selected" or "not-selected",
        mir_browser_first_visible = index == 1 and "first" or "not-first"
      })
      select.toggled = selected
      select.style.width = list_width - 44
      local status = label(item, status_caption(row, technology))
      status.style.maximal_width = list_width - 44
    end
  end
  return page.pages
end

update_navigation = function(frame, v, pages)
  local navigation = frame and frame[PREFIX .. "navigation"]
  if not (navigation and navigation.valid) then return end
  local previous = navigation[PREFIX .. "prev"]
  local current = navigation[PREFIX .. "page"]
  local following = navigation[PREFIX .. "next"]
  if previous then previous.enabled = v.page > 1 end
  if current then current.caption = tostring(v.page) .. " / " .. tostring(pages) end
  if following then following.enabled = v.page < pages end
end

render = function(player)
  local v = view(player)
  local c = catalogue(player.force)
  local cache = c and ensure_translation_catalogue(player, c)
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
  local list_width, detail_width = research_pane_widths(player)
  frame.style.maximal_width = list_width + detail_width + 36
  local bar = frame.add{type = "flow"}
  button(bar, "research", {"mir-browser.browse"}).toggled = v.tab == "research"
  button(bar, "queue", {"mir-browser.queue-tab"}).toggled = v.tab == "queue"
  button(bar, "settings", {"mir-browser.settings"}).toggled = v.tab == "settings"
  button(bar, "availability", {"mir-browser.availability"}).toggled = v.tab == "availability"
  button(bar, "refresh", {"mir-browser.refresh"})
  button(bar, "close", {"mir-browser.close"})
  if v.tab == "research" or v.tab == "settings" then
    local search = frame.add{type = "flow", direction = "horizontal", tags = {mir_browser_section = "search"}}
    label(search, {"mir-browser.search"}, math.max(160, list_width - 40))
    local field = search.add{type = "textfield", name = PREFIX .. "search", text = v.search, tags = {mir_browser = "search"}}
    field.style.width = detail_width
  end
  local body_height = math.max(140, frame.style.maximal_height - 140)
  -- Browse keeps its controls stationary.  The two sibling panes below carry
  -- their own bounded native scrolling, so reading one never moves the other.
  local browsing = v.tab == "research"
  local body = frame.add{type = browsing and "flow" or "scroll-pane", name = PREFIX .. "body", direction = "vertical"}
  if browsing then
    body.style.height = body_height
    body.style.maximal_height = body_height
  else
    body.style.maximal_height = body_height
  end
  local pages
  if v.tab == "settings" then
    pages = settings_rows(player, body, v)
  elseif v.tab == "queue" then
    pages = queue_rows(player, body, v)
  elseif v.tab == "availability" then
    pages = availability_rows(player.force, body, v)
  else
    local filters = body.add{type = "flow", direction = "horizontal"}
    local family_index = 1
    for i,name in ipairs(c.family_names) do if name == v.family then family_index = i end end
    local family_items = {}
    for _, family in ipairs(c.family_names) do family_items[#family_items + 1] = family_caption(family) end
    filter_dropdown(filters, {"mir-browser.filter-scope"}, family_items, family_index, "family")
    filter_dropdown(filters, {"mir-browser.filter-status"}, {{"mir-browser.all-status"}, {"mir-browser.available"}, {"mir-browser.locked"}, {"mir-browser.queued"}}, v.status, "status")
    filter_dropdown(filters, {"mir-browser.filter-level"}, {{"mir-browser.all-levels"}, {"mir-browser.finite"}, {"mir-browser.infinite"}}, v.mode, "mode")
    local sort_index = v.sort == "native" and 2 or v.sort == "name-asc" and 3 or v.sort == "name-desc" and 4 or 1
    filter_dropdown(filters, {"mir-browser.filter-order"}, {{"mir-browser.order-progression"}, {"mir-browser.order-native"}, {"mir-browser.order-name-asc"}, {"mir-browser.order-name-desc"}}, sort_index, "sort")
    local has_hidden = false
    for name, is_hidden in pairs(v.hidden or {}) do
      if is_hidden == true and player.force.technologies[name] then has_hidden = true end
    end
    if has_hidden then
      local recovery = body.add{type = "flow", direction = "horizontal", tags = {mir_browser_section = "hidden-recovery"}}
      button(recovery, "show-hidden", {"mir-browser.show-hidden"})
    end
    local results = body.add{type = "flow", name = PREFIX .. "research_results", direction = "horizontal"}
    local reserved_height = RESEARCH_FILTERS_HEIGHT
      + (has_hidden and RESEARCH_HIDDEN_RECOVERY_HEIGHT or 0)
    local results_height = math.max(RESEARCH_PANES_MIN_HEIGHT, body_height - reserved_height)
    results.style.height = results_height
    results.style.maximal_height = results_height
    pages = update_research_results(player, results, v, c, cache)
  end
  local nav = frame.add{type = "flow", name = PREFIX .. "navigation"}
  nav.add{type = "button", name = PREFIX .. "prev", caption = "<", tags = {mir_browser = "prev"}}
  nav.add{type = "label", name = PREFIX .. "page"}
  nav.add{type = "button", name = PREFIX .. "next", caption = ">", tags = {mir_browser = "next"}}
  update_navigation(frame, v, pages)
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
  if action == "select" then
    v.selected, v.effect_page = tags.technology, 1
    if v.tab == "queue" then v.tab, v.page = "research", 1 end
  elseif action == "queue-up" or action == "queue-down" then
    actions.move(player, tags.index, action == "queue-up" and -1 or 1,
      tags.technology, tags.adjacent, defines.input_action.move_research)
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
  elseif action == "settings" or action == "research" or action == "queue" or action == "availability" then
    v.tab, v.page = action, 1
    if action ~= "research" then v.search = "" end
  elseif action == "export" then export(player)
  elseif action == "refresh" then
    local translations = translation_state()
    local cache = translations[player.index]
    if cache then cache.priority_token = nil end
  end
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
    if v.sort == "progression" or v.sort == "native" then v.stable_sort = v.sort end
  else v[action] = event.element.selected_index end
  v.page = 1; render(player)
end
function M.on_init()
  mir_provider.invalidate_omissions()
  set_force_refresh_subscription(false)
  for _, player in pairs(game.players) do
    remove_legacy_top_button(player)
    set_shortcut_toggled(player, false)
  end
end
function M.on_configuration_changed()
  mir_provider.invalidate_omissions()
  state().pending_force_refresh = {}
  set_force_refresh_subscription(false)
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
    view(player)
    remove_legacy_top_button(player)
  end
  refresh_open()
  for _, player in pairs(game.players) do
    if not player.gui.screen[ROOT] then set_shortcut_toggled(player, false) end
  end
end

local function schedule_open_force_refresh(force)
  if not force then return end
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
    pump_translation_requests(player, cache)
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
        pump_translation_requests(player, cache)
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
        if options.tab == "settings" or options.tab == "research"
            or options.tab == "queue" or options.tab == "availability" then
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
  script.on_event(defines.events.on_gui_click, click)
  script.on_event(defines.events.on_gui_selection_state_changed, selection)
  script.on_event(defines.events.on_string_translated, translated)
  script.on_nth_tick(TRANSLATION_MAINTENANCE_TICKS, maintain_translations)
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
