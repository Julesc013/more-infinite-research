-- Only the authored electric/tesla stream has a mixed native-owner boundary.
-- Native holders carry paid counts; no aggregate gun modifier is read or set.
local definitions = require("research.native_gun_credit_definitions")
local target = require("platform.target")
local M = {}
local MAIN, ROWS = definitions.main_id, definitions.descriptors()
local KEY, MAX, MIR = "mir_native_gun_credits", 4294967295, "more-infinite-research"
local pending_active = false

local function refuse(message)
  error("MIR native gun credit: " .. message, 3)
end

local function integer(value)
  return type(value) == "number" and value >= 0 and value < MAX and value == math.floor(value)
end

local function count(technology)
  if not technology or technology.valid == false or type(technology.researched) ~= "boolean"
      or not integer(technology.level - 1) then refuse("invalid native level") end
  local value = technology.level - 1 + (technology.researched and 1 or 0)
  if not integer(value) then refuse("native count exceeds holder range") end
  return value
end

local function valid_force(force)
  return force and force.valid ~= false and integer(force.index) and force.index > 0
end

local function mask(value)
  if type(value) ~= "table" or type(value.electric) ~= "boolean" or type(value.tesla) ~= "boolean" then
    refuse("invalid saved category mask")
  end
end

local function validate_record(record)
  if type(record) ~= "table" or not integer(record.pending) or not integer(record.completed)
      or type(record.positive) ~= "table" or type(record.negative) ~= "table" then refuse("invalid saved counts") end
  mask(record.included); mask(record.payable)
  for _, row in ipairs(ROWS) do
    if not integer(record.positive[row.category]) or not integer(record.negative[row.category]) then
      refuse("invalid saved holder counts")
    end
  end
end

local function state()
  local value = storage and storage[KEY]
  if value ~= nil then
    if type(value) ~= "table" or value.schema ~= 1 or type(value.forces) ~= "table" then
      refuse("unsupported saved schema")
    end
    -- Even an inactive force bucket can affect subscription reconstruction.
    -- Validate the entire finite saved force ledger before any holder writes.
    for index, record in pairs(value.forces) do
      if not integer(index) or index < 1 then refuse("invalid saved force index") end
      validate_record(record)
    end
  end
  return value
end

local function record_for(force)
  local value = state()
  return value and value.forces[force.index]
end

local function refresh_pending()
  local value, found = state(), false
  for _, record in pairs(value and value.forces or {}) do
    if type(record) ~= "table" or not integer(record.pending) then refuse("invalid pending work") end
    if record.pending > 0 then found = true end
  end
  local changed = found ~= pending_active
  pending_active = found
  return changed
end

local function owned(technology, name)
  local prototype = technology and technology.prototype
  if not technology or technology.valid == false or technology.name ~= name or not prototype
      or prototype.name ~= name or prototype.level ~= 1 or prototype.max_level ~= MAX
      or prototype.upgrade ~= true then refuse("non-current named technology " .. name) end
  if not prototypes or type(prototypes.get_history) ~= "function" then refuse("creation history unavailable") end
  local history = prototypes.get_history("technology", name)
  if type(history) ~= "table" or history.created ~= MIR then refuse("foreign creation of " .. name) end
  return prototype
end

local function observe(force)
  if not valid_force(force) then refuse("invalid force") end
  local technologies = force.technologies
  if not technologies then refuse("missing force technologies") end
  local main = technologies[MAIN]
  local present = 0
  for _, row in ipairs(ROWS) do
    if technologies[row.positive_id] then present = present + 1 end
    if technologies[row.negative_id] then present = present + 1 end
  end
  -- Inactive/earlier targets and Space Age-free profiles have no such holders.
  if present == 0 then return nil end
  if present ~= 4 then refuse("incomplete authored holder set") end
  local prototype = owned(main, MAIN)
  if prototype.hidden == true or type(prototype.enabled) ~= "boolean"
      or type(main.enabled) ~= "boolean" then refuse("invalid public technology") end
  local included, scalars = {electric=false, tesla=false}, {}
  for _, effect in ipairs(prototype.effects or {}) do
    local category = effect.ammo_category
    if effect.type ~= "gun-speed" or included[category] == nil or included[category] then
      refuse("invalid public effect vector")
    end
    included[category], scalars[category] = true, effect.modifier
  end
  local science = main.research_unit_ingredients and main.research_unit_ingredients[1]
  if type(science) ~= "table" or type(science.name) ~= "string" then refuse("missing public science") end
  local observation = {force=force, main=main, completed=count(main), included=included,
    private=not included.electric and not included.tesla, positive={}, negative={}}
  for _, row in ipairs(ROWS) do
    local category, scalar = row.category
    for _, direction in ipairs({"positive", "negative"}) do
      local name = row[direction .. "_id"]
      local holder = technologies[name]
      local shape = owned(holder, name)
      local effects, ingredients = shape.effects, holder.research_unit_ingredients
      if shape.hidden ~= true or shape.enabled ~= false or shape.visible_when_disabled ~= false
          or type(holder.enabled) ~= "boolean" or type(holder.visible_when_disabled) ~= "boolean"
          or holder.research_unit_count ~= 1 or holder.research_unit_energy ~= 60
          or type(ingredients) ~= "table" or #ingredients ~= 1
          or ingredients[1].name ~= science.name or ingredients[1].amount ~= 1
          or type(effects) ~= "table" or #effects ~= 1
          or effects[1].type ~= "gun-speed" or effects[1].ammo_category ~= category then
        refuse("invalid holder shape " .. name)
      end
      local modifier = effects[1].modifier
      if direction == "positive" then
        if type(modifier) ~= "number" or modifier ~= modifier or modifier < 0 or modifier >= math.huge then
          refuse("invalid authored scalar")
        end
        scalar = modifier
        if included[category] and scalars[category] ~= scalar then refuse("public/holder scalar mismatch") end
      elseif modifier ~= (included[category] and -scalar or 0) then refuse("invalid conditional negative effect") end
      observation[direction][category] = count(holder)
    end
  end
  return observation
end

local function queued(force)
  local value, current_seen = 0, false
  for _, technology in ipairs(force.research_queue or {}) do
    if technology.name == MAIN then value = value + 1 end
    if technology == force.current_research then current_seen = true end
  end
  if force.current_research and force.current_research.name == MAIN and not current_seen then value = value + 1 end
  if not integer(value) then refuse("invalid native queue length") end
  return value
end

local function published_pair(event)
  if type(event) ~= "table" or event.mod_startup_settings_changed ~= false then return false end
  local changes, active = event.mod_changes, script and script.active_mods or {}
  local change = type(changes) == "table" and changes[MIR]
  if type(change) ~= "table" or change.new_version ~= active[MIR]
      or active[MIR] ~= target.distribution_version then return false end
  local old, engine = change.old_version, active.base
  local known = type(engine) == "string" and (
    target.id == "f200" and engine:match("^2%.0%.%d+$") and type(old) == "string" and old:match("^5%.0%.2000[0-3]$")
    or target.id == "f210" and engine:match("^2%.1%.%d+$") and type(old) == "string" and old:match("^5%.0%.2100[0-3]$"))
  if not known or active["space-age"] == nil then return false end
  for name, item in pairs(changes) do
    if name ~= MIR and (type(item) ~= "table" or item.old_version ~= item.new_version) then return false end
  end
  return true
end

local function plan_force(force, event, fresh)
  local observation = observe(force)
  if observation == nil then return nil end
  local prior = not fresh and record_for(force) or nil
  local previous, payable, pending = prior and prior.included, prior and prior.payable, 0
  local work = queued(force)
  if prior then
    for _, row in ipairs(ROWS) do
      local category = row.category
      if prior.positive[category] ~= observation.positive[category]
          or prior.negative[category] ~= observation.negative[category] then refuse("saved/native holder mismatch") end
    end
    if not previous.electric and not previous.tesla and prior.pending > 0
        and prior.completed ~= observation.completed then refuse("unfinished work missed its native event") end
    pending = math.min(prior.pending, work)
  else
    for _, row in ipairs(ROWS) do
      if observation.positive[row.category] ~= 0 or observation.negative[row.category] ~= 0 then
        refuse("unproven first holder counts")
      end
    end
    local invested = observation.completed > 0 or work > 0 or (observation.main.saved_progress or 0) > 0
    if fresh or not invested then previous = observation.included
    elseif published_pair(event) then previous = {electric=true, tesla=true}
    elseif observation.included.electric and observation.included.tesla then
      -- An unchanged full public vector needs no reconstruction or credit.
      -- This observes current rights; it is no proof of an older hidden mask.
      previous = observation.included
    else refuse("unknown first paid mask; restore the original save and unchanged inputs") end
    payable = previous
  end
  if observation.private then
    if not prior or previous.electric or previous.tesla then pending, payable = work, previous end
  else pending, payable = 0, observation.included end
  if pending == 0 then payable = observation.included end
  local next_record = {included=observation.included, completed=observation.completed,
    pending=pending, payable=payable, positive={}, negative={}}
  for _, row in ipairs(ROWS) do
    local category = row.category
    local earned = (previous[category] and observation.completed or 0)
      + observation.positive[category] - (previous[category] and observation.negative[category] or 0)
    if not integer(earned) then refuse("invalid earned category count") end
    local positive = observation.included[category] and 0 or earned
    local negative = observation.included[category] and observation.completed - earned or 0
    if not integer(positive) or not integer(negative) then refuse("unrepresentable native credit") end
    next_record.positive[category], next_record.negative[category] = positive, negative
  end
  return {observation=observation, record=next_record}
end

function M.preflight(event, fresh, selected_force)
  local plans = {}
  state()
  if not game or not game.forces then refuse("force collection unavailable") end
  for _, force in pairs(selected_force and {selected_force} or game.forces) do
    if valid_force(force) then
      local plan = plan_force(force, event, fresh)
      if plan then plans[#plans + 1] = plan end
    end
  end
  table.sort(plans, function(left, right) return left.observation.force.index < right.observation.force.index end)
  return plans
end

local function suppress(observation)
  for _, row in ipairs(ROWS) do
    for _, direction in ipairs({"positive", "negative"}) do
      local holder = observation.force.technologies[row[direction .. "_id"]]
      holder.enabled, holder.visible_when_disabled = false, false
    end
  end
  -- The existing lifecycle owner alone disables/restores public research,
  -- including its saved proof distinguishing MIR from foreign disablement.
end

local function apply_counts(observation, record)
  -- Remove positive credit before enabling an offset on a restored public
  -- category; disable offsets before adding positive retired credit. No
  -- intermediate assignment needs an aggregate read/repair or negative total.
  for _, direction in ipairs({"negative", "positive"}) do
    for _, row in ipairs(ROWS) do
      local category, holder = row.category, observation.force.technologies[row[direction .. "_id"]]
      if record[direction][category] < observation[direction][category] then holder.level = record[direction][category] + 1 end
    end
  end
  for _, direction in ipairs({"positive", "negative"}) do
    for _, row in ipairs(ROWS) do
      local category, holder = row.category, observation.force.technologies[row[direction .. "_id"]]
      if record[direction][category] > observation[direction][category] then holder.level = record[direction][category] + 1 end
    end
  end
  suppress(observation)
end

function M.apply(plans)
  -- Recheck every force before the first write, including plans prepared
  -- before other configuration reconcilers.
  for _, plan in ipairs(plans) do
    local old, current = plan.observation, observe(plan.observation.force)
    if current == nil or old.completed ~= current.completed then refuse("stale native plan") end
    for _, row in ipairs(ROWS) do
      local category = row.category
      if old.included[category] ~= current.included[category]
          or old.positive[category] ~= current.positive[category]
          or old.negative[category] ~= current.negative[category] then refuse("stale native holders") end
    end
  end
  if #plans == 0 then return refresh_pending() end
  local value = state() or {schema=1, forces={}}
  storage[KEY] = value
  for _, plan in ipairs(plans) do
    apply_counts(plan.observation, plan.record)
    value.forces[plan.observation.force.index] = plan.record
  end
  return refresh_pending()
end

function M.on_init() M.apply(M.preflight(nil, true)) end
function M.on_configuration_changed(event, plans) M.apply(plans or M.preflight(event)) end
function M.on_load() refresh_pending() end
function M.needs_research_events() return pending_active end

function M.on_research_finished(event)
  local research = event and event.research
  if not pending_active or not research or research.valid == false or research.name ~= MAIN then return false end
  local observation, record = observe(research.force), record_for(research.force)
  if not observation or not record or record.pending == 0 then return false end
  if not observation.private or observation.completed ~= record.completed + 1 then refuse("unexpected unfinished completion") end
  for _, row in ipairs(ROWS) do
    local category = row.category
    if observation.positive[category] ~= record.positive[category]
        or observation.negative[category] ~= record.negative[category] then refuse("changed unfinished holders") end
    local wanted = record.positive[category] + (record.payable[category] and 1 or 0)
    if not integer(wanted) then refuse("unfinished credit exceeds native range") end
  end
  for _, row in ipairs(ROWS) do
    local category = row.category
    record.positive[category] = record.positive[category] + (record.payable[category] and 1 or 0)
  end
  apply_counts(observation, record)
  record.completed, record.pending = observation.completed, record.pending - 1
  if record.pending == 0 then record.payable = record.included end
  return refresh_pending()
end

function M.on_research_cancelled(event)
  if not pending_active or not event or not valid_force(event.force) or type(event.research) ~= "table" then return false end
  local cancelled = event.research[MAIN]
  if cancelled == nil then return false end
  if not integer(cancelled) then refuse("invalid cancellation count") end
  local record = record_for(event.force)
  if record then
    record.pending = math.max(0, record.pending - cancelled)
    if record.pending == 0 then record.payable = record.included end
  end
  return refresh_pending()
end

function M.on_force_created(event)
  if not event or not valid_force(event.force) then return end
  local plans = M.preflight(nil, true, event.force)
  local value = state()
  if value then value.forces[event.force.index] = nil end
  M.apply(plans)
end
M.on_force_reset = M.on_force_created

function M.on_forces_merged(event)
  if not event or not valid_force(event.destination) then return end
  local plans = M.preflight(nil, false, event.destination)
  local value = state()
  if value then value.forces[event.source_index] = nil end
  M.apply(plans)
end

function M.on_technology_effects_reset(event)
  if not event or not valid_force(event.force) then return end
  local observation = observe(event.force)
  if observation then suppress(observation) end
end

return M
