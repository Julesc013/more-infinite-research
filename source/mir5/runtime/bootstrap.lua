-- Explicit control-stage composition for the private MIR5 Library slice.
--
-- Modules are loaded at control parse time. This is deliberately a small,
-- named set of bindings rather than a generic event dispatcher: lifecycle
-- remains the sole cap-policy owner and the Library owns only its own view
-- callbacks.
local lifecycle = require("runtime.lifecycle")
local library = require("runtime.library")
local catalogue = require("research.catalogue")
local runtime_api = require("api.v1.runtime")
local settings_profile = require("runtime.settings_profile")
local settings_commands = require("runtime.settings_commands")
local passive_repair = require("runtime.passive_repair")
local effective = require("runtime.configuration")
local target = require("platform.target")
local native_credits
if target.recipe_productivity == true then
  native_credits = require("runtime.native_credits")
end
local spoilage_contribution = require("runtime.spoilage_contribution")
local repair_config = {enabled = effective.passive_repair_enabled == true}
-- The Space Age lifecycle body is absent from base-only control stages.
local scripted_effects
local active_mods = script and script.active_mods or mods or {}
if type(active_mods) == "table" and active_mods["space-age"] ~= nil then
  scripted_effects = require("runtime.scripted_effects")
end
-- A bounded foreign-owner adapter is needed only while its named provider is
-- present. It owns no module discovery and is imported before callbacks.
local competing_productivity
if type(active_mods) == "table" and (active_mods.ExpandedProductivityResearch ~= nil
    or active_mods["plates-n-circuit-productivity"] ~= nil
    or active_mods.Science_packs_productivity ~= nil
    or active_mods["bioflux-productivity"] ~= nil
    or active_mods["fish-productivity"] ~= nil
    or active_mods["crafting-efficiency-2"] ~= nil
    or active_mods.ProductivityResearch ~= nil)
    and target.id == "f200" then
  competing_productivity = require("runtime.competing_productivity")
end

-- A removed provider is absent from script.active_mods by the time the
-- configuration callback runs. Keep this list aligned with the exact
-- F200 runtime adapters so the legacy migration guard can distinguish that
-- meaningful removal from an ordinary Base startup-setting change.
local COMPETING_PROVIDER_IDS = {
  ExpandedProductivityResearch = true,
  ["plates-n-circuit-productivity"] = true,
  Science_packs_productivity = true,
  ["bioflux-productivity"] = true,
  ["fish-productivity"] = true,
  ["crafting-efficiency-2"] = true,
  ProductivityResearch = true,
}

local function relevant_competing_provider_transition(event)
  if competing_productivity ~= nil then return true end
  local changes = event and event.mod_changes
  if type(changes) ~= "table" then return false end
  for name in pairs(COMPETING_PROVIDER_IDS) do
    local change = changes[name]
    if type(change) == "table" and type(change.old_version) == "string" then return true end
  end
  return false
end

-- Historical JSON carrier recovery is independent of caps and scripted
-- contributions. No K2 body or migration state exists on an inactive profile.
local imersite, imersite_contract, imersite_change
if active_mods.Krastorio2 and active_mods["Krastorio2-spaced-out"]
    and active_mods.Krastorio2Assets and active_mods["k2so-assets"] and active_mods["space-age"]
    and type(active_mods.base) == "string" and active_mods.base:match("^2%.1%.") then
  imersite_contract = require("research.k2_imersite")
  imersite = require("runtime.k2_imersite_migration")
  imersite_change = effective.streams[imersite_contract.stream].effect_percent / 100
end

local function imersite_state()
  local value = storage[imersite_contract.storage_key]
  if value ~= nil and (type(value) ~= "table" or value.schema ~= 1 or type(value.forces) ~= "table") then
    error("MIR unsupported Imersite migration storage",2)
  end
  return value
end

local function reconcile_imersite(selected_force)
  if not imersite then return end
  local state = imersite_state() or {schema=1,forces={}}
  local namespace = storage.mir
  local adoption = type(namespace) == "table" and namespace.productivity_family_adoption
  local legacy = type(adoption) == "table" and adoption.k2_imersite_staged_migration
  local function reconcile(force)
    imersite.reconcile_force(force,imersite_change,state.forces,type(legacy) == "table" and legacy[force.index] or nil)
  end
  if selected_force then reconcile(selected_force)
  else for _, force in pairs(game.forces) do reconcile(force) end end
  if next(state.forces) ~= nil then storage[imersite_contract.storage_key] = state end
end

local function initialize_imersite(force)
  if not imersite then return end
  if force then
    local state = imersite_state()
    if state then state.forces[force.index] = nil end
    imersite.initialize_force(force,imersite_change)
  else
    for _, candidate in pairs(game.forces) do imersite.initialize_force(candidate,imersite_change) end
  end
end

local M = {}

local API_INTERFACE = "more-infinite-research.api.v1"
local BROWSER_INTERFACE = "more-infinite-research-browser"
local SETTINGS_INTERFACE = "more-infinite-research-settings"
local repair_scheduled
local on_repair_tick
local translation_scheduled
local translation_maintenance_callback
local reconcile_translations
local browser_families = {all = true, external = true, mir = true}
for _, declaration in ipairs(catalogue.declared()) do
  browser_families[declaration.family] = true
end

-- Keep the shipped unversioned bucket in place, including saved LuaEntity
-- references. Neither a closed Library nor a disabled fresh feature allocates
-- this namespace; unrelated historical MIR fields stay with their owner.
local function repair_state(read_only)
  local namespace = storage.mir
  if namespace ~= nil and type(namespace) ~= "table" then
    if read_only then return nil end
    error("MIR invalid saved namespace")
  end
  local value = namespace and namespace.passive_repair
  if value ~= nil and type(value) ~= "table" then
    if read_only then return nil end
    error("MIR invalid passive repair state")
  end
  return value
end

local function save_repair_state(value)
  if value == nil then return end
  if storage.mir == nil then storage.mir = {} end
  storage.mir.passive_repair = value
end

local function schedule_repair(needed)
  needed = needed == true
  if repair_scheduled == needed then return end
  script.on_nth_tick(passive_repair.repair_interval_ticks, needed and on_repair_tick or nil)
  repair_scheduled = needed
end

local function reconcile_repair()
  local value, facts = passive_repair.reconcile(repair_config, repair_state())
  save_repair_state(value)
  schedule_repair(facts.needs_schedule)
end

local function on_entity_damaged(event)
  local value, facts = passive_repair.on_entity_damaged(game, repair_config, repair_state(), event)
  save_repair_state(value)
  schedule_repair(facts.needs_schedule)
end

on_repair_tick = function(event)
  local value, facts = passive_repair.on_nth_tick(game, repair_config, repair_state(), event)
  save_repair_state(value)
  schedule_repair(facts.needs_schedule)
end

-- The Library exposes a read-only answer based on its bounded durable
-- request ledger. It keeps translation cleanup independent from the shipped
-- repair cadence: no queue means no 61-tick callback is installed.
local function schedule_translations(needed)
  needed = needed == true
  if translation_scheduled == needed then return end
  script.on_nth_tick(library.translation_maintenance_ticks, needed and translation_maintenance_callback or nil)
  translation_scheduled = needed
end

reconcile_translations = function()
  schedule_translations(library.subscription_needs() == true)
end

translation_maintenance_callback = function(event)
  library.on_translation_maintenance(event)
  reconcile_translations()
end

local function valid(value)
  return value ~= nil and value.valid ~= false
end

local function player_for(index)
  if type(index) ~= "number" or not game or type(game.get_player) ~= "function" then return nil end
  local ok, player = pcall(function() return game.get_player(index) end)
  if not ok or not valid(player) then return nil end
  return player
end

local function browser_options(player, options)
  if type(options) ~= "table" then return nil end
  local result = {}
  if type(options.search) == "string" then result.query = options.search end
  if options.tab == "research" or options.tab == "settings" or options.tab == "queue"
      or options.tab == "availability" or options.tab == "help" then
    result.tab = options.tab
  end
  if options.settings_scope == "research" or options.settings_scope == "options" then
    result.settings_scope = options.settings_scope
  end
  if type(options.settings_search) == "string" then result.settings_search = options.settings_search end
  if type(options.family) == "string" and browser_families[options.family] == true then
    result.family = options.family
  end
  if options.mode == 1 or options.mode == 2 or options.mode == 3 then result.mode = options.mode end
  if type(options.status) == "number" and options.status == math.floor(options.status)
      and options.status >= 1 and options.status <= 4 then
    result.status = options.status
  end
  if type(options.visibility) == "number" and options.visibility == math.floor(options.visibility)
      and (options.visibility == 1 or options.visibility == 2) then
    result.visibility = options.visibility
  end
  if options.sort == "progression" or options.sort == "native"
      or options.sort == "name-asc" or options.sort == "name-desc" then
    result.sort = options.sort
  end
  if type(options.page) == "number" and options.page == math.floor(options.page)
      and options.page >= 1 and options.page <= 30000 then
    result.page = options.page
  end
  -- Library validates density, duplicate names, and actual force membership
  -- before persisting this remote list.  Keep this bridge shallow so it does
  -- not duplicate the bounded native lookups or mutate caller-owned input.
  if type(options.hidden) == "table" then result.hidden = options.hidden end

  -- The legacy interface admitted only technologies known to the caller's
  -- native force. Keep that boundary without asking the Library model to
  -- index an arbitrary LuaCustomTable key.
  if type(options.selected) == "string" and options.selected ~= "" and #options.selected <= 160 then
    local ok, technology = pcall(function()
      local force = player.force
      local technologies = force and force.technologies
      return technologies and technologies[options.selected] or nil
    end)
    if ok and valid(technology) then result.selected = options.selected end
  end
  return result
end

local function open_browser(player_index, options)
  local player = player_for(player_index)
  if not player then return false end
  local opened = library.open(player, browser_options(player, options)) ~= nil
  reconcile_translations()
  return opened
end

local function register_interface(name, members, label)
  if not remote or type(remote.add_interface) ~= "function" then
    error("MIR runtime remote interface support is unavailable: " .. name)
  end
  if remote.interfaces and remote.interfaces[name] ~= nil then
    error("MIR " .. label .. " interface collision: " .. name)
  end
  remote.add_interface(name, members)
end

local function add_command()
  -- The guard only accommodates the pure-Lua host controls. Factorio always
  -- supplies commands.add_command to a control-stage mod.
  if not commands or type(commands.add_command) ~= "function" then return end
  commands.add_command("mir-research", {"mir-browser.command"}, function(event)
    local player = player_for(event and event.player_index)
    if player then library.open(player) end
    reconcile_translations()
  end)
  commands.add_command("mir-settings-export",
    "Export the current effective MIR startup settings to script-output/more-infinite-research/settings/<name>.txt. Use --compact to omit defaults.",
    settings_commands.export)
  commands.add_command("mir-settings-import-check",
    "Validate a MIR settings profile string before pasting it into the mir-settings-profile-import startup setting.",
    settings_commands.validate)
end

local function on_init()
  initialize_imersite()
  lifecycle.on_init()
  if native_credits then native_credits.on_init() end
  if competing_productivity then competing_productivity.on_init() end
  if scripted_effects then scripted_effects.on_init() end
  library.on_init()
  reconcile_repair()
  reconcile_translations()
end

-- The provider can be removed between saves. No native EPR technology can be
-- trusted after that change, so discard only this exact private schema rather
-- than carrying an old disablement right into a later provider re-addition.
-- This deliberately performs no force or technology write.
local function discard_absent_competing_productivity_state()
  if competing_productivity or storage == nil then return end
  local value = storage.mir_competing_productivity
  if value == nil then return end
  if type(value) ~= "table" or value.schema ~= 1 or type(value.owned_disabled) ~= "table" then
    error("MIR unsupported competing productivity storage", 2)
  end
  storage.mir_competing_productivity = nil
end

local function on_configuration_changed(event)
  -- The first published-MIR4 preference transition has no durable old setting.
  -- This preflight must run before any lifecycle reconciler can write a level,
  -- ownership record, queue state, or disablement flag.
  if native_credits and target.id == "f200" then
    native_credits.preflight_legacy_preference_transition(event, relevant_competing_provider_transition(event))
  end
  reconcile_imersite()
  lifecycle.on_configuration_changed(event)
  if native_credits then native_credits.on_configuration_changed(event) end
  if competing_productivity then
    competing_productivity.on_configuration_changed(event)
  else
    discard_absent_competing_productivity_state()
  end
  if scripted_effects then
    scripted_effects.on_configuration_changed(event)
  else
    -- The active Space Age body is deliberately unavailable in a base-only
    -- stage.  Retire an existing global contribution only when its native
    -- property can still be read and restored safely; this branch never
    -- allocates storage or runs on load.
    local namespace = storage.mir
    if type(namespace) == "table" and namespace.spoilage_preservation ~= nil then
      local next_state, facts = spoilage_contribution.try_retire(game,
        namespace.spoilage_preservation, "space-age-removed")
      if not facts.unavailable_native_property then
        namespace.spoilage_preservation = next_state
      end
    end
  end
  library.on_configuration_changed(event)
  reconcile_repair()
  reconcile_translations()
end

local function on_load()
  lifecycle.on_load()
  if native_credits then native_credits.on_load() end
  if competing_productivity then competing_productivity.on_load() end
  if scripted_effects then scripted_effects.on_load() end
  library.on_load()
  -- No save writes or game access on load. Each joining client reconstructs
  -- the same conditional subscription from the retained queue.
  -- The shipped unversioned reader treated malformed legacy buckets as
  -- absent. Retain them unchanged here; writable boundaries still reject them.
  schedule_repair(passive_repair.on_load(repair_config, repair_state(true)).needs_schedule)
  reconcile_translations()
end

local function on_library_shortcut(event)
  library.on_lua_shortcut(event)
  reconcile_translations()
end

local function on_library_text_changed(event)
  library.on_gui_text_changed(event)
  reconcile_translations()
end

local function on_library_selection_changed(event)
  library.on_gui_selection_state_changed(event)
  reconcile_translations()
end

local function on_library_tab_changed(event)
  library.on_gui_selected_tab_changed(event)
  reconcile_translations()
end

local function on_library_click(event)
  library.on_gui_click(event)
  reconcile_translations()
end

local function on_library_location_changed(event)
  library.on_gui_location_changed(event)
  reconcile_translations()
end

local function on_library_closed(event)
  library.on_gui_closed(event)
  reconcile_translations()
end

local function on_library_player_removed(event)
  library.on_player_removed(event)
  reconcile_translations()
end

local function on_library_string_translated(event)
  library.on_string_translated(event)
  reconcile_translations()
end

local function on_library_locale_changed(event)
  library.on_player_locale_changed(event)
  reconcile_translations()
end

local function on_library_force_changed(event)
  library.on_player_changed_force(event)
  reconcile_translations()
end

local function on_library_player_joined(event)
  library.on_player_joined_game(event)
  reconcile_translations()
end

local function on_research_finished(event)
  if lifecycle.caps_active() then lifecycle.on_research_finished(event) end
  if competing_productivity then competing_productivity.on_research_finished(event) end
  if scripted_effects then scripted_effects.on_research_finished(event) end
end

local function on_research_reversed(event)
  if lifecycle.caps_active() then lifecycle.on_research_reversed(event) end
  if competing_productivity then competing_productivity.on_research_reversed(event) end
  if scripted_effects then scripted_effects.on_research_reversed(event) end
end

local function on_technology_effects_reset(event)
  if lifecycle.caps_active() then lifecycle.on_technology_effects_reset(event) end
  if native_credits then native_credits.on_technology_effects_reset(event) end
  if competing_productivity then competing_productivity.on_technology_effects_reset(event) end
  if scripted_effects then scripted_effects.on_technology_effects_reset(event) end
end

local function on_research_started(event)
  if lifecycle.caps_active() then lifecycle.on_research_started(event) end
  if competing_productivity then competing_productivity.on_research_started(event) end
end

local function on_research_cancelled(event)
  if lifecycle.caps_active() then lifecycle.on_research_cancelled(event) end
  if competing_productivity then competing_productivity.on_research_cancelled(event) end
end

local function on_tower_planted_seed(event)
  if scripted_effects then scripted_effects.on_tower_planted_seed(event) end
end

local function on_force_created(event)
  if event and event.force then initialize_imersite(event.force) end
  if native_credits then native_credits.on_force_created(event) end
  -- Authored prototype disablement may retain restoration rights even when
  -- all caps are unlimited. Clear those rights at existing force boundaries.
  lifecycle.on_force_created(event)
  if competing_productivity then competing_productivity.on_force_created(event) end
  if scripted_effects then scripted_effects.on_force_created(event) end
end

local function on_force_reset(event)
  if event and event.force then initialize_imersite(event.force) end
  if native_credits then native_credits.on_force_reset(event) end
  lifecycle.on_force_reset(event)
  if competing_productivity then competing_productivity.on_force_reset(event) end
  if scripted_effects then scripted_effects.on_force_reset(event) end
end

local function on_forces_merged(event)
  if native_credits then native_credits.on_forces_merged(event) end
  if imersite and event and event.destination then
    local state = imersite_state()
    if state then
      state.forces[event.source_index] = nil
      state.forces[event.destination.index] = nil
    end
    initialize_imersite(event.destination)
    reconcile_imersite(event.destination)
  end
  lifecycle.on_forces_merged(event)
  if competing_productivity then competing_productivity.on_forces_merged(event) end
  if scripted_effects then scripted_effects.on_forces_merged(event) end
end

function M.register()
  library.set_cap_provider(lifecycle.cap_limits)

  register_interface(API_INTERFACE, {
    get_version = runtime_api.get_version,
    get_capabilities = runtime_api.get_capabilities,
    get_research = runtime_api.get_research
  }, "API")
  register_interface(BROWSER_INTERFACE, {open = open_browser}, "Research Library")
  register_interface(SETTINGS_INTERFACE, {
    export_string = settings_profile.export_string,
    validate_string = settings_profile.validate_string
  }, "Settings profile")
  add_command()

  if script and type(script.on_init) == "function" then script.on_init(on_init) end
  if script and type(script.on_configuration_changed) == "function" then
    script.on_configuration_changed(on_configuration_changed)
  end
  if script and type(script.on_load) == "function" then script.on_load(on_load) end

  local events = defines and defines.events or {}
  schedule_repair(false)
  schedule_translations(false)
  if events.on_entity_damaged then
    script.on_event(events.on_entity_damaged, repair_config.enabled and on_entity_damaged or nil,
      repair_config.enabled and {{filter = "type", type = "wall"}, {filter = "type", type = "gate", mode = "or"}} or nil)
  end
  local competing_active = competing_productivity and competing_productivity.active()
  local force_lifecycle_active = lifecycle.caps_active()
    or native_credits ~= nil
    or competing_active
    or (scripted_effects and scripted_effects.events_active())
    or imersite ~= nil
  if force_lifecycle_active then
    if events.on_force_created then script.on_event(events.on_force_created, on_force_created) end
    if events.on_force_reset then script.on_event(events.on_force_reset, on_force_reset) end
    if events.on_forces_merged then script.on_event(events.on_forces_merged, on_forces_merged) end
  else
    -- A settings/profile transition may reuse the control registration from a
    -- finite save. Remove those exact native callbacks when all cap families
    -- are unlimited; otherwise their previous closures remain active.
    if events.on_force_created then script.on_event(events.on_force_created, nil) end
    if events.on_force_reset then script.on_event(events.on_force_reset, nil) end
    if events.on_forces_merged then script.on_event(events.on_forces_merged, nil) end
  end
  -- Research queue admission belongs solely to bounded cap ownership.  The
  -- direct scripted effects need the force callbacks above, but do not own
  -- start/cancel handling when every cap is unlimited.
  if events.on_research_started then
    local active = lifecycle.caps_active() or competing_active
    script.on_event(events.on_research_started, active and on_research_started or nil)
  end
  if events.on_research_cancelled then
    local active = lifecycle.caps_active() or competing_active
    script.on_event(events.on_research_cancelled, active and on_research_cancelled or nil)
  end
  if events.on_research_finished then
    local active = lifecycle.caps_active() or competing_active or (scripted_effects and scripted_effects.events_active())
    script.on_event(events.on_research_finished, active and on_research_finished or nil)
  end
  if events.on_research_reversed then
    local active = lifecycle.caps_active() or competing_active or (scripted_effects and scripted_effects.events_active())
    script.on_event(events.on_research_reversed, active and on_research_reversed or nil)
  end
  if events.on_technology_effects_reset then
    local active = lifecycle.caps_active() or native_credits ~= nil
      or competing_active or (scripted_effects and scripted_effects.events_active())
    script.on_event(events.on_technology_effects_reset, active and on_technology_effects_reset or nil)
  end
  if events.on_tower_planted_seed then
    local active = scripted_effects and scripted_effects.agriculture_events_active()
    script.on_event(events.on_tower_planted_seed, active and on_tower_planted_seed or nil)
  end
  if events.on_lua_shortcut then script.on_event(events.on_lua_shortcut, on_library_shortcut) end
  if events.on_gui_text_changed then script.on_event(events.on_gui_text_changed, on_library_text_changed) end
  if events.on_gui_selected_tab_changed then script.on_event(events.on_gui_selected_tab_changed, on_library_tab_changed) end
  if events.on_gui_selection_state_changed then script.on_event(events.on_gui_selection_state_changed, on_library_selection_changed) end
  if events.on_gui_click then script.on_event(events.on_gui_click, on_library_click) end
  if events.on_gui_location_changed then script.on_event(events.on_gui_location_changed, on_library_location_changed) end
  if events.on_gui_closed then script.on_event(events.on_gui_closed, on_library_closed) end
  if events.on_player_removed then script.on_event(events.on_player_removed, on_library_player_removed) end
  if events.on_string_translated then script.on_event(events.on_string_translated, on_library_string_translated) end
  if events.on_player_locale_changed then script.on_event(events.on_player_locale_changed, on_library_locale_changed) end
  if events.on_player_changed_force then script.on_event(events.on_player_changed_force, on_library_force_changed) end
  if events.on_player_joined_game then script.on_event(events.on_player_joined_game, on_library_player_joined) end
end

return M
