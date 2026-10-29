-- This fixture migration runs before successor configuration callbacks.  It
-- observes the exact foreign armor row seeded by the published-stage fixture;
-- it intentionally has no writes to fixture storage, force state, or MIR.
local KEY = "mir5_integration_catalogue_upgrade"
local PRIMARY = "recipe-prod-research_armor_components-1"

local function fail(message)
  error("[mir5-integration-catalogue-upgrade migration 0.2.0] " .. message)
end

local function expected_row(state)
  local snapshot = state.foreign_snapshot
  local technologies = type(snapshot) == "table" and snapshot.technologies or nil
  local row = type(technologies) == "table" and technologies[PRIMARY] or nil
  if type(row) ~= "table" then fail("requires the published armor foreign snapshot") end
  if type(row.level) ~= "number" or type(row.researched) ~= "boolean"
      or type(row.enabled) ~= "boolean" or type(row.visible) ~= "boolean"
      or type(row.saved) ~= "number" or type(row.maximum) ~= "number" then
    fail("published armor foreign snapshot is incomplete")
  end
  return {
    level=row.level,
    researched=row.researched,
    enabled=row.enabled,
    visible=row.visible,
    saved=row.saved,
    maximum=row.maximum,
  }
end

local function actual_row(state)
  local force = game.forces[state.foreign_index]
  if force == nil or force.valid == false then fail("published foreign force is absent") end
  local technology = force.technologies[PRIMARY]
  if technology == nil or technology.valid == false or technology.prototype == nil then
    fail("published foreign armor technology is absent")
  end
  if type(technology.level) ~= "number" or type(technology.researched) ~= "boolean"
      or type(technology.enabled) ~= "boolean" or type(technology.visible_when_disabled) ~= "boolean"
      or type(technology.saved_progress) ~= "number" or type(technology.prototype.max_level) ~= "number" then
    fail("published foreign armor technology state is incomplete")
  end
  return {
    level=technology.level,
    researched=technology.researched,
    enabled=technology.enabled,
    visible=technology.visible_when_disabled,
    saved=technology.saved_progress,
    maximum=technology.prototype.max_level,
  }
end

local state = storage[KEY]
if type(state) ~= "table" or type(state.foreign_index) ~= "number" or type(state.profile) ~= "string" then
  fail("requires the published integration source save")
end

-- The retained Py profiles have no armor-components primary.  Do not broaden
-- this diagnostic into a catalogue selector or touch their force tables.
if state.profile ~= "armor-bobwarfare" then
  log("[MIR5_INTEGRATION_PRECONFIG_FOREIGN] " .. helpers.table_to_json({
    fixture_migration="0.2.0",
    profile=state.profile,
    status="not-applicable",
    reason="foreign-armor-probe",
  }))
  return
end

-- Factorio applies this migration before it dispatches control-stage
-- configuration callbacks.  Do not turn this observer into an assertion:
-- recording both rows is the evidence for whether that engine boundary has
-- already changed the externally owned force flag.
log("[MIR5_INTEGRATION_PRECONFIG_FOREIGN] " .. helpers.table_to_json({
  fixture_migration="0.2.0",
  technology=PRIMARY,
  force=state.foreign_index,
  expected=expected_row(state),
  actual=actual_row(state),
}))
