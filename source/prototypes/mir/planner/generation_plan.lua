local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local effect_contracts = require("prototypes.mir.integrity.effect_contracts")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")

local M = {}
local Plan = {}
Plan.__index = Plan
local trusted_artifacts = setmetatable({}, {__mode = "k"})
local trusted_drafts = setmetatable({}, {__mode = "k"})
-- Internal compiler views are distinct from public exports. They retain the
-- exact finalized GenerationPlan authority during one compiler scope.
local trusted_internal_artifacts = setmetatable({}, {__mode = "k"})
-- Keys are compact final-only rows. Complete rows remain in the private owner;
-- the active compiler uses an internal view and public exports are detached.
local owned_rows = setmetatable({}, {__mode = "k"})

local ACTIONS = {
  adopt = true,
  emit = true,
  skip = true
}

local REQUIRED_GATES = hard_gate_authority.order()

local function effect_identity(effect)
  return effect_contracts.identity(effect)
end

local function effect_signature(effect)
  if not effect or effect.type == nil or effect.type == "nothing" then return "" end
  local normalized = {}
  for key, value in pairs(effect) do
    if key ~= "icon" and key ~= "icons" then normalized[key] = deepcopy(value) end
  end
  return fingerprint.canonical(normalized)
end

local function validate_gate(row, gate_name)
  local gate = row.gates[gate_name]
  if gate_contract.is_trusted(gate) then gate_contract.assert_trusted(gate)
  else gate_contract.verify_untrusted(gate) end
  if row.action ~= "skip" and gate.status == "failed" then
    error("GenerationPlan materializing row failed gate " .. gate_name .. ": " .. row.stream_key, 3)
  end
end

local function required(row, field)
  if row[field] == nil then
    error("GenerationPlan row missing required field: " .. field, 3)
  end
end

local function validate_row(row, options)
  options = options or {}
  if type(row) ~= "table" then error("GenerationPlan row must be a table", 3) end
  if row.schema ~= 3 then error("GenerationPlan row schema must be 3", 3) end
  required(row, "stream_key")
  required(row, "manifest_id")
  required(row, "action")
  required(row, "source")
  if not ACTIONS[row.action] then
    error("GenerationPlan row has unsupported action: " .. tostring(row.action), 3)
  end
  required(row, "gates")
  hard_gate_authority.assert_total(row.gates)
  for _, gate in ipairs(REQUIRED_GATES) do
    validate_gate(row, gate)
  end
  if row.action == "emit" then
    required(row, "technology_name")
    if options.preparation then
      technology_design.preparation_fingerprint(options.preparation, row)
    elseif options.design_derived then
      required(row, "technology_design")
      if technology_design.is_trusted(row.technology_design) then
        technology_design.assert_trusted(row.technology_design)
      else
        technology_design.verify_untrusted(row.technology_design)
      end
    else
      required(row, "technology_design")
      technology_design.assert_generation_row(row)
    end
    required(row, "fields")
    required(row.fields, "effects")
    required(row.fields, "ingredients")
    required(row.fields, "prerequisites")
    if row.fields.count_formula ~= nil then
      if row.fields.count ~= nil then
        error("GenerationPlan row must use exactly one research cost representation", 3)
      end
    else
      local count = row.fields.count
      if type(count) ~= "number" or count < 1 or count >= math.huge or count % 1 ~= 0 then
        error("GenerationPlan row requires a count formula or a positive finite integer count", 3)
      end
    end
    required(row.fields, "research_time")
    required(row.fields, "max_level")
  elseif row.action == "adopt" then
    required(row, "adoption")
    required(row, "technology_design")
    if row.adoption.schema ~= 2 then error("GenerationPlan native-owner binding schema must be 2", 3) end
    required(row.adoption, "owner")
    required(row.adoption, "operation")
    required(row.adoption, "configured_fields")
    required(row.adoption, "effects")
    required(row.adoption, "input_snapshot")
    required(row.adoption, "expected_snapshot")
    required(row.adoption, "input_fingerprint")
    required(row.adoption, "output_fingerprint")
    if fingerprint.of(row.adoption.input_snapshot) ~= row.adoption.input_fingerprint then
      error("GenerationPlan native-owner input fingerprint differs: " .. row.stream_key, 3)
    end
    if fingerprint.of(row.adoption.expected_snapshot) ~= row.adoption.output_fingerprint then
      error("GenerationPlan native-owner output fingerprint differs: " .. row.stream_key, 3)
    end
    if options.design_derived then
      if technology_design.is_trusted(row.technology_design) then
        technology_design.assert_trusted(row.technology_design)
      else
        technology_design.verify_untrusted(row.technology_design)
      end
    else
      technology_design.assert_generation_row(row)
    end
  else
    required(row, "reason")
  end
end

function M.new(metadata)
  metadata = metadata or {}
  return setmetatable({
    rows = {},
    finalized = false,
    source_fingerprints = deepcopy(metadata.source_fingerprints or {}),
    validation_summary = nil,
    plan_fingerprint = nil
  }, Plan)
end

function Plan:add(row)
  if self.finalized then error("GenerationPlan is already finalized", 2) end
  validate_row(row)
  table.insert(self.rows, deepcopy(row))
end

local function unowned_row_fingerprint_material(row, preparation)
  local design = row.technology_design or {}
  local adoption = row.adoption
  return {
    schema = row.schema,
    stream_key = row.stream_key,
    manifest_id = row.manifest_id,
    action = row.action,
    source = row.source,
    reason = row.reason,
    technology_name = row.technology_name,
    target_profile_fingerprint = row.target_profile_fingerprint,
    provider_ids = row.provider_ids,
    family_ids = row.family_ids,
    technology_risk = row.technology_risk,
    gates = row.gates,
    diagnostics = row.diagnostics,
    effect_ownership = row.effect_ownership,
    effect_integrity = row.effect_integrity,
    graph_integrity = row.graph_integrity,
    adoption = adoption and {
      schema = adoption.schema,
      owner = adoption.owner,
      operation = adoption.operation,
      configured_fields = adoption.configured_fields,
      planned_max_level = adoption.planned_max_level,
      effects = adoption.effects,
      input_fingerprint = adoption.input_fingerprint,
      output_fingerprint = adoption.output_fingerprint
    } or nil,
    planned_max_level = row.planned_max_level,
    stage_kind = row.stage_kind,
    staged_parent_technology = row.staged_parent_technology,
    staged_parent_stream_key = row.staged_parent_stream_key,
    configured_stream_key = row.configured_stream_key,
    generation_preparation = preparation and {
      schema = 1,
      input_fingerprint = technology_design.preparation_fingerprint(preparation, row)
    } or nil,
    technology_design = row.technology_design and {
      schema = design.schema,
      candidate_id = design.candidate_id,
      technology_id = design.technology_id,
      subject_fingerprint = design.subject_fingerprint,
      design_fingerprint = design.design_fingerprint,
      prototype_fingerprint = design.prototype_fingerprint,
      qualification_fingerprint = design.qualification_fingerprint,
      semantic_fingerprint = design.semantic_fingerprint
    } or nil
  }
end

local function row_fingerprint_material(row, preparation)
  local owner = owned_rows[row]
  if owner then
    return {
      schema = 5,
      record_type = "OwnedGenerationPlanRow",
      identity = owner.identity
    }
  end
  return unowned_row_fingerprint_material(row, preparation)
end

local function rows_fingerprint_material(rows, preparations)
  local out = {}
  for index, row in ipairs(rows) do
    out[index] = row_fingerprint_material(row, preparations and preparations[row])
  end
  return out
end

local owned_row_identity_material

local function final_design_for_owned_row(row)
  if type(row) ~= "table" or type(row.gates) ~= "table" then
    error("GenerationPlan owned row capture requires a complete row and Gate map.", 3)
  end
  hard_gate_authority.assert_total(row.gates)
  if type(row.technology_design) ~= "table" then
    error("GenerationPlan owned row capture requires its final TechnologyDesign.", 3)
  end
  -- The construction/import boundary has already admitted the full Gate proof.
  -- This final handoff requires the exact admitted Gate instances bound into
  -- the final Design before consuming the graph builder's transient row.
  technology_design.assert_trusted(row.technology_design)
  local exact = true
  for _, gate_name in ipairs(REQUIRED_GATES) do
    gate_contract.assert_trusted(row.gates[gate_name])
    if not rawequal(row.gates[gate_name], row.technology_design.gates[gate_name]) then
      exact = false
    end
  end
  if exact then return row.technology_design end
  -- A supported public Plan re-entry has already been defensively copied, so
  -- its independently admitted Design/Gate tables are not reference-equal and
  -- sanitation may have changed the row action. Reconstruct only this explicit
  -- re-entry path from the authoritative final row; ordinary graph rows retain
  -- the no-refresh fast path above.
  return technology_design.from_generation_row(row)
end

local function consume_owned_row(row)
  local owned_design = final_design_for_owned_row(row)
  -- This is the consuming, internal post-graph handoff. The graph builder has
  -- finished with this transient row; its Design and Gate values already own
  -- their immutable inputs. Move that record rather than copying those values
  -- again. Mutable public input uses Plan:add and its deep admission/copy.
  validate_row(row, {design_derived = true})
  local full = {}
  for key, value in pairs(row) do
    full[key] = value
    row[key] = nil
  end
  full.technology_design = owned_design
  -- Preserve the exact final admitted Gate vector in both projections.
  full.gates = owned_design.gates
  local compact = {
    schema = full.schema,
    stream_key = full.stream_key,
    manifest_id = full.manifest_id,
    action = full.action,
    technology_name = full.technology_name
  }
  owned_rows[compact] = {
    full = full,
    -- The complete record is consumed above. Schema 5 deliberately hashes
    -- this compact semantic identity rather than re-traversing its proof.
    identity = owned_row_identity_material(full)
  }
  return compact
end

local function owned_row(row)
  local owner = owned_rows[row]
  return owner and owner.full or row
end

owned_row_identity_material = function(row)
  local design = row.technology_design or {}
  local adoption = row.adoption or {}
  -- Schema-5 Plan material names the closed owner and its semantic outputs.
  -- It deliberately does not recanonicalize the private complete proof record:
  -- that record was already admitted and the graph builder has completed its
  -- ownership transfer. Full proof content remains in all explicit exports.
  return {
    schema = row.schema,
    stream_key = row.stream_key,
    manifest_id = row.manifest_id,
    action = row.action,
    reason = row.reason,
    technology_name = row.technology_name,
    target_profile_fingerprint = row.target_profile_fingerprint,
    stage_kind = row.stage_kind,
    staged_parent_technology = row.staged_parent_technology,
    staged_parent_stream_key = row.staged_parent_stream_key,
    configured_stream_key = row.configured_stream_key,
    adoption = next(adoption) and {
      owner = adoption.owner,
      operation = adoption.operation,
      input_fingerprint = adoption.input_fingerprint,
      output_fingerprint = adoption.output_fingerprint
    } or nil,
    design = {
      candidate_id = design.candidate_id,
      technology_id = design.technology_id,
      subject_fingerprint = design.subject_fingerprint,
      design_fingerprint = design.design_fingerprint,
      prototype_fingerprint = design.prototype_fingerprint,
      qualification_fingerprint = design.qualification_fingerprint,
      semantic_fingerprint = design.semantic_fingerprint
    }
  }
end

local function exported_rows(rows)
  local out = {}
  for index, row in ipairs(rows or {}) do out[index] = deepcopy(owned_row(row)) end
  return out
end

local function same_qualified_material_stage(previous, row, previous_effect, effect)
  return previous and previous.action == "emit"
    and row.action == "emit"
    and row.stage_kind == "material-continuation"
    and row.staged_parent_technology == previous.technology_name
    and row.staged_parent_stream_key == previous.stream_key
    and row.configured_stream_key == previous.stream_key
    and row.technology_name ~= previous.technology_name
    and effect_signature(previous_effect) == effect_signature(effect)
end

function Plan:add_derived(row)
  if self.finalized then error("GenerationPlan is already finalized", 2) end
  validate_row(row, {design_derived = true})
  table.insert(self.rows, deepcopy(row))
end

function Plan:add_owned_derived(row)
  if self.finalized then error("GenerationPlan is already finalized", 2) end
  -- This path receives a compiler-owned row and finalizes immediately. Keep
  -- the draft's mutable row until graph work has completed.  The final Plan
  -- consumes the complete row and leaves only a compact handle in
  -- its ordinary internal row list.
  table.insert(self.rows, self.preparations and row or consume_owned_row(row))
end

function Plan:finalize()
  if self.finalized then return self end

  table.sort(self.rows, function(a, b)
    if a.stream_key ~= b.stream_key then return a.stream_key < b.stream_key end
    if a.action ~= b.action then return a.action < b.action end
    return tostring(a.manifest_id) < tostring(b.manifest_id)
  end)

  local stream_keys = {}
  local manifest_ids = {}
  local technology_names = {}
  local adopted_recipes = {}
  local adopted_owners = {}
  local materialized_effects = {}
  for _, stored_row in ipairs(self.rows) do
    local row = owned_row(stored_row)
    -- Recheck the inexpensive row and gate invariants at the ownership
    -- boundary without repeating complete TechnologyDesign fingerprints.
    validate_row(row, {design_derived = true,
      preparation = self.preparations and self.preparations[row]})
    if stream_keys[row.stream_key] then
      error("GenerationPlan contains duplicate stream key: " .. row.stream_key, 2)
    end
    stream_keys[row.stream_key] = true

    if row.action == "emit" then
      if manifest_ids[row.manifest_id] then
        error("GenerationPlan contains duplicate emitted manifest id: " .. row.manifest_id, 2)
      end
      if technology_names[row.technology_name] then
        error("GenerationPlan contains duplicate technology name: " .. row.technology_name, 2)
      end
      manifest_ids[row.manifest_id] = true
      technology_names[row.technology_name] = true
      for _, effect in ipairs(row.fields.effects or {}) do
        local identity = effect_identity(effect)
        if identity ~= "" then
          local previous = materialized_effects[identity]
          if previous and not same_qualified_material_stage(
              previous.row, row, previous.effect, effect) then
            error("GenerationPlan contains duplicate materialized effect identity: " .. identity, 2)
          end
          materialized_effects[identity] = {row = row, effect = effect}
        end
      end
    elseif row.action == "adopt" then
      if adopted_owners[row.adoption.owner] then
        error("GenerationPlan contains duplicate native-owner binding: " .. row.adoption.owner, 2)
      end
      adopted_owners[row.adoption.owner] = row.stream_key
      for _, effect in ipairs(row.adoption.effects) do
        local identity = row.adoption.owner .. "\0" .. tostring(effect.recipe)
        if adopted_recipes[identity] then
          error("GenerationPlan contains duplicate adopted recipe: " .. tostring(effect.recipe), 2)
        end
        adopted_recipes[identity] = true
        local effect_key = effect_identity(effect)
        if effect_key ~= "" then
          if materialized_effects[effect_key] then
            error("GenerationPlan contains duplicate materialized effect identity: " .. effect_key, 2)
          end
          materialized_effects[effect_key] = {row = row, effect = effect}
        end
      end
    end
  end

  self.finalized = true
  local action_counts, reason_counts = {}, {}
  for _, stored_row in ipairs(self.rows) do
    local row = owned_row(stored_row)
    action_counts[row.action] = (action_counts[row.action] or 0) + 1
    local reason = row.reason or row.action
    reason_counts[reason] = (reason_counts[reason] or 0) + 1
  end
  local ownership_conflict_count = 0
  for _, stored_row in ipairs(self.rows) do
    local row = owned_row(stored_row)
    ownership_conflict_count = ownership_conflict_count + #((row.effect_ownership and row.effect_ownership.lost) or {})
  end
  self.validation_summary = {
    valid = true,
    row_count = #self.rows,
    action_counts = action_counts,
    reason_counts = reason_counts,
    effect_ownership_conflict_count = ownership_conflict_count
  }
  self.plan_fingerprint = fingerprint.of({
    schema = self.preparations and 1 or 5,
    record_type = self.preparations and "GenerationDraft" or nil,
    source_fingerprints = self.source_fingerprints,
    rows = rows_fingerprint_material(self.rows, self.preparations),
    validation_summary = self.validation_summary
  })
  return self
end

function Plan:snapshot()
  if not self.finalized then error("GenerationPlan must be finalized before snapshot", 2) end
  return exported_rows(self.rows)
end

function Plan:count(action)
  local count = 0
  for _, row in ipairs(self.rows) do
    if action == nil or row.action == action then count = count + 1 end
  end
  return count
end

function Plan:artifact()
  if not self.finalized then error("GenerationPlan must be finalized before artifact export", 2) end
  return {
    schema = 3,
    plan_fingerprint = self.plan_fingerprint,
    source_fingerprints = deepcopy(self.source_fingerprints),
    rows = exported_rows(self.rows),
    validation_summary = deepcopy(self.validation_summary)
  }
end

function Plan:artifact_view()
  if not self.finalized then error("GenerationPlan must be finalized before artifact view", 2) end
  local artifact = {
    schema = 3,
    plan_fingerprint = self.plan_fingerprint,
    source_fingerprints = self.source_fingerprints,
    rows = self.rows,
    validation_summary = self.validation_summary
  }
  trusted_artifacts[artifact] = {
    plan_fingerprint = self.plan_fingerprint,
    source_fingerprints = self.source_fingerprints,
    rows = self.rows,
    validation_summary = self.validation_summary
  }
  return artifact
end

function M.assert_trusted_artifact(artifact)
  local authority = trusted_artifacts[artifact]
  if not authority
    or artifact.schema ~= 3
    or artifact.plan_fingerprint ~= authority.plan_fingerprint
    or artifact.source_fingerprints ~= authority.source_fingerprints
    or artifact.rows ~= authority.rows
    or artifact.validation_summary ~= authority.validation_summary then
    error("GenerationPlan artifact is not the exact trusted finalized view", 2)
  end
  return artifact
end

function M.is_trusted_artifact(artifact)
  return trusted_artifacts[artifact] ~= nil
end

-- The compact rows belong only to a trusted internal artifact.  Consumers
-- during the one compiler run receive the private authority records; all
-- caller-visible surfaces receive a detached complete reconstruction.
function M.rows_for_consumption(artifact)
  local rows = {}
  for index, row in ipairs((artifact or {}).rows or {}) do rows[index] = owned_row(row) end
  return rows
end

function M.internal_artifact(artifact)
  M.assert_trusted_artifact(artifact)
  local view = {}
  for key, value in pairs(artifact) do view[key] = value end
  view.rows = M.rows_for_consumption(artifact)
  trusted_internal_artifacts[view] = {
    plan_fingerprint = artifact.plan_fingerprint,
    source_fingerprints = artifact.source_fingerprints,
    rows = view.rows,
    validation_summary = artifact.validation_summary
  }
  return view
end

-- One private GenerationPlan admission surface for compiler-scope handoffs.
-- It keeps exact-instance authentication with this owner while allowing both
-- pre-graph drafts and finalized internal views through their existing paths.
function M.assert_owned_view(artifact)
  if M.is_draft(artifact) then
    M.assert_trusted_draft(artifact)
  elseif M.is_trusted_internal_artifact(artifact) then
    M.assert_trusted_internal_artifact(artifact)
  elseif M.is_trusted_artifact(artifact) then
    M.assert_trusted_artifact(artifact)
  else
    error("GenerationPlan compiler handoff is not an exact owned view.", 2)
  end
  return artifact
end
function M.is_trusted_internal_artifact(artifact)
  return trusted_internal_artifacts[artifact] ~= nil
end

function M.assert_trusted_internal_artifact(artifact)
  local authority = trusted_internal_artifacts[artifact]
  if not authority
    or artifact.schema ~= 3
    or artifact.plan_fingerprint ~= authority.plan_fingerprint
    or artifact.source_fingerprints ~= authority.source_fingerprints
    or artifact.rows ~= authority.rows
    or artifact.validation_summary ~= authority.validation_summary then
    error("GenerationPlan internal artifact is not the exact owned compiler view", 2)
  end
  return artifact
end

function M.export_artifact(artifact)
  if type(artifact) ~= "table" then return deepcopy(artifact) end
  local exported = {}
  for key, value in pairs(artifact) do
    if key == "rows" and type(value) == "table" then
      exported.rows = exported_rows(value)
    else
      exported[deepcopy(key)] = deepcopy(value)
    end
  end
  return exported
end

-- The private pre-graph handoff is deliberately not a schema-3 GenerationPlan.
-- Its opaque preparations never occur in serialized rows or context state.
function M.prepare(rows, metadata)
  local plan = M.new(metadata)
  plan.preparations = {}
  for _, row in ipairs(rows) do
    if row.action == "emit" and row.stage_kind ~= "material-continuation" then
      plan.preparations[row] = technology_design.prepare_generation_row(row)
    else
      row.technology_design = technology_design.from_generation_row(row)
    end
    plan:add_owned_derived(row)
  end
  plan:finalize()
  local draft = {
    schema = 1, record_type = "GenerationDraft", phase = "pregraph",
    plan_fingerprint = plan.plan_fingerprint,
    source_fingerprints = plan.source_fingerprints,
    rows = plan.rows, validation_summary = plan.validation_summary
  }
  trusted_drafts[draft] = {plan = plan, plan_fingerprint = draft.plan_fingerprint,
    rows = draft.rows, source_fingerprints = draft.source_fingerprints,
    validation_summary = draft.validation_summary}
  return draft
end

function M.is_draft(artifact)
  return type(artifact) == "table" and artifact.record_type == "GenerationDraft"
end

function M.assert_trusted_draft(draft)
  local owned = trusted_drafts[draft]
  if not owned or draft.schema ~= 1 or draft.record_type ~= "GenerationDraft" or draft.phase ~= "pregraph"
    or draft.plan_fingerprint ~= owned.plan_fingerprint or draft.rows ~= owned.rows
    or draft.source_fingerprints ~= owned.source_fingerprints
    or draft.validation_summary ~= owned.validation_summary then
    error("GenerationDraft must be the exact private pre-graph handoff.", 2)
  end
  return owned.plan.preparations
end

function M.materialize_draft(draft)
  local preparations = M.assert_trusted_draft(draft)
  local plan = M.new({source_fingerprints = draft.source_fingerprints})
  for _, row in ipairs(draft.rows) do
    local exported = {}
    for key, value in pairs(row) do exported[key] = value end
    if preparations[row] then
      exported.technology_design = technology_design.finalize_prepared_generation_row(
        preparations[row], row)
    end
    plan:add_owned_derived(exported)
  end
  return plan:finalize():artifact()
end

function M.effect_identity(effect)
  return effect_identity(effect)
end

function M.effect_signature(effect)
  return effect_signature(effect)
end

return M
