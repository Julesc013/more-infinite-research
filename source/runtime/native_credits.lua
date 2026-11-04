-- Bounded reconciliation for the explicit native-credit carrier pairs.
--
-- The five-family and descriptor declarations own the rows this module reads or
-- writes.  It intentionally does not inspect recipe bonuses, reset technology
-- effects. Native levels carry signed credit. Only previously queued private
-- manufacturing work needs a temporary completion/cancellation subscription.
local definitions = require("research.native_credit_definitions")
local catalogue = require("runtime.catalogue")

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
  ["4.7.20003"] = true,
}
local groups = type(catalogue.native_credit_groups) == "function" and catalogue.native_credit_groups() or nil
local DESCRIPTORS = definitions.descriptors(groups)
local COLLECTED_BY_KEY, COLLECTED_BY_MAIN, history_seen = {}, {}, {}
local FAMILY_IDS = {
  research_low_density_structure="recipe-prod-research_low_density_structure-1",
  research_plastic="recipe-prod-research_plastic-1", research_processing_unit="recipe-prod-research_processing_unit-1",
  research_rocket_fuel="recipe-prod-research_rocket_fuel-1", research_steel="recipe-prod-research_steel-1",
}
local function require_creation_history(name)
  if history_seen[name] then return end
  if not prototypes or type(prototypes.get_history) ~= "function" then
    error("MIR native family credit requires prototype creation history", 2)
  end
  local history = prototypes.get_history("technology", name)
  if type(history) ~= "table" or history.created ~= MIR_MOD then
    error("MIR native family credit requires MIR creation custody for " .. name, 2)
  end
  history_seen[name] = true
end
for family in pairs(groups or {}) do
  local name = FAMILY_IDS[family]
  COLLECTED_BY_MAIN[name] = {}
  require_creation_history(name)
end
for _, row in ipairs(DESCRIPTORS) do
  if row.collected then
    COLLECTED_BY_KEY[row.key] = row
    COLLECTED_BY_MAIN[row.main_id] = COLLECTED_BY_MAIN[row.main_id] or {}
    COLLECTED_BY_MAIN[row.main_id][#COLLECTED_BY_MAIN[row.main_id] + 1] = row
    for _, name in ipairs({row.main_id, row.positive_id, row.negative_id}) do
      require_creation_history(name)
    end
  end
end
local SIF_RECIPES = next(COLLECTED_BY_MAIN) ~= nil
  and definitions.published_sif_paid_recipe_sets() or nil
-- The exact published MIR4 Base origins below share this five-recipe vector
-- with the published Base betas (independent modern-f200/f210-470 captures).
local PUBLISHED_BASE_RECIPES = next(COLLECTED_BY_MAIN) ~= nil
  and require("research.native_credit_contracts").published_beta_base_paid_recipe_sets() or nil
local pending_active = false

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
    if recipe:find("\0", 1, true) then
      local family, name = recipe:match("^(.-)%z(.+)$")
      if FAMILY_IDS[family] == nil or not name or name:find("\0", 1, true)
          or type(record.private) ~= "boolean" or type(record.payable) ~= "boolean"
          or not integer(record.pending) or record.pending < 0
          or not integer(record.completed) or record.completed < 0 then
        error("MIR unsupported native family credit record", 3)
      end
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
  if type(current.families) == "table" then current.families[index] = nil end
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

local function inspect_with_mask(force, descriptor, scope)
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
  if descriptor.collected and not close(positive_scalar, descriptor.change) then return nil end
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
  local effect, effects_valid
  if scope then
    effect = scope.values[descriptor.recipe]
    effects_valid = scope.valid and effect ~= false
  else effect, effects_valid = named_main_effect(prototype, descriptor.recipe) end
  if not effects_valid or (effect ~= nil and not close(effect, positive_scalar)) then return nil end
  return {
    descriptor = descriptor,
    included = effect ~= nil,
    completed = main_completed,
    offset = positive_completed - negative_completed,
    positive = positive,
    negative = negative,
    private = prototype.hidden == true,
  }
end

local function family_observations(force)
  local out, scopes = {}, {}
  for _, descriptor in ipairs(DESCRIPTORS) do
    if descriptor.collected then
      local scope = scopes[descriptor.main_id]
      if scope == nil then
        local main = force.technologies[descriptor.main_id]
        local effects = main and main.prototype and main.prototype.effects
        scope = {valid=type(effects) == "table", values={}}
        for _, effect in ipairs(scope.valid and effects or {}) do
          if type(effect) == "table" and type(effect.recipe) == "string" then
            if scope.values[effect.recipe] ~= nil or effect.type ~= PRODUCTIVITY_EFFECT
                or type(effect.change) ~= "number" or effect.change ~= effect.change
                or effect.change == math.huge or effect.change == -math.huge then
              scope.values[effect.recipe] = false
            else scope.values[effect.recipe] = effect.change end
          end
        end
        scopes[descriptor.main_id] = scope
      end
      local observation = inspect_with_mask(force, descriptor, scope)
      if observation == nil then error("MIR native family credit has invalid main or carrier: " .. descriptor.key, 3) end
      out[#out + 1] = observation
    end
  end
  return out
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
    local observation = not DESCRIPTORS[index].collected and inspect_with_mask(force, DESCRIPTORS[index])
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

local function family_failure(message)
  error("MIR native family credit: " .. message, 3)
end

local function queued_counts(force)
  local counts = {}
  for _, technology in ipairs(force.research_queue or {}) do
    local name = technology.name
    if COLLECTED_BY_MAIN[name] ~= nil then counts[name] = (counts[name] or 0) + 1 end
  end
  local current = force.current_research
  if current and COLLECTED_BY_MAIN[current.name] ~= nil and counts[current.name] == nil then counts[current.name] = 1 end
  return counts
end

local function family_histories(current, index)
  local all = current and current.families
  if all == nil then return {} end
  if type(all) ~= "table" then family_failure("invalid saved family histories") end
  local histories = all[index]
  if histories == nil then return {} end
  if type(histories) ~= "table" then family_failure("invalid saved force histories") end
  for family, history in pairs(histories) do
    if FAMILY_IDS[family] == nil or type(history) ~= "table" or history.schema ~= 1
        or type(history.recipes) ~= "table" then family_failure("invalid complete family history") end
    for key in pairs(history) do
      if key ~= "schema" and key ~= "recipes" then family_failure("unknown family history field") end
    end
    for recipe, present in pairs(history.recipes) do
      if type(recipe) ~= "string" or recipe == "" or recipe:find("\0", 1, true) or present ~= true then
        family_failure("invalid history recipe")
      end
    end
  end
  return histories
end

local function legacy_family_context(event)
  local changes = type(event) == "table" and event.mod_changes
  local mir = type(changes) == "table" and changes[MIR_MOD]
  local active = script and script.active_mods or {}
  local valid = type(mir) == "table" and type(mir.old_version) == "string"
    and type(mir.new_version) == "string" and mir.new_version == active[MIR_MOD]
  local old = valid and mir.old_version or nil
  local sif_change = type(changes) == "table" and changes["space-is-fake"]
  local previous_sif = type(sif_change) == "table" and sif_change.old_version == "1.0.60"
    or sif_change == nil and active["space-is-fake"] == "1.0.60"
  local same_inputs = valid and event.mod_startup_settings_changed == false
  if same_inputs then
    for name, change in pairs(changes) do
      if name ~= MIR_MOD and type(change) == "table" and change.old_version ~= change.new_version then same_inputs = false end
    end
  end
  local unchanged = same_inputs
    and (old == "4.7.20002" or old == "4.7.20003" or old == "4.7.21002" or old == "4.7.21003")
  local plain_base = true
  for name in pairs(active) do if name ~= "base" and name ~= MIR_MOD then plain_base = false end end
  local f210_destination = type(active[MIR_MOD]) == "string" and active[MIR_MOD]:match("^5%.0%.210%d%d$") ~= nil
  local m4_base = false
  if plain_base and (old == "4.7.20003" or old == "4.7.21003") then
    -- These published Base origins have a known five-recipe paid mask, not
    -- today's collected output. The protected hop is exactly 2.0.77->2.1.23;
    -- another engine patch needs its own route review, not an open-ended >=.
    local base_change = changes.base
    local exact_hop = old == "4.7.20003" and type(base_change) == "table"
      and base_change.old_version == "2.0.77" and base_change.new_version == "2.1.23"
    local same_engine = old == "4.7.21003" and same_inputs and (base_change == nil
      or type(base_change) == "table" and base_change.old_version == "2.1.23" and base_change.new_version == "2.1.23")
    m4_base = valid and f210_destination and active.base == "2.1.23"
      and event.mod_startup_settings_changed == false
      and (same_engine or exact_hop)
    for name in pairs(changes) do
      if name ~= MIR_MOD and name ~= "base" then m4_base = false end
    end
    -- A missing hop event or unreviewed F210 engine must not fall through to
    -- the generic unchanged-input reader and fabricate an old Base mask.
    if f210_destination or type(active.base) == "string" and active.base:match("^2%.1%.") then unchanged = false end
  end
  -- Only the reviewed plain Base closure is admitted here. Other profiles,
  -- provider changes and startup changes still require their own old mask.
  local beta_base = same_inputs and type(active.base) == "string" and (
    active.base:match("^2%.0%.%d+$") and (old == "5.0.20000" or old == "5.0.20001" or old == "5.0.20002")
    or active.base:match("^2%.1%.%d+$") and (old == "5.0.21000" or old == "5.0.21001" or old == "5.0.21002"))
  if beta_base then
    for name in pairs(active) do if name ~= "base" and name ~= MIR_MOD then beta_base = false end end
  end
  return {unchanged=unchanged, beta_base=beta_base, m4_base=m4_base, sif502=old == "5.0.20002" and previous_sif,
    sif473=unchanged and previous_sif and (old == "4.7.20002" or old == "4.7.20003")}
end

local function refresh_pending()
  local needed = false
  local current = storage and storage[STORAGE_KEY]
  if type(current) == "table" and current.schema == SCHEMA and type(current.forces) == "table" then
    for _, records in pairs(current.forces) do
      if type(records) == "table" then
        for key in pairs(COLLECTED_BY_KEY) do
          local record = records[key]
          if type(record) == "table" and record.private == true and type(record.pending) == "number"
              and record.pending > 0 and record.payable ~= record.included then needed = true end
        end
      end
    end
  end
  local changed = pending_active ~= needed
  pending_active = needed
  return changed
end

function M.needs_research_events() return pending_active end

-- Preflight every affected force before any core or family level/state write.
-- A complete previous recipe set proves a new recipe was not previously paid;
-- an isolated schema-shaped record is not that proof.
function M.preflight_family_transition(event, fresh, selected_force)
  local current = existing_state()
  if next(COLLECTED_BY_MAIN) == nil and (groups == nil or next(groups) == nil)
      and (not current or current.families == nil) then return {} end
  local context, plans = legacy_family_context(event), {}
  local forces = selected_force and {[selected_force.index]=selected_force} or game and game.forces or {}
  for _, force in pairs(forces) do
    if valid_force(force) then
      local records = not fresh and current and current.forces[force.index] or {}
      validate_records(records)
      local histories = family_histories(not fresh and current or nil, force.index)
      local queued = queued_counts(force)
      for family, recipes in pairs(groups or {}) do
        if #recipes == 0 then
          local id = FAMILY_IDS[family]
          local main = force.technologies and force.technologies[id]
          local prototype = main and main.prototype
          local completed = completed_infinite(main)
          if main == nil or main.name ~= id or prototype == nil or prototype.name ~= id
              or prototype.level ~= 1 or prototype.max_level ~= UINT32_MAX or completed == nil then
            family_failure("empty family has an absent or invalid named main")
          end
          if not fresh and histories[family] == nil and (completed > 0 or (queued[id] or 0) > 0
              or type(main.saved_progress) == "number" and main.saved_progress > 0) then
            family_failure("empty first family has unproven paid or invested work; restore previous inputs and original save")
          end
        end
      end
      local plan = {force=force, rows={}, retire={}, histories={}}
      for family in pairs(groups or {}) do plan.histories[family] = {schema=1, recipes={}} end
      for family, history in pairs(histories) do
        plan.histories[family] = {schema=1, recipes={}}
        for recipe in pairs(history.recipes) do
          local key = family .. "\0" .. recipe
          local record = records and records[key]
          if type(record) ~= "table" then family_failure("incomplete previous paid mask") end
          if COLLECTED_BY_KEY[key] == nil then
            local main = force.technologies[FAMILY_IDS[family]]
            local completed = completed_infinite(main)
            if completed == nil or record.offset ~= 0 or record.included and completed > 0
                or record.pending > 0 or type(main.saved_progress) == "number" and main.saved_progress > 0 then
              family_failure("a paid recipe or invested identity disappeared; restore previous inputs and original save")
            end
            plan.retire[#plan.retire + 1] = key
          end
        end
      end
      for key in pairs(records or {}) do
        local family, recipe = key:match("^(.-)%z(.+)$")
        if family and (histories[family] == nil or histories[family].recipes[recipe] ~= true) then
          family_failure("record has no complete previous family history")
        end
      end
      local observations = family_observations(force)
      local complete_sif_checked, complete_base_checked = false, false
      for _, observation in ipairs(observations) do
        local descriptor = observation.descriptor
        local key, family = descriptor.key, descriptor.family
        local record, history = records and records[key], histories[family]
        local prior_included, payable, pending
        if record then
          if record.offset ~= observation.offset then family_failure("saved offset differs from its native carriers") end
          if record.private and record.pending > 0 and record.payable ~= record.included
              and record.completed ~= observation.completed then family_failure("unfinished work changed without its native event") end
          if observation.completed < record.completed then family_failure("completed private work moved backwards") end
          prior_included = record.included
          payable = record.included
          if record.private and record.pending > 0 then payable = record.payable end
          pending = record.private and math.min(record.pending, queued[descriptor.main_id] or 0)
            or (queued[descriptor.main_id] or 0)
        elseif history then
          if history.recipes[descriptor.recipe] then family_failure("missing record in complete previous mask") end
          if observation.offset ~= 0 then family_failure("new recipe has unproven native credit") end
          prior_included, payable, pending = false, false, 0
        else
          if not fresh and observation.offset ~= 0 then family_failure("first baseline has unproven native credit") end
          local main = force.technologies[descriptor.main_id]
          local invested_private = observation.private and ((queued[descriptor.main_id] or 0) > 0
            or type(main.saved_progress) == "number" and main.saved_progress > 0)
          -- Zero earned levels do not prove the absence of original queued or
          -- detached work. Known source contracts must resolve that old mask;
          -- an unknown first investment cannot baseline from the new output.
          if fresh or observation.completed == 0 and not invested_private then prior_included = observation.included
          elseif context.sif502 or context.sif473 and observation.private then
            if not complete_sif_checked then
              for old_family, recipes in pairs(SIF_RECIPES) do
                if force.technologies[FAMILY_IDS[old_family]] == nil then family_failure("missing published SIF paid identity") end
                for recipe in pairs(recipes) do
                  if COLLECTED_BY_KEY[old_family .. "\0" .. recipe] == nil then family_failure("missing published SIF credit route") end
                end
              end
              complete_sif_checked = true
            end
            prior_included = SIF_RECIPES[family][descriptor.recipe] == true
          elseif (context.beta_base or context.m4_base) and not observation.private then
            if not complete_base_checked then
              for old_family, recipes in pairs(PUBLISHED_BASE_RECIPES) do
                if force.technologies[FAMILY_IDS[old_family]] == nil then family_failure("missing published Base paid identity") end
                for recipe in pairs(recipes) do
                  if COLLECTED_BY_KEY[old_family .. "\0" .. recipe] == nil then family_failure("missing published Base credit route") end
                end
              end
              complete_base_checked = true
            end
            prior_included = PUBLISHED_BASE_RECIPES[family][descriptor.recipe] == true
          elseif context.unchanged and not observation.private then prior_included = observation.included
          else family_failure("unknown first paid mask; upgrade once with original mods/startup unchanged and save before changing ownership") end
          payable, pending = prior_included, queued[descriptor.main_id] or 0
        end
        local offset = observation.offset + ((prior_included and 1 or 0) - (observation.included and 1 or 0)) * observation.completed
        if not integer(offset) or math.abs(offset) >= UINT32_MAX then family_failure("credit exceeds native level range") end
        if not observation.private then pending, payable = 0, observation.included end
        if pending == 0 then payable = observation.included end
        plan.rows[#plan.rows + 1] = {observation=observation, record={included=observation.included,
          offset=offset, private=observation.private, payable=payable, pending=pending, completed=observation.completed}}
        plan.histories[family] = plan.histories[family] or {schema=1, recipes={}}
        plan.histories[family].recipes[descriptor.recipe] = true
      end
      plans[#plans + 1] = plan
    end
  end
  return plans
end

local function apply_family_plans(plans)
  if #plans == 0 then return end
  local current = ensure_state()
  current.families = current.families or {}
  for _, plan in ipairs(plans) do
    local old = current.forces[plan.force.index] or {}
    local records = {}
    for key, record in pairs(old) do records[key] = record end
    for _, key in ipairs(plan.retire) do records[key] = nil end
    for _, row in ipairs(plan.rows) do
      if row.record.offset ~= row.observation.offset then apply_offset(row.observation, row.record.offset) end
      records[row.observation.descriptor.key] = row.record
    end
    current.forces[plan.force.index], current.families[plan.force.index] = records, plan.histories
  end
  refresh_pending()
end

function M.on_research_finished(event)
  local research = event and event.research
  local selected = research and COLLECTED_BY_MAIN[research.name]
  local force = research and research.force
  if not pending_active or selected == nil or not valid_force(force) then return false end
  local records = records_for(force, false)
  validate_records(records)
  local plans = {}
  for _, observation in ipairs(family_observations(force)) do
    local descriptor = observation.descriptor
    if descriptor.main_id == research.name then
      local record = records and records[descriptor.key]
      if record and record.private and record.pending > 0 then
        if record.offset ~= observation.offset then family_failure("unfinished carrier state was changed") end
        local delta = observation.completed - record.completed
        if delta < 0 or delta > 1 then family_failure("unfinished native completion differs from one level") end
        if delta == 1 then
          local offset = record.offset + (record.payable and 1 or 0) - (observation.included and 1 or 0)
          if not integer(offset) or math.abs(offset) >= UINT32_MAX then family_failure("unfinished credit exceeds native levels") end
          plans[#plans + 1] = {observation=observation, record=record, offset=offset}
        end
      end
    end
  end
  for _, plan in ipairs(plans) do
    if plan.offset ~= plan.observation.offset then apply_offset(plan.observation, plan.offset) end
    local record = plan.record
    record.offset, record.completed, record.pending = plan.offset, plan.observation.completed, record.pending - 1
    if record.pending == 0 then record.payable = record.included end
  end
  return refresh_pending()
end

function M.on_research_cancelled(event)
  local force, cancelled = event and event.force, event and event.research
  if not pending_active or not valid_force(force) or type(cancelled) ~= "table" then return false end
  local records = records_for(force, false)
  validate_records(records)
  local plans = {}
  for name, count in pairs(cancelled) do
    if COLLECTED_BY_MAIN[name] then
      if not integer(count) or count < 0 then family_failure("invalid native cancellation count") end
      for _, descriptor in ipairs(COLLECTED_BY_MAIN[name]) do
        local record = records and records[descriptor.key]
        if record then
          plans[#plans + 1] = {record=record, pending=math.max(0, record.pending - count)}
        end
      end
    end
  end
  for _, plan in ipairs(plans) do
    plan.record.pending = plan.pending
    if plan.pending == 0 then plan.record.payable = plan.record.included end
  end
  return refresh_pending()
end

-- A technology-effects reset does not need to recalculate migration credit.
-- It may re-enable native hidden carriers, so inspect exact owned shapes and
-- restore only the carrier flags.  No level, force effect, or ledger changes.
local function disable_exact_carriers(force)
  if not valid_force(force) then return end
  local observations = family_observations(force)
  for index = 1, #DESCRIPTORS do
    local observation = not DESCRIPTORS[index].collected and inspect_with_mask(force, DESCRIPTORS[index])
    if observation then observations[#observations + 1] = observation end
  end
  for _, observation in ipairs(observations) do
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
    and type(change.new_version) == "string" and change.new_version ~= ""
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
        local observation = not DESCRIPTORS[index].collected and inspect_with_mask(force, DESCRIPTORS[index])
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
  local plans = M.preflight_family_transition(nil, true)
  reconcile_all()
  apply_family_plans(plans)
end

function M.on_configuration_changed(event, plans)
  plans = plans or M.preflight_family_transition(event)
  reconcile_all()
  apply_family_plans(plans)
end

function M.on_force_created(event)
  local force = event and event.force
  if not valid_force(force) then return end
  local plans = M.preflight_family_transition(nil, true, force)
  clear_force(force.index)
  reconcile_force(force)
  apply_family_plans(plans)
  disable_exact_carriers(force)
end

function M.on_force_reset(event)
  local force = event and event.force
  if not valid_force(force) then return end
  local plans = M.preflight_family_transition(nil, true, force)
  clear_force(force.index)
  reconcile_force(force)
  apply_family_plans(plans)
  disable_exact_carriers(force)
end

function M.on_forces_merged(event)
  local destination = event and event.destination
  if not valid_force(destination) then return end
  -- Native merging retains destination research and bonuses, discarding the
  -- source's. Validate its existing family history before either ledger is
  -- cleared; pending private work keeps its original payable decision.
  local plans = M.preflight_family_transition(nil, false, destination)
  clear_force(event and event.source_index)
  clear_force(destination.index)
  reconcile_force(destination)
  apply_family_plans(plans)
  disable_exact_carriers(destination)
end

function M.on_technology_effects_reset(event)
  disable_exact_carriers(event and event.force)
end

-- Parse-time registration owns activation.  This must not touch storage or
-- game during a host reload or client join.
function M.on_load()
  refresh_pending()
end

return M
