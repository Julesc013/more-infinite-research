-- Bounded reconciliation for the explicit native-credit carrier pairs.
--
-- The descriptor list is the sole authority for rows this module reads or
-- writes.  It intentionally does not inspect recipe bonuses, reset technology
-- effects, or subscribe to research/tick events: native technology levels
-- carry the signed migration credit directly.
local definitions = require("research.native_credit_definitions")

local M = {}

local STORAGE_KEY = "mir_native_credits"
local SCHEMA = 1
local UINT32_MAX = 4294967295
local EFFECT_TOLERANCE = .00000001
local PRODUCTIVITY_EFFECT = "change-recipe-productivity"
local MIR_MOD = "more-infinite-research"
local PUBLISHED_F200_M4_VERSIONS = {
  ["4.7.20000"] = true,
  ["4.7.20001"] = true,
  ["4.7.20002"] = true,
}
local DESCRIPTORS = definitions.descriptors()

local function close(left, right)
  return type(left) == "number" and type(right) == "number"
    and math.abs(left - right) <= EFFECT_TOLERANCE
end

local function integer(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

local function valid_force(force)
  return force and force.valid ~= false and integer(force.index)
end

local function existing_state()
  local value = storage[STORAGE_KEY]
  if value == nil then return nil end
  if type(value) ~= "table" or value.schema ~= SCHEMA or type(value.forces) ~= "table" then
    error("MIR unsupported native credit storage", 2)
  end
  return value
end

local function ensure_state()
  local value = existing_state()
  if value then return value end
  value = {schema = SCHEMA, forces = {}}
  storage[STORAGE_KEY] = value
  return value
end

local function validate_records(records)
  if records == nil then return end
  if type(records) ~= "table" then error("MIR unsupported native credit force storage", 3) end
  for recipe, record in pairs(records) do
    if type(recipe) ~= "string" or type(record) ~= "table"
        or type(record.included) ~= "boolean" or not integer(record.offset) then
      error("MIR unsupported native credit record", 3)
    end
  end
end

local function records_for(force, create)
  local current = create and ensure_state() or existing_state()
  if not current then return nil end
  local records = current.forces[force.index]
  validate_records(records)
  if records == nil and create then
    records = {}
    current.forces[force.index] = records
  end
  return records
end

local function clear_force(index)
  if not integer(index) then return end
  local current = existing_state()
  if not current then return end
  current.forces[index] = nil
  if next(current.forces) == nil then storage[STORAGE_KEY] = nil end
end

local function named_main_effect(prototype, recipe)
  local effects = prototype and prototype.effects
  if type(effects) ~= "table" then return nil, false end
  local found = nil
  for index = 1, #effects do
    local effect = effects[index]
    if type(effect) == "table" and effect.recipe == recipe then
      if effect.type ~= PRODUCTIVITY_EFFECT or found ~= nil
          or type(effect.change) ~= "number" then
        return nil, false
      end
      found = effect.change
    end
  end
  return found, true
end

local function carrier_scalar(technology, descriptor, direction)
  local name = direction == "positive" and descriptor.positive_id or descriptor.negative_id
  local prototype = technology and technology.prototype
  local effects = prototype and prototype.effects
  if technology == nil or technology.valid == false or technology.name ~= name
      or prototype == nil or prototype.name ~= name
      or prototype.level ~= 1 or prototype.max_level ~= UINT32_MAX
      or prototype.hidden ~= true or prototype.enabled ~= false
      or prototype.visible_when_disabled ~= false
      or type(effects) ~= "table" or #effects ~= 1 then
    return nil
  end
  local effect = effects[1]
  if type(effect) ~= "table" or effect.type ~= PRODUCTIVITY_EFFECT
      or effect.recipe ~= descriptor.recipe or type(effect.change) ~= "number"
      or effect.change ~= effect.change or effect.change == math.huge
      or effect.change == -math.huge then
    return nil
  end
  return effect.change
end

local function completed_infinite(technology)
  if technology == nil or technology.valid == false or not integer(technology.level)
      or technology.level < 1 or type(technology.researched) ~= "boolean" then
    return nil
  end
  return technology.level - 1 + (technology.researched and 1 or 0)
end

local function inspect_with_mask(force, descriptor)
  local technologies = force and force.technologies
  if technologies == nil then return nil end
  local main = technologies[descriptor.main_id]
  local positive = technologies[descriptor.positive_id]
  local negative = technologies[descriptor.negative_id]
  local positive_scalar = carrier_scalar(positive, descriptor, "positive")
  local negative_scalar = carrier_scalar(negative, descriptor, "negative")
  if type(positive_scalar) ~= "number" or positive_scalar <= 0
      or negative_scalar == nil or not close(negative_scalar, -positive_scalar) then
    return nil
  end
  local positive_completed = completed_infinite(positive)
  local negative_completed = completed_infinite(negative)
  if positive_completed == nil or negative_completed == nil then return nil end
  local prototype = main and main.prototype
  if main == nil or main.valid == false or main.name ~= descriptor.main_id
      or prototype == nil or prototype.name ~= descriptor.main_id
      or prototype.level ~= 1 or prototype.max_level ~= UINT32_MAX then
    return nil
  end
  local main_completed = completed_infinite(main)
  if main_completed == nil then return nil end
  local effect, effects_valid = named_main_effect(prototype, descriptor.recipe)
  if not effects_valid or (effect ~= nil and not close(effect, positive_scalar)) then return nil end
  return {
    descriptor = descriptor,
    included = effect ~= nil,
    completed = main_completed,
    offset = positive_completed - negative_completed,
    positive = positive,
    negative = negative,
  }
end

local function set_level_and_disable(technology, wanted)
  -- A level-one infinite carrier can also report one completed level through
  -- researched=true. Assign its level in that case too, so the native level
  -- setter is the sole materialization operation and clears that completion.
  if technology.level == wanted and technology.researched ~= true then return end
  technology.level = wanted
  -- F200's native setter enables a hidden carrier.  Re-disable only after our
  -- own named-carrier write; this changes neither native units nor effects.
  technology.enabled = false
end

local function apply_offset(observation, offset)
  if not integer(offset) then error("MIR native credit offset is not integral", 3) end
  local positive = offset > 0 and offset or 0
  local negative = offset < 0 and -offset or 0
  set_level_and_disable(observation.positive, 1 + positive)
  set_level_and_disable(observation.negative, 1 + negative)
end

local function reconcile_force(force)
  if not valid_force(force) then return end
  local existing = records_for(force, false)
  -- Validate all stored values before any native write.  It is legitimate for
  -- a force to have no ledger yet: the first successful observation below is
  -- a baseline, not a guessed historic preference.
  validate_records(existing)

  local observations = {}
  for index = 1, #DESCRIPTORS do
    local observation = inspect_with_mask(force, DESCRIPTORS[index])
    if observation then observations[#observations + 1] = observation end
  end
  if #observations == 0 then return end

  local records = existing or records_for(force, true)
  local plans = {}
  for index = 1, #observations do
    local observation = observations[index]
    local record = records[observation.descriptor.recipe]
    if record == nil then
      -- MIR4 did not persist the prior preference.  Current inclusion and
      -- native carrier levels are the only honest first-upgrade baseline.
      records[observation.descriptor.recipe] = {
        included = observation.included,
        offset = observation.offset,
      }
    else
      local old_included = record.included and 1 or 0
      local new_included = observation.included and 1 or 0
      local offset = record.offset + (old_included - new_included) * observation.completed
      if not integer(offset) then error("MIR native credit calculated a non-integral offset", 2) end
      plans[#plans + 1] = {observation = observation, record = record, offset = offset}
    end
  end

  -- Every affected pair was validated before this first technology-level write.
  for index = 1, #plans do
    local plan = plans[index]
    apply_offset(plan.observation, plan.offset)
    plan.record.included, plan.record.offset = plan.observation.included, plan.offset
  end
end

-- A technology-effects reset does not need to recalculate migration credit.
-- It may re-enable native hidden carriers, so inspect exact owned shapes and
-- restore only the carrier flags.  No level, force effect, or ledger changes.
local function disable_exact_carriers(force)
  if not valid_force(force) then return end
  for index = 1, #DESCRIPTORS do
    local observation = inspect_with_mask(force, DESCRIPTORS[index])
    if observation then
      observation.positive.enabled = false
      observation.negative.enabled = false
    end
  end
end

local function reconcile_all()
  -- Factorio exposes this collection as LuaCustomTable userdata, not a plain
  -- Lua table. Its supported pairs iterator is the force lifecycle boundary.
  if not game or not game.forces then return end
  -- This iterates only Factorio's force lifecycle collection.  Technology and
  -- prototype access stays direct and descriptor-named in inspect_with_mask.
  for _, force in pairs(game.forces) do reconcile_force(force) end
end

local function published_m4_startup_change(event)
  if type(event) ~= "table" or event.mod_startup_settings_changed ~= true then return false end
  local changes = event.mod_changes
  local change = type(changes) == "table" and changes[MIR_MOD] or nil
  return type(change) == "table" and PUBLISHED_F200_M4_VERSIONS[change.old_version] == true
    and type(change.new_version) == "string" and change.new_version:match("^5%.") ~= nil
end

local function valid_record_for_observation(records, observation)
  local record = records and records[observation.descriptor.recipe] or nil
  -- A schema-shaped bucket is not proof that this exact force/recipe observed
  -- an earlier MIR5 setting. The recorded carrier delta must still agree with
  -- the direct named native holders before it can establish that baseline.
  return type(record) == "table" and type(record.included) == "boolean"
    and record.included == observation.included and integer(record.offset)
    and record.offset == observation.offset
end

-- Published F200 MIR4.7 recorded no competing-preference history. Factorio reports
-- only that *some* startup setting changed, not the old/new setting values.
-- Block an earned partial overlap at that exact first transition rather than
-- baseline it from the new data-stage preference and fabricate or lose credit.
-- This has no writes: bootstrap calls it before every configuration reconciler.
function M.preflight_legacy_preference_transition(event, competing_provider_relevant)
  if competing_provider_relevant ~= true or not published_m4_startup_change(event)
      or not game or not game.forces then return end
  local current = existing_state()
  for _, force in pairs(game.forces) do
    if valid_force(force) then
      local records = current and current.forces[force.index] or nil
      validate_records(records)
      for index = 1, #DESCRIPTORS do
        local observation = inspect_with_mask(force, DESCRIPTORS[index])
        if observation and observation.completed > 0
            and not valid_record_for_observation(records, observation) then
          error("MIR cannot safely migrate published 4.7 competing productivity while startup settings changed. "
            .. "Upgrade once with startup settings unchanged and save, then change "
            .. "mir-prefer-this-mod-for-competing-techs in a later MIR5 configuration.", 2)
        end
      end
    end
  end
end

function M.on_init()
  reconcile_all()
end

function M.on_configuration_changed()
  reconcile_all()
end

function M.on_force_created(event)
  local force = event and event.force
  if not valid_force(force) then return end
  clear_force(force.index)
  reconcile_force(force)
  disable_exact_carriers(force)
end

function M.on_force_reset(event)
  local force = event and event.force
  if not valid_force(force) then return end
  clear_force(force.index)
  reconcile_force(force)
  disable_exact_carriers(force)
end

function M.on_forces_merged(event)
  clear_force(event and event.source_index)
  local destination = event and event.destination
  if not valid_force(destination) then return end
  clear_force(destination.index)
  reconcile_force(destination)
  disable_exact_carriers(destination)
end

function M.on_technology_effects_reset(event)
  disable_exact_carriers(event and event.force)
end

-- Parse-time registration owns activation.  This must not touch storage or
-- game during a host reload or client join.
function M.on_load()
end

return M
