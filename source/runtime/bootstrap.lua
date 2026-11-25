-- Explicit control-stage composition for the private MIR5 Library slice.
--
-- Modules are loaded at control parse time. This is deliberately a small,
-- named set of bindings rather than a generic event dispatcher: lifecycle
-- remains the sole cap-policy owner and the Library owns only its own view
-- callbacks.
local lifecycle = require("runtime.lifecycle")
local library = require("runtime.library")
local catalogue = require("runtime.catalogue")
local runtime_api = require("api.v1.runtime")
local settings_profile = require("runtime.settings_profile")
local settings_commands = require("runtime.settings_commands")
local diagnostics = helpers and type(helpers.write_file) == "function" and require("runtime.diagnostics")
local passive_repair = require("runtime.passive_repair")
local effective = require("runtime.configuration")
local target = require("platform.target")
local function required_runtime_export(module, component, name)
  local value = module[name]
  if type(value) ~= "function" then
    error("MIR runtime " .. component .. " requires callable " .. name, 2)
  end
  return value
end
required_runtime_export(lifecycle, "caps", "preflight")
local worker_storage_route_export
local worker_default_split_export
local finite_research_speed_provider_export
if target.id == "f200" or target.id == "f210" then
  worker_storage_route_export = required_runtime_export(catalogue, "catalogue", "worker_storage_route")
  worker_default_split_export = required_runtime_export(catalogue, "catalogue", "worker_default_split")
  finite_research_speed_provider_export = required_runtime_export(catalogue, "catalogue", "finite_research_speed_provider")
end
local finite_research_speed = (target.id == "f200" or target.id == "f210")
  and require("runtime.finite_research_speed")
local worker_robot_storage = (target.id == "f200" or target.id == "f210")
  and require("runtime.worker_robot_storage")
if worker_robot_storage then
  local worker_values = effective.streams and effective.streams["worker-robots-storage"]
  worker_robot_storage.configure(worker_values and worker_values.max_level, worker_values and worker_values.enabled)
end
local function worker_storage_route()
  if worker_storage_route_export == nil then return nil end
  return worker_storage_route_export()
end
local WORKER_DEFAULT_SPLIT = worker_robot_storage and worker_default_split_export() or false
local function worker_storage_mutating(event)
  return worker_robot_storage and worker_robot_storage.default_owner_mutating(event) or false
end
local function finite_research_speed_provider()
  if finite_research_speed_provider_export == nil then return nil end
  return finite_research_speed_provider_export()
end
local DISCOVERY_TREE = script and script.active_mods and script.active_mods.discovery_tree ~= nil
local native_credits, legacy_module_credits, legacy_cannon_credits
if target.recipe_productivity == true then
  native_credits = require("runtime.native_credits")
  -- Absence of this optional subsystem is decided above. Its history and
  -- paid-work callbacks are mandatory once it is active; a broken interface
  -- must not skip admission or silently drop continuation events.
  for _, name in ipairs({"preflight_family_transition", "preflight_force_created",
      "preflight_force_reset", "preflight_forces_merged", "preflight_technology_effects_reset",
      "needs_research_events", "on_research_finished", "on_research_cancelled"}) do
    required_runtime_export(native_credits, "native credits", name)
  end
  legacy_module_credits = require("runtime.legacy_module_credits")
  legacy_cannon_credits = require("runtime.legacy_cannon_credits")
end
local spoilage_contribution = require("runtime.spoilage_contribution")
local repair_config = {enabled = effective.passive_repair_enabled == true}
-- The Space Age lifecycle body is absent from base-only control stages.
local scripted_effects, native_gun_credits
local active_mods = script and script.active_mods or mods or {}
local se_system_force = target.id == "f200" and active_mods["space-exploration"] == "0.7.57"
  and require("runtime.space_exploration_system_force")
if type(active_mods) == "table" and active_mods["space-age"] ~= nil then
  scripted_effects = require("runtime.scripted_effects")
  if target.recipe_productivity == true then
    native_gun_credits = require("runtime.native_gun_credits")
    native_gun_credits.set_retirement_policy(lifecycle.reconcile_retired_paid_work)
    lifecycle.set_retired_work_observer(native_gun_credits.has_retired_work)
  end
end
-- A removed provider is absent from script.active_mods by the time the
-- configuration callback runs. Keep this finite list aligned with the exact
-- F200 runtime adapters; it also recognizes a current F210 provider without
-- importing the F200 adapter.
local COMPETING_PROVIDER_IDS = {
  "ExpandedProductivityResearch",
  "plates-n-circuit-productivity",
  "Science_packs_productivity",
  "bioflux-productivity",
  "fish-productivity",
  "crafting-efficiency-2",
  "ProductivityResearch",
}

local function has_competing_provider(values)
  if type(values) ~= "table" then return false end
  for index = 1, #COMPETING_PROVIDER_IDS do
    if values[COMPETING_PROVIDER_IDS[index]] ~= nil then return true end
  end
  return false
end

-- A bounded foreign-owner adapter is needed only while its named provider is
-- present. It owns no module discovery and is imported before callbacks.
local competing_productivity
if target.id == "f200" and has_competing_provider(active_mods) then
  competing_productivity = require("runtime.competing_productivity")
end

local function relevant_competing_provider_transition(event)
  if competing_productivity ~= nil then return true end
  if has_competing_provider(active_mods) then return true end
  local changes = event and event.mod_changes
  if type(changes) ~= "table" then return false end
  for index = 1, #COMPETING_PROVIDER_IDS do
    local change = changes[COMPETING_PROVIDER_IDS[index]]
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
local reconcile_library_events
local library_events_scheduled
local credit_events_scheduled
local gun_credit_events_scheduled
local worker_events_scheduled
local worker_completion_tick_scheduled
local library_refresh_scheduled
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
  reconcile_library_events()
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
  if type(options.search) == "string" then result.search = options.search end
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
  if diagnostics then
    commands.add_command("mir-diagnostics-export", "Replace the bounded MIR report and export full MIR settings; attach factorio-current.log separately.",
      function(command) diagnostics.export(command and command.player_index) end)
  end
  if worker_robot_storage then
    commands.add_command("mir-worker-storage-recovery",
      "Administrator/server only: prepare a COPY before adding a finite worker-storage provider, or resume preserved partial work.",
      function(command)
        worker_robot_storage.command(command, worker_storage_route())
        reconcile_library_events()
      end)
  end
end

local function on_init()
  local native_credit_plan = native_credits and native_credits.preflight_family_transition(nil, true)
  local cap_plan = lifecycle.preflight(false)
  if worker_robot_storage then
    worker_robot_storage.on_init(worker_storage_route())
    worker_robot_storage.default_owner_on_init(worker_storage_route(), WORKER_DEFAULT_SPLIT)
  end
  if finite_research_speed then finite_research_speed.on_init(finite_research_speed_provider()) end
  initialize_imersite()
  lifecycle.on_init(cap_plan)
  if native_credits then native_credits.on_init(native_credit_plan) end
  if native_gun_credits then native_gun_credits.on_init() end
  if competing_productivity then competing_productivity.on_init() end
  if scripted_effects then scripted_effects.on_init() end
  library.on_init()
  reconcile_repair()
  reconcile_translations()
  if se_system_force then se_system_force.observe() end
  if diagnostics then diagnostics.startup("MIR initialization") end
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
  local se_system_force_plan = se_system_force and se_system_force.preflight(event)
  local cap_plan = lifecycle.preflight(true)
  local changes = event and event.mod_changes
  local muria = type(changes) == "table" and changes.Muria
  local mir = type(changes) == "table" and changes["more-infinite-research"]
  local secretas = type(changes) == "table" and changes.secretas
  local worker_default_plan = worker_robot_storage
    and worker_robot_storage.default_owner_preflight(event, worker_storage_route(), WORKER_DEFAULT_SPLIT)
  local worker_provider_handover = worker_robot_storage
    and worker_robot_storage.default_owner_delegated(worker_default_plan)
  local worker_prepared_default = worker_default_plan and worker_default_plan.prepared_default == true
  -- The default-owner plan authenticates and consumes this complete prepared
  -- witness. Do not issue a second legacy plan that could reinstall its quota.
  local worker_storage_plan = not worker_prepared_default and worker_robot_storage and worker_robot_storage.preflight(event, worker_storage_route(),
    worker_provider_handover and worker_default_plan or nil)
  local worker_default_caps = lifecycle.preflight_worker_storage_split_caps(worker_default_plan)
  if (target.id == "f200" or target.id == "f210") and type(secretas) == "table"
      and ((secretas.old_version ~= nil) ~= (secretas.new_version ~= nil))
      and (mir == nil or mir.old_version ~= nil)
      and not worker_prepared_default and not (worker_robot_storage and worker_robot_storage.plan_prepared(worker_storage_plan)) then
    -- Foreign finite4..8 and MIR's infinite4/9 represent different paid
    -- identities. Do not guess their former levels after prototype migration.
    error("MIR cannot safely add or remove Secretas on this unprepared save; keep the protected original COPY and prepare its MIR-default infinite worker4 before adding the provider using /mir-worker-storage-recovery prepare", 2)
  end
  if target.id == "f210" and type(muria) == "table"
      and ((muria.old_version ~= nil) ~= (muria.new_version ~= nil))
      and (mir == nil or mir.old_version ~= nil) then
    -- Finite foreign7/8 and MIR's infinite7/9 have different earned-effect
    -- identities. After native prototype migration, old levels cannot be
    -- inferred safely. Refuse before MIR writes state; keep the original save.
    error("MIR cannot safely add or remove Muria on an existing MIR save; restore the previous mod selection and original save", 2)
  end
  -- The first published-MIR4 preference transition has no durable old setting.
  -- This preflight must run before any lifecycle reconciler can write a level,
  -- ownership record, queue state, or disablement flag.
  local family_credit_plan
  local finite_speed_plan = finite_research_speed
    and finite_research_speed.preflight(event, finite_research_speed_provider())
  if native_credits then
    native_credits.preflight_legacy_preference_transition(event, relevant_competing_provider_transition(event))
    family_credit_plan = native_credits.preflight_family_transition(event)
  end
  local module_credit_plan = legacy_module_credits and legacy_module_credits.preflight(event)
  local cannon_credit_plan = legacy_cannon_credits and legacy_cannon_credits.preflight(event)
  local gun_credit_plan = native_gun_credits and native_gun_credits.preflight(event)
  if worker_robot_storage then
    if worker_prepared_default then
      worker_robot_storage.default_owner_apply(worker_default_plan)
    elseif worker_provider_handover then
      -- Native setters can raise scripted callbacks. Keep the old route until
      -- its work is completely on the private holder, then install its quota.
      worker_robot_storage.default_owner_apply(worker_default_plan)
      worker_robot_storage.apply(worker_storage_plan)
    elseif worker_storage_plan and worker_storage_plan.retired and worker_default_plan
        and worker_default_plan.kind == "default-native-provider-gate-settle" then
      worker_robot_storage.default_owner_apply(worker_default_plan)
      worker_robot_storage.apply(worker_storage_plan)
    else
      worker_robot_storage.apply(worker_storage_plan)
      worker_robot_storage.default_owner_apply(worker_default_plan)
    end
    lifecycle.apply_worker_storage_split_caps(worker_default_caps)
  end
  if finite_research_speed then finite_research_speed.apply(finite_speed_plan) end
  reconcile_imersite()
  lifecycle.on_configuration_changed(event, cap_plan)
  if native_credits then native_credits.on_configuration_changed(event, family_credit_plan) end
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
  if legacy_module_credits then legacy_module_credits.apply(module_credit_plan) end
  if legacy_cannon_credits then legacy_cannon_credits.apply(cannon_credit_plan) end
  if native_gun_credits then native_gun_credits.on_configuration_changed(event, gun_credit_plan) end
  library.on_configuration_changed(event)
  reconcile_repair()
  reconcile_translations()
  -- Restore only the separately admitted SE scripted NPC policy, after all
  -- native plans have verified their original zero-contribution frames.
  if se_system_force then
    if not se_system_force.apply(se_system_force_plan) then se_system_force.observe() end
  elseif target.id == "f200" then
    storage.mir_se_conquest_policy_force = nil
  end
  if diagnostics then diagnostics.startup("MIR configuration change") end
end

local function on_load()
  if worker_robot_storage then
    worker_robot_storage.on_load(worker_storage_route())
    worker_robot_storage.default_owner_on_load(WORKER_DEFAULT_SPLIT)
  end
  if finite_research_speed then finite_research_speed.on_load(finite_research_speed_provider()) end
  lifecycle.on_load()
  if native_credits then native_credits.on_load() end
  if native_gun_credits then native_gun_credits.on_load() end
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
  if library.on_lua_shortcut(event) then reconcile_translations() end
end

local function on_library_display_changed(event)
  if library.on_player_display_changed(event) then reconcile_translations() end
end

local function on_library_player_removed(event)
  library.on_player_removed(event)
  reconcile_translations()
end

local function on_library_player_pre_removed(event)
  library.on_pre_player_removed(event)
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

local function on_library_player_left(event)
  library.on_player_left_game(event)
  reconcile_translations()
end

local function request_library_refresh(event)
  if library_events_scheduled then
    library.on_native_state_changed(event)
    reconcile_translations()
  end
end

local function on_research_finished(event)
  if not (event and event.research) or event.research.valid == false then return end
  local worker_default_changed, worker_default_settled = false, false
  if worker_robot_storage then
    worker_default_changed, worker_default_settled =
      worker_robot_storage.default_owner_on_research_finished(event, lifecycle.record_completed_worker_cap)
    if worker_robot_storage.on_research_event(event, true) or worker_default_changed then reconcile_library_events() end
  end
  if native_credits and native_credits.on_research_finished(event) then reconcile_library_events() end
  if native_gun_credits and native_gun_credits.on_research_finished(event) then reconcile_library_events() end
  if lifecycle.caps_active() and not worker_storage_mutating(event) then
    lifecycle.on_research_finished(event)
    if worker_default_settled then
      -- Its first native completion also fulfils the public prerequisite.
      -- Reconcile only that changed head's presentation, never the work queue.
      lifecycle.on_research_finished({research=event.research.force.technologies["worker-robots-storage-4"]})
    end
  end
  if competing_productivity then competing_productivity.on_research_finished(event) end
  if scripted_effects then scripted_effects.on_research_finished(event) end
  request_library_refresh(event)
end

local function on_research_reversed(event)
  if not (event and event.research) or event.research.valid == false then return end
  if lifecycle.caps_active() and not worker_storage_mutating(event) then lifecycle.on_research_reversed(event) end
  if competing_productivity then competing_productivity.on_research_reversed(event) end
  if scripted_effects then scripted_effects.on_research_reversed(event) end
  request_library_refresh(event)
end

local function on_technology_effects_reset(event)
  local native_credit_plan = native_credits and native_credits.preflight_technology_effects_reset(event)
  if not worker_storage_mutating(event) then lifecycle.on_technology_effects_reset(event) end
  if native_credits then native_credits.on_technology_effects_reset(event, native_credit_plan) end
  if competing_productivity then competing_productivity.on_technology_effects_reset(event) end
  if scripted_effects then scripted_effects.on_technology_effects_reset(event) end
  if legacy_module_credits then legacy_module_credits.on_technology_effects_reset(event) end
  if legacy_cannon_credits then legacy_cannon_credits.on_technology_effects_reset(event) end
  if native_gun_credits then native_gun_credits.on_technology_effects_reset(event) end
  request_library_refresh(event)
end

local function on_research_started(event)
  if not (event and event.research) or event.research.valid == false then return end
  if worker_robot_storage and worker_robot_storage.on_research_event(event) then reconcile_library_events() end
  if native_gun_credits then native_gun_credits.on_research_queue_event(event) end
  if lifecycle.caps_active() and not worker_storage_mutating(event) then lifecycle.on_research_started(event) end
  if competing_productivity then competing_productivity.on_research_started(event) end
  request_library_refresh(event)
end

local function on_research_cancelled(event)
  if worker_robot_storage and worker_robot_storage.on_research_event(event) then reconcile_library_events() end
  if native_credits and native_credits.on_research_cancelled(event) then reconcile_library_events() end
  if native_gun_credits and native_gun_credits.on_research_cancelled(event) then reconcile_library_events() end
  if lifecycle.caps_active() and not worker_storage_mutating(event) then lifecycle.on_research_cancelled(event) end
  if competing_productivity then competing_productivity.on_research_cancelled(event) end
  request_library_refresh(event)
end

local function on_worker_completion_tick(event)
  local changed, settled = false, nil
  if worker_robot_storage then
    changed, settled = worker_robot_storage.default_owner_on_completion_tick(event, lifecycle.record_completed_worker_cap)
  end
  if lifecycle.caps_active() and changed and type(settled) == "table" then
    for _, force in ipairs(settled) do
      lifecycle.on_research_finished({research=force.technologies["worker-robots-storage-4"]})
    end
  end
  if worker_robot_storage and type(worker_robot_storage.on_prepared_queue_tick) == "function" then
    worker_robot_storage.on_prepared_queue_tick(event)
  end
  -- Release the one-shot subscription after the last durable marker settles.
  reconcile_library_events()
end

local function on_tower_planted_seed(event)
  if scripted_effects then scripted_effects.on_tower_planted_seed(event) end
end

local function on_force_created(event)
  local native_credit_plan = native_credits and native_credits.preflight_force_created(event)
  if worker_robot_storage then
    worker_robot_storage.on_force_created(event)
    worker_robot_storage.default_owner_on_force_created(event)
  end
  if event and event.force then initialize_imersite(event.force) end
  if native_credits then native_credits.on_force_created(event, native_credit_plan) end
  if native_gun_credits then native_gun_credits.on_force_created(event) end
  -- Authored prototype disablement may retain restoration rights even when
  -- all caps are unlimited. Clear those rights at existing force boundaries.
  lifecycle.on_force_created(event)
  if competing_productivity then competing_productivity.on_force_created(event) end
  if scripted_effects then scripted_effects.on_force_created(event) end
  reconcile_library_events()
  request_library_refresh(event)
end

local function on_force_reset(event)
  local native_credit_plan = native_credits and native_credits.preflight_force_reset(event)
  if worker_robot_storage then
    worker_robot_storage.on_force_reset(event)
    worker_robot_storage.default_owner_on_force_reset(event)
  end
  if event and event.force then initialize_imersite(event.force) end
  if native_credits then native_credits.on_force_reset(event, native_credit_plan) end
  if native_gun_credits then native_gun_credits.on_force_reset(event) end
  lifecycle.on_force_reset(event)
  if competing_productivity then competing_productivity.on_force_reset(event) end
  if scripted_effects then scripted_effects.on_force_reset(event) end
  reconcile_library_events()
  request_library_refresh(event)
end

local function on_forces_merging(event)
  if worker_robot_storage then worker_robot_storage.default_owner_on_forces_merging(event) end
end

local function on_forces_merged(event)
  local native_credit_plan = native_credits and native_credits.preflight_forces_merged(event)
  local worker_merge_unqualified = false
  if worker_robot_storage then
    worker_robot_storage.on_forces_merged(event)
    local _, disposition = worker_robot_storage.default_owner_on_forces_merged(event)
    worker_merge_unqualified = disposition == "unqualified-native-merge-frame"
    if worker_merge_unqualified then
      log("MIR worker storage: mixed native merge work retained without worker-cargo cap reconciliation; this draft case is unqualified")
    end
  end
  if native_credits then native_credits.on_forces_merged(event, native_credit_plan) end
  if imersite and event and event.destination then
    local state = imersite_state()
    if state then
      state.forces[event.source_index] = nil
      state.forces[event.destination.index] = nil
    end
    initialize_imersite(event.destination)
    reconcile_imersite(event.destination)
  end
  lifecycle.on_forces_merged(event, worker_merge_unqualified and "worker-robots-storage" or nil)
  if native_gun_credits then native_gun_credits.on_forces_merged(event) end
  if competing_productivity then competing_productivity.on_forces_merged(event) end
  if scripted_effects then scripted_effects.on_forces_merged(event) end
  if legacy_module_credits and event and event.destination then
    legacy_module_credits.on_technology_effects_reset({force=event.destination})
  end
  if legacy_cannon_credits and event and event.destination then
    legacy_cannon_credits.on_technology_effects_reset({force=event.destination})
  end
  reconcile_library_events()
  request_library_refresh(event)
end

local function on_research_queued(event)
  if not (event and event.research) or event.research.valid == false then return end
  if worker_robot_storage and worker_robot_storage.on_research_event(event) then reconcile_library_events() end
  if native_gun_credits then native_gun_credits.on_research_queue_event(event) end
  if DISCOVERY_TREE then
    if lifecycle.caps_active() and not worker_storage_mutating(event) then lifecycle.on_discovery_tree_queue_changed(event) end
    if competing_productivity and competing_productivity.active() then competing_productivity.on_discovery_tree_queue_changed(event) end
  end
  request_library_refresh(event)
end

local function on_discovery_setting_changed(event)
  if lifecycle.caps_active() then lifecycle.on_discovery_tree_changed(event) end
  if competing_productivity and competing_productivity.active() then competing_productivity.on_discovery_tree_changed(event) end
  request_library_refresh(event)
end

local function bind_runtime_events(library_open)
  local credit_pending = native_credits and native_credits.needs_research_events() or false
  local gun_credit_pending = native_gun_credits and native_gun_credits.needs_research_events() or false
  credit_pending = credit_pending or gun_credit_pending
  local worker_pending = worker_robot_storage and worker_robot_storage.needs_research_events() or false
  local worker_completion_tick = worker_robot_storage
    and type(worker_robot_storage.default_owner_completion_pending_tick) == "function"
    and worker_robot_storage.default_owner_completion_pending_tick() or nil
  if worker_robot_storage and type(worker_robot_storage.prepared_queue_pending) == "function" then
    worker_completion_tick = worker_completion_tick or worker_robot_storage.prepared_queue_pending() or nil
  end
  credit_pending = credit_pending or worker_pending
  if library_events_scheduled == library_open and credit_events_scheduled == credit_pending
      and gun_credit_events_scheduled == gun_credit_pending
      and worker_events_scheduled == worker_pending and worker_completion_tick_scheduled == worker_completion_tick then return end
  library_events_scheduled = library_open
  credit_events_scheduled = credit_pending
  gun_credit_events_scheduled = gun_credit_pending
  worker_events_scheduled = worker_pending
  worker_completion_tick_scheduled = worker_completion_tick
  local events = defines and defines.events or {}
  local competing_active = competing_productivity and competing_productivity.active()
  local force_lifecycle_active = lifecycle.caps_active()
    or native_credits ~= nil
    or native_gun_credits ~= nil
    or competing_active
    or (scripted_effects and scripted_effects.events_active())
    or imersite ~= nil
    or (worker_robot_storage and worker_robot_storage.force_events())
    or library_open
  if force_lifecycle_active then
    if events.on_force_created then script.on_event(events.on_force_created, on_force_created) end
    if events.on_force_reset then script.on_event(events.on_force_reset, on_force_reset) end
    if events.on_forces_merging then script.on_event(events.on_forces_merging, on_forces_merging) end
    if events.on_forces_merged then script.on_event(events.on_forces_merged, on_forces_merged) end
  else
    -- Remove previous closures when no runtime owner or open Library needs
    -- these force boundaries after a configuration/view transition.
    if events.on_force_created then script.on_event(events.on_force_created, nil) end
    if events.on_force_reset then script.on_event(events.on_force_reset, nil) end
    if events.on_forces_merging then script.on_event(events.on_forces_merging, nil) end
    if events.on_forces_merged then script.on_event(events.on_forces_merged, nil) end
  end
  -- The Library observes native changes only while a connected owned view is
  -- open. Cap admission and scripted effects retain their independent guards.
  if events.on_research_started then
    local active = lifecycle.caps_active() or competing_active or library_open or worker_pending or gun_credit_pending
    script.on_event(events.on_research_started, active and on_research_started or nil)
  end
  if events.on_research_cancelled then
    local active = lifecycle.caps_active() or competing_active or library_open or credit_pending
    script.on_event(events.on_research_cancelled, active and on_research_cancelled or nil)
  end
  if events.on_research_finished then
    local active = lifecycle.caps_active() or competing_active or (scripted_effects and scripted_effects.events_active()) or library_open or credit_pending
    script.on_event(events.on_research_finished, active and on_research_finished or nil)
  end
  if events.on_research_reversed then
    local active = lifecycle.caps_active() or competing_active or (scripted_effects and scripted_effects.events_active()) or library_open
    script.on_event(events.on_research_reversed, active and on_research_reversed or nil)
  end
  if events.on_technology_effects_reset then
    local active = lifecycle.caps_active() or native_credits ~= nil or native_gun_credits ~= nil
      or competing_active or (scripted_effects and scripted_effects.events_active()) or library_open
    script.on_event(events.on_technology_effects_reset, active and on_technology_effects_reset or nil)
  end
  if events.on_research_queued then
    local active = library_open or worker_pending or gun_credit_pending
      or (DISCOVERY_TREE and (lifecycle.caps_active() or competing_active))
    script.on_event(events.on_research_queued, active and on_research_queued or nil)
  end
  if events.on_runtime_mod_setting_changed and DISCOVERY_TREE then
    script.on_event(events.on_runtime_mod_setting_changed,
      (lifecycle.caps_active() or competing_active or library_open) and on_discovery_setting_changed or nil)
  end
  if events.on_research_moved then script.on_event(events.on_research_moved, library_open and request_library_refresh or nil) end
  if events.on_tick then script.on_event(events.on_tick, worker_completion_tick and on_worker_completion_tick or nil) end
end

local function on_library_native_refresh(event)
  library.on_native_refresh_tick(event)
  reconcile_translations()
end

reconcile_library_events = function()
  local open, pending = library.native_subscription_needs()
  bind_runtime_events(open == true)
  pending = pending == true
  if library_refresh_scheduled ~= pending then
    script.on_nth_tick(library.native_refresh_ticks, pending and on_library_native_refresh or nil)
    library_refresh_scheduled = pending
  end
end

function M.register()
  library.set_cap_provider(lifecycle.cap_limits)
  if DISCOVERY_TREE then library.set_discovery_visibility_provider(lifecycle.discovery_visibility) end

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
  library_events_scheduled = nil
  credit_events_scheduled = nil
  gun_credit_events_scheduled = nil
  worker_events_scheduled = nil
  worker_completion_tick_scheduled = nil
  bind_runtime_events(false)
  script.on_nth_tick(library.native_refresh_ticks, nil)
  library_refresh_scheduled = false
  if events.on_entity_damaged then
    script.on_event(events.on_entity_damaged, repair_config.enabled and on_entity_damaged or nil,
      repair_config.enabled and {{filter = "type", type = "wall"}, {filter = "type", type = "gate", mode = "or"}} or nil)
  end
  if events.on_tower_planted_seed then
    local active = scripted_effects and scripted_effects.agriculture_events_active()
    script.on_event(events.on_tower_planted_seed, active and on_tower_planted_seed or nil)
  end
  if events.on_lua_shortcut then script.on_event(events.on_lua_shortcut, on_library_shortcut) end
  for _, name in ipairs{
    "on_gui_text_changed", "on_gui_selected_tab_changed", "on_gui_selection_state_changed",
    "on_gui_checked_state_changed", "on_gui_click", "on_gui_location_changed", "on_gui_closed",
  } do
    local id = events[name]
    if id then
      script.on_event(id, function(event)
        if not library.has_library_gui_name(event) then return end
        library[name](event)
        reconcile_translations()
      end)
    end
  end
  if events.on_player_display_scale_changed then script.on_event(events.on_player_display_scale_changed, on_library_display_changed) end
  if events.on_player_display_resolution_changed then script.on_event(events.on_player_display_resolution_changed, on_library_display_changed) end
  if events.on_pre_player_removed then script.on_event(events.on_pre_player_removed, on_library_player_pre_removed) end
  if events.on_player_removed then script.on_event(events.on_player_removed, on_library_player_removed) end
  if events.on_string_translated then script.on_event(events.on_string_translated, on_library_string_translated) end
  if events.on_player_locale_changed then script.on_event(events.on_player_locale_changed, on_library_locale_changed) end
  if events.on_player_changed_force then script.on_event(events.on_player_changed_force, on_library_force_changed) end
  if events.on_player_joined_game then script.on_event(events.on_player_joined_game, on_library_player_joined) end
  if events.on_player_left_game then script.on_event(events.on_player_left_game, on_library_player_left) end
end

return M
