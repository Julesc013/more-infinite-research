-- Bounded handoff of the two historical JSON-renamed Imersite technologies.
-- Native setters own effects. This module never writes an aggregate bonus or
-- reconstructs researchability, and runs only at named lifecycle boundaries.
local contract = require("research.k2_imersite")
local M = {}
local EARLY, TAIL = contract.early.id, contract.continuation.id
local HOLDERS = {contract.carriers[1].id, contract.carriers[2].id}

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function snapshot(technology)
  return {level=technology.level, researched=technology.researched == true,
    saved_progress=technology.saved_progress or 0, enabled=technology.enabled,
    visible_when_disabled=technology.visible_when_disabled}
end

local function valid_state(state, first)
  return type(state) == "table" and finite(state.level) and state.level >= first
    and state.level == math.floor(state.level) and type(state.researched) == "boolean"
    and finite(state.saved_progress) and state.saved_progress >= 0 and state.saved_progress <= 1
end

local function earned(state, first)
  return state.level - first + (state.researched and 1 or 0)
end

local function same_names(left, right)
  if #left ~= #right then return false end
  for index, name in ipairs(left) do if right[index] ~= name then return false end end
  return true
end

local function queue_names(force)
  local out = {}
  for _, technology in ipairs(force.research_queue or {}) do out[#out+1] = technology.name end
  return out
end

local function current_name(force)
  return force.current_research and force.current_research.name or nil
end

local function active(state, first, queue, current, id)
  if earned(state, first) > 0 or state.saved_progress ~= 0 or current == id then return true end
  for _, name in ipairs(queue) do if name == id then return true end end
  return false
end

local function exact_effect(technology, change)
  local effects = technology and technology.prototype and technology.prototype.effects
  if not effects or #effects ~= 1 then return false end
  local effect = effects[1]
  return effect.type == contract.effect.type and effect.recipe == contract.effect.recipe
    and effect.change == change
end

local function admitted(technologies, change)
  for _, id in ipairs({EARLY, TAIL, HOLDERS[1], HOLDERS[2]}) do
    local technology = technologies[id]
    if not exact_effect(technology, change) then return false, "effect:" .. id end
    local maximum = technology.prototype.max_level
    if id == EARLY then
      if maximum ~= 3 then return false, "finite-early-stage" end
    elseif maximum ~= "infinite" and maximum ~= 4294967295 then return false, "infinite-stage:" .. id end
    if id == HOLDERS[1] or id == HOLDERS[2] then
      if technology.prototype.hidden ~= true or not finite(technology.research_unit_energy)
        or technology.research_unit_energy <= 0 then return false, "carrier-shape:" .. id end
    end
  end
  local prerequisite = false
  for _, technology in pairs(technologies[TAIL].prototype.prerequisites or {}) do
    if technology.name == EARLY then prerequisite = true end
  end
  return prerequisite, "continuation-prerequisite"
end

-- Pure local mapping; all inputs are snapshots or names. Existing public
-- finite completion is explicit evidence for a held tail, not invented credit.
function M.plan(early, tail, public_early, queue, current, progress)
  if not valid_state(early, 1) or not valid_state(tail, 4) or not valid_state(public_early, 1)
    or not finite(progress) or progress < 0 or progress > 1 then
    error("MIR invalid Imersite migration state", 2)
  end
  local early_earned, tail_earned = earned(early,1), earned(tail,4)
  local tail_active = active(tail,4,queue,current,HOLDERS[2])
  if early_earned == 0 and tail_active and public_early.level == 3 and public_early.researched then
    early_earned = 3
  end
  if tail_active and (early_earned < 3 or early_earned > 3) then
    error("MIR inconsistent Imersite staged predecessor", 2)
  end
  local completed = math.min(3, early_earned)
  local early_target = {level=math.min(3,completed+1),researched=completed == 3,
    saved_progress=completed < 3 and early.saved_progress or 0}
  local tail_target = {level=4,researched=false,saved_progress=0}
  if tail_active then
    tail_target = {level=tail.level,researched=tail.researched,saved_progress=tail.saved_progress}
  elseif early_earned > 3 or early.level >= 4 then
    tail_target = {level=early_earned+1,researched=false,saved_progress=early.saved_progress}
  end
  local mapped, next_early, mapped_current = {}, early_earned+1, nil
  for _, name in ipairs(queue) do
    local destination = name
    if name == HOLDERS[1] then
      destination = next_early <= 3 and EARLY or TAIL
      next_early = next_early + 1
    elseif name == HOLDERS[2] then destination = TAIL end
    mapped[#mapped+1] = destination
    if mapped_current == nil and name == current then mapped_current = destination end
  end
  if current ~= nil and mapped_current == nil then
    error("MIR Imersite current research is absent from its queue", 2)
  end
  return {early=early_target,tail=tail_target,queue=mapped,current=mapped_current,progress=progress,
    earned=early_earned+tail_earned}
end

local function set_state(technology, state)
  -- Setting researched=false after level would erase earned levels natively.
  technology.researched = state.researched
  technology.level = state.level
  technology.saved_progress = state.saved_progress
end

local function set_queue(force, names, current, progress)
  local rows = {}
  for _, id in ipairs(names) do rows[#rows+1] = assert(force.technologies[id], "MIR missing queued technology " .. id) end
  force.research_queue = rows
  if not same_names(queue_names(force), names) or current_name(force) ~= (current or names[1]) then
    error("MIR Imersite queue readback differs", 2)
  end
  force.research_progress = current and progress or 0
  if force.research_progress ~= (current and progress or 0) then error("MIR Imersite progress readback differs", 2) end
end

local function clear(holder, first)
  set_state(holder, {researched=false,level=first,saved_progress=0})
  holder.enabled, holder.visible_when_disabled = false, false
end

function M.initialize_force(force, change)
  local technologies = force and force.technologies
  if not technologies or not admitted(technologies,change) then return end
  local queue, current = queue_names(force), current_name(force)
  for index, id in ipairs(HOLDERS) do
    local state = snapshot(technologies[id])
    local first = index == 1 and 1 or 4
    if valid_state(state,first) and not active(state,first,queue,current,id) then clear(technologies[id],first) end
  end
end

-- The legacy record is read-only evidence of an already held queue. It is
-- used only when the current queue is still exactly the recorded removal;
-- intervening player choices take precedence and are never overwritten.
function M.reconcile_force(force, change, records, legacy)
  local technologies = assert(force.technologies, "MIR missing force technologies")
  local ok, reason = admitted(technologies,change)
  if not ok then
    for _, id in ipairs(HOLDERS) do
      local holder = technologies[id]
      if holder then
        local state, first = snapshot(holder), id == HOLDERS[1] and 1 or 4
        if not valid_state(state,first) or active(state,first,queue_names(force),current_name(force),id) then
          error("MIR cannot discard active Imersite carrier: " .. tostring(reason),2)
        end
      end
    end
    return false
  end
  local before, queue, current = {}, queue_names(force), current_name(force)
  for _, id in ipairs({EARLY,TAIL,HOLDERS[1],HOLDERS[2]}) do before[id] = snapshot(technologies[id]) end
  local early, tail = before[HOLDERS[1]], before[HOLDERS[2]]
  if not valid_state(early,1) or not valid_state(tail,4) then error("MIR invalid Imersite carrier state",2) end
  if not active(early,1,queue,current,HOLDERS[1]) and not active(tail,4,queue,current,HOLDERS[2]) then
    M.initialize_force(force,change)
    return false
  end
  if records[force.index] ~= nil then error("MIR Imersite carriers became active after completed handoff",2) end
  local checkpoint_progress = force.research_progress or 0
  local source_queue, source_current, source_progress = queue, current, checkpoint_progress
  if legacy ~= nil then
    local retry_safe = type(legacy) == "table" and (legacy.phase == "tail-held-no-continuation"
      or legacy.phase == "holder-held-unmatched-profile" or legacy.phase == "holder-retained-unmatched-profile"
      or legacy.phase == "holder-retained-retryable")
    if not retry_safe or legacy.schema ~= 3 or legacy.force_index ~= force.index
      or legacy.source ~= "json-two-holders-v1" or type(legacy.source_version) ~= "string"
      or legacy.source_version == "" or not valid_state(legacy.early,1)
      or not valid_state(legacy.continuation,4) or type(legacy.queue_before) ~= "table"
      or not finite(legacy.progress_before) or legacy.progress_before < 0 or legacy.progress_before > 1 then
      error("MIR unsafe or unsupported historical Imersite handoff record",2)
    end
    for key,name in pairs(legacy.queue_before) do
      if type(key) ~= "number" or key < 1 or key > #legacy.queue_before or key ~= math.floor(key)
        or type(name) ~= "string" or name == "" then error("MIR malformed historical Imersite queue",2) end
    end
    -- Do not replace investment accumulated by the currently surviving queue
    -- while a carrier was held. The holder's saved_progress remains available
    -- on its destination even when its old queue is no longer restored.
    local expected_progress = legacy.current_before == legacy.current_after_removal and legacy.progress_before or 0
    if type(legacy.queue_after_removal) == "table" and same_names(queue,legacy.queue_after_removal)
      and current == legacy.current_after_removal and checkpoint_progress == expected_progress then
      source_queue,source_current,source_progress = legacy.queue_before,legacy.current_before,legacy.progress_before
    end
  end
  local plan = M.plan(early,tail,before[EARLY],source_queue,source_current,source_progress)
  -- Public states must be fresh or already equal to this exact handoff. A
  -- foreign mutation is not permission to replace unrelated earned credit.
  for _, row in ipairs({{EARLY,1,plan.early},{TAIL,4,plan.tail}}) do
    local state, first, target = before[row[1]],row[2],row[3]
    local empty = state.level == first and not state.researched and state.saved_progress == 0
    local equal = state.level == target.level and state.researched == target.researched
      and state.saved_progress == target.saved_progress
    if not empty and not equal then error("MIR conflicting public Imersite state: " .. row[1],2) end
  end
  local bonus = force.recipes[contract.effect.recipe].productivity_bonus
  local applied, failure = pcall(function()
    set_state(technologies[EARLY],plan.early)
    set_state(technologies[TAIL],plan.tail)
    set_queue(force,plan.queue,plan.current,plan.progress)
    clear(technologies[HOLDERS[1]],1)
    clear(technologies[HOLDERS[2]],4)
    local after = force.recipes[contract.effect.recipe].productivity_bonus
    if not finite(bonus) or not finite(after) or math.abs(after-bonus) > 0.0000001 then
      error("MIR Imersite handoff changed the earned powder bonus")
    end
  end)
  if not applied then
    -- Four named identities only: restore the actual pre-handoff checkpoint,
    -- retain carriers/legacy records, and fail instead of saving partial loss.
    for _, id in ipairs({EARLY,TAIL,HOLDERS[1],HOLDERS[2]}) do
      set_state(technologies[id],before[id])
      technologies[id].enabled = before[id].enabled
      technologies[id].visible_when_disabled = before[id].visible_when_disabled
    end
    set_queue(force,queue,current,checkpoint_progress)
    error(tostring(failure),2)
  end
  records[force.index] = {schema=1,status="completed",earned=plan.earned,
    source_early=early,source_tail=tail,queue_before=source_queue,current_before=source_current,
    progress_before=source_progress}
  return true
end

return M
