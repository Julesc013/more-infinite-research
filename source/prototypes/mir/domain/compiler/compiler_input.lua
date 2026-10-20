local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot = require("prototypes.mir.domain.compiler.policy_snapshot")
local environment_identity = require("prototypes.mir.domain.environment_identity")
local gate_contract = require("prototypes.mir.domain.technology.gate")

local M = {}
local authority = trusted_record.new("CompilerInput")
local SCHEMA = 2
local ordinary_inputs = setmetatable({}, {__mode = "k"})
local ordinary_qualified_inputs = setmetatable({}, {__mode = "k"})
-- Ephemeral compiler-phase projections, issued only after an owned qualified
-- handoff has validated the actual semantic input and consumed final rows.
local ordinary_component_projections = setmetatable({}, {__mode = "k"})

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

local function ordinary_material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    input_scope = record.input_scope,
    compilation_semantic_fingerprint = record.compilation_semantic_fingerprint,
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
  return authority.assert_trusted(record, trust_identity_unchanged)
end

function M.is_trusted(record)
  return authority.is_trusted(record)
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

-- The semantic snapshot is admitted by CompilationSnapshot itself.  This
-- owner binds it to policy/environment and keeps the ordinary record private;
-- full schema-2 CompilerInput construction remains unchanged above.
function M.new_ordinary(values)
  values = values or {}
  compilation_snapshot.assert_ordinary(values.compilation_snapshot)
  if policy_snapshot.is_trusted(values.policy_snapshot) then policy_snapshot.assert_trusted(values.policy_snapshot)
  else policy_snapshot.verify_untrusted(values.policy_snapshot) end
  if environment_identity.is_trusted(values.runtime_environment) then
    environment_identity.assert_trusted(values.runtime_environment)
  else
    environment_identity.verify_untrusted(values.runtime_environment)
  end
  local record = {
    schema = SCHEMA,
    record_type = "CompilerInput",
    input_scope = "ordinary-semantic",
    -- Alias the semantic snapshot's already deep-owned source material.  The
    -- alias is checked below; a second copy would add work without another
    -- ownership boundary.
    source_fingerprints = values.compilation_snapshot.source_fingerprints,
    compilation_snapshot = values.compilation_snapshot,
    compilation_semantic_fingerprint = values.compilation_snapshot.semantic_input_fingerprint,
    policy_snapshot = values.policy_snapshot,
    policy_fingerprint = values.policy_snapshot.policy_fingerprint,
    runtime_environment = values.runtime_environment,
    runtime_environment_fingerprint = values.runtime_environment.environment_fingerprint,
    input_sanitation_fingerprint = values.input_sanitation_fingerprint or fingerprint.of({})
  }
  record.compilation_snapshot_fingerprint = record.compilation_semantic_fingerprint
  record.input_fingerprint = fingerprint.of(ordinary_material(record))
  ordinary_inputs[record] = record.input_fingerprint
  return record
end

function M.is_ordinary(record)
  return type(record) == "table" and record.input_scope == "ordinary-semantic"
    and ordinary_inputs[record] ~= nil
end

function M.assert_ordinary(record)
  if type(record) ~= "table" or record.input_scope ~= "ordinary-semantic"
    or ordinary_inputs[record] == nil then
    error("Ordinary CompilerInput private ownership is required.", 2)
  end
  policy_snapshot.assert_trusted(record.policy_snapshot)
  environment_identity.assert_trusted(record.runtime_environment)
  compilation_snapshot.assert_ordinary(record.compilation_snapshot)
  if record.source_fingerprints ~= record.compilation_snapshot.source_fingerprints
    or record.compilation_semantic_fingerprint ~= record.compilation_snapshot.semantic_input_fingerprint
    or record.compilation_snapshot_fingerprint ~= record.compilation_semantic_fingerprint
    or record.policy_fingerprint ~= record.policy_snapshot.policy_fingerprint
    or record.runtime_environment_fingerprint ~= record.runtime_environment.environment_fingerprint
    or record.input_fingerprint ~= ordinary_inputs[record]
    or record.input_fingerprint ~= fingerprint.of(ordinary_material(record)) then
    error("Ordinary CompilerInput semantic material or identity changed after capture.", 2)
  end
  return true
end

function M.assert_compilation_input(record)
  if M.is_ordinary(record) then return M.assert_ordinary(record) end
  if M.is_trusted(record) then return M.assert_trusted(record) end
  return M.verify_untrusted(record)
end

function M.assert_publication_input(record)
  return M.assert_compilation_input(record)
end

function M.assert_ordinary_planning_inputs(record, stream_inputs, base_inputs)
  M.assert_ordinary(record)
  return compilation_snapshot.assert_ordinary_planning_inputs(
    record.compilation_snapshot, stream_inputs, base_inputs)
end

local function qualified_ordinary_material(view)
  return {
    schema = view.schema,
    record_type = view.record_type,
    compilation_input_fingerprint = view.compilation_input_fingerprint,
    policy_fingerprint = view.policy_fingerprint
  }
end

-- The final rows are compiler-owned results of CompilationPlan.finalize.  Bind
-- only the values read by the following pure compiler phase.  Gate and Design
-- contents are rechecked by their existing authorities while that phase reads
-- them; serializing every full row here would duplicate the same work three
-- times without creating another mutation boundary.
--
-- Native adoption snapshots have their own reference and exact fingerprint
-- checks below.  The compiler also consumes/copies every remaining adoption
-- field, including configured_fields and unknown future payload keys.  Hash
-- that payload once without reserializing the two independently checked large
-- snapshots.
local function adoption_material_without_snapshots(adoption)
  local out = {}
  for key, value in pairs(adoption) do
    if key ~= "input_snapshot" and key ~= "expected_snapshot" then out[key] = value end
  end
  return out
end
local function capture_stream_bindings(stream_plan, gate_session)
  if type(stream_plan) ~= "table" or type(stream_plan.rows) ~= "table" then
    error("Ordinary CompilerInput qualification requires final stream rows.", 3)
  end
  local binding = {plan = stream_plan, rows = {}}
  for index, row in ipairs(stream_plan.rows) do
    if type(row) ~= "table" or (row.action ~= "emit" and row.action ~= "adopt" and row.action ~= "skip")
      or type(row.stream_key) ~= "string" or type(row.manifest_id) ~= "string" then
      error("Ordinary CompilerInput final stream row is malformed at " .. tostring(index), 3)
    end
    local entry = {
      row = row,
      action = row.action,
      stream_key = row.stream_key,
      manifest_id = row.manifest_id,
      technology_name = row.technology_name,
      technology_design = row.technology_design,
      gates = row.gates,
      gate_receipt = gate_contract.capture_initial_skip_gate_vector(gate_session, row.gates)
    }
    if row.action == "adopt" then
      local adoption = row.adoption
      if type(adoption) ~= "table" or type(adoption.owner) ~= "string"
        or type(adoption.input_fingerprint) ~= "string" or type(adoption.output_fingerprint) ~= "string" then
        error("Ordinary CompilerInput final native-owner row is malformed: " .. tostring(row.stream_key), 3)
      end
      entry.adoption = adoption
      entry.adoption_owner = adoption.owner
      entry.adoption_operation = adoption.operation
      entry.adoption_input_snapshot = adoption.input_snapshot
      entry.adoption_expected_snapshot = adoption.expected_snapshot
      -- The pure compiler reads configured_fields and transfers the complete
      -- adoption payload into the operation. Bind every non-snapshot field
      -- once per native patch row; this is not a whole-plan hash.
      entry.adoption_payload_fingerprint = fingerprint.of(adoption_material_without_snapshots(adoption))
      entry.adoption_input_fingerprint = adoption.input_fingerprint
      entry.adoption_output_fingerprint = adoption.output_fingerprint
    end
    binding.rows[index] = entry
  end
  return binding
end

local function assert_stream_bindings(binding, gate_session)
  local stream_plan = binding.plan
  if type(stream_plan) ~= "table" or type(stream_plan.rows) ~= "table"
    or #stream_plan.rows ~= #binding.rows then
    error("Ordinary qualified compiler input final stream membership changed.", 3)
  end
  for index, expected in ipairs(binding.rows) do
    local row = stream_plan.rows[index]
    if row ~= expected.row or type(row) ~= "table" or row.action ~= expected.action
      or row.stream_key ~= expected.stream_key or row.manifest_id ~= expected.manifest_id
      or row.technology_name ~= expected.technology_name
      or row.technology_design ~= expected.technology_design or row.gates ~= expected.gates then
      error("Ordinary qualified compiler input final stream row changed: " .. tostring(index), 3)
    end
    if not gate_contract.matches_initial_skip_gate_vector(gate_session, expected.gate_receipt, row.gates) then
      error("Ordinary qualified compiler input Gate contents changed: stream/" .. tostring(index), 3)
    end
    if expected.adoption then
      local adoption = row.adoption
      if adoption ~= expected.adoption or adoption.owner ~= expected.adoption_owner
        or adoption.operation ~= expected.adoption_operation
        or adoption.input_snapshot ~= expected.adoption_input_snapshot
        or adoption.expected_snapshot ~= expected.adoption_expected_snapshot
        or adoption.input_fingerprint ~= expected.adoption_input_fingerprint
        or adoption.output_fingerprint ~= expected.adoption_output_fingerprint
        or fingerprint.of(adoption_material_without_snapshots(adoption)) ~= expected.adoption_payload_fingerprint
        or fingerprint.of(adoption.input_snapshot) ~= adoption.input_fingerprint
        or fingerprint.of(adoption.expected_snapshot) ~= adoption.output_fingerprint then
        error("Ordinary qualified compiler input native-owner binding changed: "
          .. tostring(expected.stream_key), 3)
      end
    end
  end
end

local function capture_base_bindings(base_operations, gate_session)
  if type(base_operations) ~= "table" then
    error("Ordinary CompilerInput qualification requires final base operations.", 3)
  end
  local binding = {operations = base_operations, rows = {}}
  for index, operation in ipairs(base_operations) do
    if type(operation) ~= "table" or type(operation.key) ~= "string"
      or type(operation.technology_name) ~= "string" then
      error("Ordinary CompilerInput final base operation is malformed at " .. tostring(index), 3)
    end
    binding.rows[index] = {
      operation = operation,
      key = operation.key,
      technology_name = operation.technology_name,
      manifest_id = operation.manifest_id,
      technology_design = operation.technology_design,
      gates = operation.gates,
      gate_receipt = gate_contract.capture_initial_skip_gate_vector(gate_session, operation.gates)
    }
  end
  return binding
end

local function assert_base_bindings(binding, gate_session)
  local operations = binding.operations
  if type(operations) ~= "table" or #operations ~= #binding.rows then
    error("Ordinary qualified compiler input final base membership changed.", 3)
  end
  for index, expected in ipairs(binding.rows) do
    local operation = operations[index]
    if operation ~= expected.operation or type(operation) ~= "table"
      or operation.key ~= expected.key or operation.technology_name ~= expected.technology_name
      or operation.manifest_id ~= expected.manifest_id
      or operation.technology_design ~= expected.technology_design or operation.gates ~= expected.gates then
      error("Ordinary qualified compiler input final base operation changed: " .. tostring(index), 3)
    end
    if not gate_contract.matches_initial_skip_gate_vector(gate_session, expected.gate_receipt, operation.gates) then
      error("Ordinary qualified compiler input Gate contents changed: base/" .. tostring(index), 3)
    end
  end
end

-- Final stream/base rows are compiler-owned outputs of CompilationPlan.  Their
-- references plus consumed scalar bindings form one closed handoff.  The
-- subsequent pure compiler validates each Gate/Design while consuming it.
function M.qualify_ordinary(record, policy, stream_plan, base_operations)
  M.assert_ordinary(record)
  if policy ~= record.policy_snapshot then
    error("Ordinary CompilerInput qualification policy differs from its admitted input.", 2)
  end
  policy_snapshot.assert_trusted(policy)
  local view = {
    schema = 1,
    record_type = "QualifiedOrdinaryCompilerInput",
    compilation_input_fingerprint = record.compilation_semantic_fingerprint,
    policy_fingerprint = policy.policy_fingerprint
  }
  view.qualified_input_fingerprint = fingerprint.of(qualified_ordinary_material(view))
  local gate_session = gate_contract.new_initial_skip_gate_vector_session()
  ordinary_qualified_inputs[view] = {
    compiler_input = record,
    policy_snapshot = policy,
    gate_session = gate_session,
    stream = capture_stream_bindings(stream_plan, gate_session),
    base = capture_base_bindings(base_operations, gate_session),
    qualified_input_fingerprint = view.qualified_input_fingerprint
  }
  return view
end

function M.assert_ordinary_qualified(view)
  local owned = ordinary_qualified_inputs[view]
  if type(view) ~= "table" or view.record_type ~= "QualifiedOrdinaryCompilerInput" or not owned
    or view.qualified_input_fingerprint ~= owned.qualified_input_fingerprint
    or view.qualified_input_fingerprint ~= fingerprint.of(qualified_ordinary_material(view)) then
    error("Ordinary qualified compiler input private ownership or identity changed.", 2)
  end
  -- This is the one semantic-input mutation boundary before the pure compiler.
  M.assert_ordinary(owned.compiler_input)
  policy_snapshot.assert_trusted(owned.policy_snapshot)
  if owned.policy_snapshot ~= owned.compiler_input.policy_snapshot
    or view.compilation_input_fingerprint ~= owned.compiler_input.compilation_semantic_fingerprint
    or view.policy_fingerprint ~= owned.policy_snapshot.policy_fingerprint then
    error("Ordinary qualified compiler input changed after qualification.", 2)
  end
  assert_stream_bindings(owned.stream, owned.gate_session)
  assert_base_bindings(owned.base, owned.gate_session)
  -- This is a public assertion surface.  Its private ledger must never
  -- escape: callers receive only the successful validation result.
  return true
end

function M.ordinary_qualified_components(view)
  M.assert_ordinary_qualified(view)
  local owned = ordinary_qualified_inputs[view]
  if not owned then
    error("Ordinary qualified compiler input private ownership disappeared after validation.", 2)
  end
  -- This projection is a private same-phase continuation, not a public
  -- verification ledger.  It is registered only after the actual boundary
  -- above succeeds, and has no escape through exports or Context state.
  local projection = {
    compiler_input = owned.compiler_input,
    policy_snapshot = owned.policy_snapshot,
    stream_plan = owned.stream.plan,
    base_operations = owned.base.operations,
    qualified_input_fingerprint = owned.qualified_input_fingerprint
  }
  ordinary_component_projections[projection] = {view = view, owned = owned}
  return projection
end

function M.assert_ordinary_component_projection(projection)
  local issued = ordinary_component_projections[projection]
  if not issued or type(projection) ~= "table"
    or projection.qualified_input_fingerprint ~= issued.owned.qualified_input_fingerprint
    or projection.compiler_input ~= issued.owned.compiler_input
    or projection.policy_snapshot ~= issued.owned.policy_snapshot
    or projection.stream_plan ~= issued.owned.stream.plan
    or projection.base_operations ~= issued.owned.base.operations then
    error("Ordinary compiler component continuation is not the issued qualified projection.", 2)
  end
  -- Do not leak the private qualified-input ledger through an assertion API.
  return true
end

function M.ordinary_qualified_identity(view)
  M.assert_ordinary_qualified(view)
  return view.qualified_input_fingerprint
end

function M.provider_inputs(record)
  -- Ordinary CompilerInput is verified once at each consuming boundary. These
  -- are internal field reads during one nonyielding compiler phase; rehashing
  -- the full provider envelope for every getter would not create a boundary.
  if M.is_ordinary(record) then return record.compilation_snapshot.provider_inputs end
  M.assert_compilation_input(record)
  return record.compilation_snapshot.provider_inputs
end

function M.effect_target_inventory(record)
  if M.is_ordinary(record) then return record.compilation_snapshot.effect_target_inventory end
  M.assert_compilation_input(record)
  return record.compilation_snapshot.effect_target_inventory
end

function M.compilation_identity(record)
  if M.is_ordinary(record) then return record.compilation_semantic_fingerprint end
  M.assert_compilation_input(record)
  return record.compilation_snapshot_fingerprint
end

local function public_identity_domain_material(domain)
  return {
    schema = domain.schema,
    kind = domain.kind,
    compiler_input_fingerprint = domain.compiler_input_fingerprint
  }
end

-- Public support/evidence must label whether this identifier names the legacy
-- full schema-2 CompilerInput or the private ordinary semantic input.  The
-- label is additive and self-fingerprinted; it never manufactures a missing
-- full snapshot hash for an ordinary stage.
function M.public_identity_domain(record)
  M.assert_publication_input(record)
  local domain = {
    schema = 1,
    kind = M.is_ordinary(record) and "ordinary-semantic-v1" or "full-schema2-v1",
    compiler_input_fingerprint = record.input_fingerprint
  }
  domain.identity_domain_fingerprint = fingerprint.of(public_identity_domain_material(domain))
  return domain
end

function M.verify_public_identity_domain(domain, expected_fingerprint, options)
  options = options or {}
  if domain == nil then
    if options.allow_legacy_full == true then return "full-schema2-v1" end
    error("Compiler public identity domain is required for newly emitted evidence.", 2)
  end
  if type(domain) ~= "table" or domain.schema ~= 1
    or (domain.kind ~= "full-schema2-v1" and domain.kind ~= "ordinary-semantic-v1")
    or type(domain.compiler_input_fingerprint) ~= "string" or domain.compiler_input_fingerprint == ""
    or (expected_fingerprint ~= nil and domain.compiler_input_fingerprint ~= expected_fingerprint)
    or domain.identity_domain_fingerprint ~= fingerprint.of(public_identity_domain_material(domain)) then
    error("Compiler public identity domain is invalid.", 2)
  end
  return domain.kind
end

function M.compatibility_projection(record, generation_plan_fingerprint)
  M.assert_publication_input(record)
  local environment = environment_identity.compatibility_projection(record.runtime_environment)
  local out = {
    schema = 1,
    record_type = "CompilerInput",
    source_fingerprints = deepcopy(record.source_fingerprints),
    environment_identity = environment,
    environment_fingerprint = environment.environment_fingerprint,
    target_profile_fingerprint = record.runtime_environment.target_profile_fingerprint,
    generation_plan_fingerprint = generation_plan_fingerprint or record.compilation_snapshot_fingerprint,
    input_sanitation_fingerprint = record.input_sanitation_fingerprint,
    authoritative_input_fingerprint = record.input_fingerprint
  }
  local fp_material = deepcopy(out)
  fp_material.input_fingerprint = nil
  out.input_fingerprint = fingerprint.of(fp_material)
  return out
end

function M.snapshot(record)
  if M.is_ordinary(record) then
    error("Ordinary CompilerInput has no export snapshot; request full collection before emission.", 2)
  end
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  authority.count_snapshot()
  authority.count_full_copy()
  local out = deepcopy(record)
  out.compilation_snapshot = compilation_snapshot.snapshot(record.compilation_snapshot)
  return out
end

return M
