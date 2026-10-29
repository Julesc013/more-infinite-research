-- Lifecycle owner for the two Space Age scripted effects. The pure component
-- modules own their calculations; this module owns only their exact historic
-- unversioned `storage.mir` buckets and named event entry points.
local agriculture = require("runtime.agriculture")
local spoilage = require("runtime.spoilage")
local effective_values = require("runtime.configuration")

local M = {}

local AGRICULTURE_BUCKET = "agricultural_growth_speed"
local SPOILAGE_BUCKET = "spoilage_preservation"

local function resolved_config(values)
  -- Factorio reloads the control chunk when its active-mod set changes, so
  -- these fields are present for a real Space Age save. Keep a conservative
  -- inactive shape for a host reload that intentionally reuses a base-only
  -- settings module; it cannot grant an effect or cap ownership.
  if type(values) ~= "table" then return {enabled = false, per_level_percent = 0} end
  return {enabled = values.enabled == true, per_level_percent = values.effect_percent}
end

local agriculture_config = resolved_config(effective_values.agricultural_growth_speed)
local spoilage_config = resolved_config(effective_values.spoilage_preservation)
local scripted_effect_diagnostics = type(effective_values.options) == "table"
  and effective_values.options["mir-debug-scripted-effects"] == true

local function debug_log(message)
  if scripted_effect_diagnostics and type(log) == "function" then
    log("[more-infinite-research] scripted-effects " .. message)
  end
end

local function bucket(name)
  local namespace = storage.mir
  if namespace == nil then return nil end
  if type(namespace) ~= "table" then error("MIR invalid saved namespace", 3) end
  return namespace[name]
end

local function save_bucket(name, value)
  local namespace = storage.mir
  if value == nil then
    if namespace == nil then return end
    if type(namespace) ~= "table" then error("MIR invalid saved namespace", 3) end
    namespace[name] = nil
    return
  end
  if namespace == nil then
    namespace = {}
    storage.mir = namespace
  elseif type(namespace) ~= "table" then
    error("MIR invalid saved namespace", 3)
  end
  if type(value) ~= "table" then error("MIR invalid scripted-effect state", 3) end
  namespace[name] = value
end

local function refresh_agriculture(event_name)
  local value, facts = agriculture.refresh(game, agriculture_config, bucket(AGRICULTURE_BUCKET))
  save_bucket(AGRICULTURE_BUCKET, value)
  if scripted_effect_diagnostics then
    debug_log("agriculture event=" .. event_name
      .. " active=" .. tostring(facts.active)
      .. " refreshed=" .. tostring(facts.refreshed))
  end
end

local function reconcile_spoilage(event_name)
  local value, facts = spoilage.reconcile(game, spoilage_config, bucket(SPOILAGE_BUCKET))
  save_bucket(SPOILAGE_BUCKET, value)
  if scripted_effect_diagnostics then
    debug_log("spoilage event=" .. event_name
      .. " active=" .. tostring(facts.active)
      .. " reason=" .. tostring(facts.reason or "applied")
      .. " restored=" .. tostring(facts.restored == true)
      .. " level=" .. tostring(facts.effective_level or "")
      .. " ambiguous=" .. tostring(facts.external_write_ambiguous == true))
  end
end

local function research_name(event)
  local research = event and event.research
  return research and research.name or nil
end

function M.events_active()
  return agriculture_config.enabled == true or spoilage_config.enabled == true
end

function M.agriculture_events_active()
  return agriculture_config.enabled == true
end

function M.on_init()
  refresh_agriculture("init")
  reconcile_spoilage("init")
end

function M.on_configuration_changed()
  refresh_agriculture("configuration-changed")
  reconcile_spoilage("configuration-changed")
end

local function reconcile_research(event, event_name)
  local name = research_name(event)
  if name == agriculture.technology_name then
    refresh_agriculture(event_name)
  elseif name == spoilage.technology_name then
    reconcile_spoilage(event_name)
  end
end

function M.on_research_finished(event)
  reconcile_research(event, "research-finished")
end

function M.on_research_reversed(event)
  reconcile_research(event, "research-reversed")
end

function M.on_technology_effects_reset()
  refresh_agriculture("technology-effects-reset")
  reconcile_spoilage("technology-effects-reset")
end

-- Force lifecycle events can lower the highest completed spoilage level even
-- when every configured cap is unlimited. The merged source is already
-- invalid when Factorio raises on_forces_merged, so both components refresh
-- from the current game.forces snapshot instead of retaining a source row.
local function reconcile_force_change(event_name)
  refresh_agriculture(event_name)
  reconcile_spoilage(event_name)
end

function M.on_force_created()
  reconcile_force_change("force-created")
end

function M.on_force_reset()
  reconcile_force_change("force-reset")
end

function M.on_forces_merged()
  reconcile_force_change("forces-merged")
end

function M.on_tower_planted_seed(event)
  local value, facts = agriculture.on_tower_planted_seed(game, agriculture_config,
    bucket(AGRICULTURE_BUCKET), event)
  save_bucket(AGRICULTURE_BUCKET, value)
  if scripted_effect_diagnostics and facts.applied == true then
    debug_log("agriculture event=tower-planted-seed applied=true level=" .. tostring(facts.level)
      .. " multiplier=" .. tostring(facts.multiplier))
  end
end

-- No save reads, writes, or game access are allowed while Factorio restores a
-- save. This event-driven feature has no local subscriptions to reconstruct.
function M.on_load()
end

return M
