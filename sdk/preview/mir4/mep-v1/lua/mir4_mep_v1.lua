-- Generated package-excluded MIR Extension Protocol V1 preview helper.
local M = {}
local fragment_kinds = {
  CompatibilityFragment=true,ProfileFragment=true,ProofFragment=true,PresentationFragment=true,
  CapabilityRequirement=true,ExtensionDependency=true,ExtensionConflict=true,FinalizationRequirement=true,
  ProcessClassificationFragment=true,MigrationFragment=true,TargetDispositionFragment=true,ExternalEffectChannelDeclaration=true
}
local forbidden = {callback=true,callbacks=true,compiler_context=true,data_raw=true,executor=true,prototype=true,prototype_write=true,safety_kernel=true,safety_kernel_override=true}
local function scan(value)
  if type(value) ~= 'table' then return true end
  for key, child in pairs(value) do
    if forbidden[key] then return nil, 'mir4-mep-v1-forbidden-field' end
    local ok, err = scan(child); if not ok then return nil, err end
  end
  return true
end
function M.validate(value)
  if type(value) ~= 'table' or value.kind ~= 'MIR4ExtensionEnvelopeV1' or value.schema ~= 1 then return nil, 'mir4-mep-v1-schema' end
  if type(value.extension_id) ~= 'string' or type(value.extension_version) ~= 'string' or type(value.namespace) ~= 'string' then return nil, 'mir4-mep-v1-schema' end
  if type(value.targets) ~= 'table' or #value.targets < 1 or #value.targets > 17 or type(value.fragments) ~= 'table' or #value.fragments < 1 or #value.fragments > 64 then return nil, 'mir4-mep-v1-cardinality' end
  local ids = {}
  for _, fragment in ipairs(value.fragments) do
    if type(fragment) ~= 'table' or not fragment_kinds[fragment.kind] or ids[fragment.id] then return nil, 'mir4-mep-v1-fragment' end
    ids[fragment.id] = true
  end
  return scan(value)
end
function M.build(value) local ok, err=M.validate(value);if not ok then return nil,err end;return value end
return M