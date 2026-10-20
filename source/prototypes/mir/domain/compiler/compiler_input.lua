local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot = require("prototypes.mir.domain.compiler.policy_snapshot")
local environment_identity = require("prototypes.mir.domain.environment_identity")

local M = {}
local authority = trusted_record.new("CompilerInput")
-- The ordinary compiler path retains its complete active values behind this
-- existing owner. Schema-2 CompilerInput remains the explicit generic
-- import/export record; it is not constructed just to drive the planner.
local active_authority = trusted_record.new("CompilerInputActive")
local active_owners = setmetatable({}, {__mode = "k"})
local SCHEMA = 2
local ACTIVE_SCHEMA = 1
local ACTIVE_CONTRACT = "mir-active-compiler-input-v1"

local function material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    source_fingerprints = record.source_fingerprints,
    compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    runtime_environment_fingerprint = record.runtime_environment_fingerprint,
    input_sanitation_fingerprint = record.input_sanitation_fingerprint
  }
end

local function trust_identity(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    runtime_environment_fingerprint = record.runtime_environment_fingerprint,
    input_fingerprint = record.input_fingerprint
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.record_type == registered.record_type
    and record.compilation_snapshot_fingerprint == registered.compilation_snapshot_fingerprint
    and record.policy_fingerprint == registered.policy_fingerprint
    and record.runtime_environment_fingerprint == registered.runtime_environment_fingerprint
    and record.input_fingerprint == registered.input_fingerprint
end

local function verify(record, options)
  options = options or {}
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "CompilerInput" then
    error("CompilerInput schema 2 record is required.", 2)
  end
  for _, field in ipairs({
    "compilation_snapshot_fingerprint", "policy_fingerprint", "runtime_environment_fingerprint",
    "input_sanitation_fingerprint"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("CompilerInput field is required: " .. field, 2)
    end
  end
  if type(record.source_fingerprints) ~= "table" then
    error("CompilerInput source fingerprints are required.", 2)
  end
  if options.trusted_children then
    compilation_snapshot.assert_trusted(record.compilation_snapshot)
    policy_snapshot.assert_trusted(record.policy_snapshot)
    environment_identity.assert_trusted(record.runtime_environment)
  else
    compilation_snapshot.verify_untrusted(record.compilation_snapshot)
    policy_snapshot.verify_untrusted(record.policy_snapshot)
    environment_identity.verify_untrusted(record.runtime_environment)
  end
  if record.compilation_snapshot.snapshot_fingerprint ~= record.compilation_snapshot_fingerprint
    or record.policy_snapshot.policy_fingerprint ~= record.policy_fingerprint
    or record.runtime_environment.environment_fingerprint ~= record.runtime_environment_fingerprint then
    error("CompilerInput bound authority fingerprint differs from its record.", 2)
  end
  if options.verify_fingerprint ~= false
    and record.input_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilerInput fingerprint is invalid.", 2)
  end
  return true
end

function M.verify_untrusted(record)
  authority.verify_untrusted(record, verify, trust_identity(record or {}))
  return true
end

function M.validate(record)
  return M.verify_untrusted(record)
end

function M.assert_trusted(record)
  if active_authority.is_trusted(record) then return M.assert_active(record) end
  return authority.assert_trusted(record, trust_identity_unchanged)
end

function M.is_trusted(record)
  return authority.is_trusted(record) or active_authority.is_trusted(record)
end

function M.new(values)
  values = values or {}
  local record = {
    schema = SCHEMA,
    record_type = "CompilerInput",
    source_fingerprints = values.source_fingerprints or {},
    compilation_snapshot = values.compilation_snapshot,
    policy_snapshot = values.policy_snapshot,
    runtime_environment = values.runtime_environment,
    input_sanitation_fingerprint = values.input_sanitation_fingerprint or fingerprint.of({})
  }
  record.compilation_snapshot_fingerprint = record.compilation_snapshot
    and record.compilation_snapshot.snapshot_fingerprint
  record.policy_fingerprint = record.policy_snapshot and record.policy_snapshot.policy_fingerprint
  record.runtime_environment_fingerprint = record.runtime_environment
    and record.runtime_environment.environment_fingerprint
  if compilation_snapshot.is_trusted(record.compilation_snapshot) then
    compilation_snapshot.assert_trusted(record.compilation_snapshot)
  else
    compilation_snapshot.verify_untrusted(record.compilation_snapshot)
  end
  if policy_snapshot.is_trusted(record.policy_snapshot) then
    policy_snapshot.assert_trusted(record.policy_snapshot)
  else
    policy_snapshot.verify_untrusted(record.policy_snapshot)
  end
  if environment_identity.is_trusted(record.runtime_environment) then
    environment_identity.assert_trusted(record.runtime_environment)
  else
    environment_identity.verify_untrusted(record.runtime_environment)
  end
  record.input_fingerprint = fingerprint.of(material(record))
  verify(record, {trusted_children = true, verify_fingerprint = false})
  return authority.register(record, trust_identity(record))
end


local function active_material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    contract = record.contract,
    base_input_fingerprint = record.base_input_fingerprint,
    stream_plan_fingerprint = record.stream_plan_fingerprint,
    base_continuation_input_fingerprint = record.base_continuation_input_fingerprint,
    base_candidates_fingerprint = record.base_candidates_fingerprint,
    provider_input_fingerprint = record.provider_input_fingerprint,
    effect_target_inventory_fingerprint = record.effect_target_inventory_fingerprint,
    source_fingerprint = record.source_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    runtime_environment_fingerprint = record.runtime_environment_fingerprint,
    input_sanitation_fingerprint = record.input_sanitation_fingerprint
  }
end

local ACTIVE_IDENTITY_FIELDS = {
  "schema", "record_type", "contract", "base_input_fingerprint",
  "stream_plan_fingerprint", "base_continuation_input_fingerprint",
  "base_candidates_fingerprint", "provider_input_fingerprint",
  "effect_target_inventory_fingerprint", "source_fingerprint",
  "policy_fingerprint", "runtime_environment_fingerprint",
  "input_sanitation_fingerprint", "input_fingerprint"
}

local function active_identity(record)
  local out = {}
  for _, field in ipairs(ACTIVE_IDENTITY_FIELDS) do out[field] = record[field] end
  return out
end

local function active_identity_unchanged(record, registered)
  for _, field in ipairs(ACTIVE_IDENTITY_FIELDS) do
    if record[field] ~= registered[field] then return false end
  end
  return true
end

-- GenerationPlan keeps the private authority for its own artifacts.  The
-- domain carrier binds only the structural plan identity; its planner
-- consumers admit the carried instance through GenerationPlan immediately
-- before use.  This avoids making the domain layer the owner of planner state.
local function bound_stream_plan_fingerprint(plan)
  if type(plan) ~= "table" or type(plan.plan_fingerprint) ~= "string"
    or plan.plan_fingerprint == "" then
    error("Active CompilerInput requires a bound GenerationPlan fingerprint.", 3)
  end
  return plan.plan_fingerprint
end

-- The active owner copies values that have no existing private owner. Stream
-- plans and policy/environment records already have their own trust owners;
-- this record retains those exact owned values only for the compiler scope.
function M.new_active(values)
  values = values or {}
  if type(values.stream_plan) ~= "table" or type(values.base_continuation_inputs) ~= "table"
    or type(values.provider_inputs) ~= "table" or type(values.effect_target_inventory) ~= "table" then
    error("Active CompilerInput requires complete stream, base, provider, and target inputs.", 2)
  end
  if not policy_snapshot.is_trusted(values.policy_snapshot) then
    error("Active CompilerInput requires an exact owned PolicySnapshot.", 2)
  end
  policy_snapshot.assert_trusted(values.policy_snapshot)
  if not environment_identity.is_trusted(values.runtime_environment) then
    error("Active CompilerInput requires an exact owned RuntimeEnvironmentIdentity.", 2)
  end
  environment_identity.assert_trusted(values.runtime_environment)
  local stream_plan_fingerprint = bound_stream_plan_fingerprint(values.stream_plan)
  local owner = {
    stream_plan = values.stream_plan,
    base_continuation_inputs = deepcopy(values.base_continuation_inputs),
    base_candidates = deepcopy(values.base_candidates or {}),
    provider_inputs = deepcopy(values.provider_inputs),
    effect_target_inventory = deepcopy(values.effect_target_inventory),
    source_fingerprints = deepcopy(values.source_fingerprints or {}),
    policy_snapshot = values.policy_snapshot,
    runtime_environment = values.runtime_environment
  }
  local record = {
    schema = ACTIVE_SCHEMA,
    record_type = "ActiveCompilerInput",
    contract = ACTIVE_CONTRACT,
    base_input_fingerprint = values.base_input_fingerprint,
    stream_plan_fingerprint = stream_plan_fingerprint,
    base_continuation_input_fingerprint = fingerprint.of(owner.base_continuation_inputs),
    base_candidates_fingerprint = fingerprint.of(owner.base_candidates),
    provider_input_fingerprint = fingerprint.of(owner.provider_inputs),
    effect_target_inventory_fingerprint = fingerprint.of(owner.effect_target_inventory),
    source_fingerprint = fingerprint.of(owner.source_fingerprints),
    policy_fingerprint = values.policy_snapshot.policy_fingerprint,
    runtime_environment_fingerprint = values.runtime_environment.environment_fingerprint,
    input_sanitation_fingerprint = values.input_sanitation_fingerprint or fingerprint.of({})
  }
  record.input_fingerprint = fingerprint.of(active_material(record))
  active_owners[record] = owner
  return active_authority.register(record, active_identity(record))
end

function M.is_active(record)
  return active_authority.is_trusted(record)
end

function M.assert_active(record)
  active_authority.assert_trusted(record, active_identity_unchanged)
  local owner = active_owners[record]
  if type(owner) ~= "table" then error("Active CompilerInput owner is unavailable.", 2) end
  -- The exact GenerationPlan owner is authenticated by its planner consumers.
  -- Keep this carrier bound to the same structural plan identity in the meantime.
  if bound_stream_plan_fingerprint(owner.stream_plan) ~= record.stream_plan_fingerprint then
    error("Active CompilerInput bound GenerationPlan fingerprint differs from its record.", 2)
  end
  policy_snapshot.assert_trusted(owner.policy_snapshot)
  environment_identity.assert_trusted(owner.runtime_environment)
  return record
end

-- Internal compiler-only view. Public methods below return generic detached
-- schema-2 values and never expose this owner table.
function M.active_view(record)
  M.assert_active(record)
  return active_owners[record]
end

function M.qualify_active(base, values)
  M.assert_active(base)
  values = values or {}
  local owner = active_owners[base]
  local qualified = M.new_active({
    base_input_fingerprint = base.input_fingerprint,
    stream_plan = values.stream_plan or owner.stream_plan,
    base_continuation_inputs = values.base_continuation_inputs or owner.base_continuation_inputs,
    base_candidates = values.base_candidates or owner.base_candidates,
    provider_inputs = owner.provider_inputs,
    effect_target_inventory = owner.effect_target_inventory,
    source_fingerprints = values.source_fingerprints or owner.source_fingerprints,
    policy_snapshot = owner.policy_snapshot,
    runtime_environment = owner.runtime_environment,
    input_sanitation_fingerprint = base.input_sanitation_fingerprint
  })
  return qualified
end

function M.runtime_environment(record)
  if M.is_active(record) then return M.active_view(record).runtime_environment end
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  return record.runtime_environment
end

function M.compatibility_projection(record, generation_plan_fingerprint)
  local active = M.is_active(record) and M.active_view(record) or nil
  if not active then
    if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  end
  local runtime_environment = active and active.runtime_environment or record.runtime_environment
  local source_fingerprints = active and active.source_fingerprints or record.source_fingerprints
  local environment = environment_identity.compatibility_projection(runtime_environment)
  local out = {
    schema = 1,
    record_type = "CompilerInput",
    source_fingerprints = deepcopy(source_fingerprints),
    environment_identity = environment,
    environment_fingerprint = environment.environment_fingerprint,
    target_profile_fingerprint = runtime_environment.target_profile_fingerprint,
    generation_plan_fingerprint = generation_plan_fingerprint
      or (active and record.input_fingerprint or record.compilation_snapshot_fingerprint),
    input_sanitation_fingerprint = record.input_sanitation_fingerprint,
    authoritative_input_fingerprint = record.input_fingerprint
  }
  local fp_material = deepcopy(out)
  fp_material.input_fingerprint = nil
  out.input_fingerprint = fingerprint.of(fp_material)
  return out
end

-- ActiveCompilerInput is compiler-scope only. It intentionally has no
-- schema-2 export: constructing one later would read the post-emission
-- prototype world and misrepresent the original input. Callers needing the
-- supported generic record must capture it before entering this owned path.
function M.legacy_view(record)
  if M.is_active(record) then
    M.assert_active(record)
    error("Active CompilerInput has no post-construction legacy export; capture schema-2 input before compiler mutation.", 2)
  end
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  return record
end

function M.snapshot(record)
  if M.is_active(record) then
    M.assert_active(record)
    error("Active CompilerInput has no post-construction legacy export; capture schema-2 input before compiler mutation.", 2)
  end
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  authority.count_snapshot()
  authority.count_full_copy()
  local out = deepcopy(record)
  out.compilation_snapshot = compilation_snapshot.snapshot(record.compilation_snapshot)
  return out
end

return M
