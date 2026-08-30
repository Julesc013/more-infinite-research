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
local function sorted_keys(value)
  local out = {}; for key, _ in pairs(value or {}) do out[#out + 1] = key end
  table.sort(out); return out
end
function M.discover_mod_data(mod_data, host_present)
  local result = {status=host_present and 'discovered' or 'host-absent-inert',records={},diagnostics={},mutation_authorized=false,prototype_write_authorized=false}
  if not host_present then return result end
  local by_id, namespaces, edges = {}, {}, {}
  for _, name in ipairs(sorted_keys(mod_data)) do
    local prototype = mod_data[name]
    if type(prototype) == 'table' and prototype.data_type == 'more-infinite-research.extension.v1' then
      local envelope = prototype.data
      local ok, err = M.validate(envelope)
      if not ok then result.status='quarantined';result.diagnostics[#result.diagnostics+1]=err
      elseif by_id[envelope.extension_id] or namespaces[envelope.namespace] then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-duplicate-extension'
      else
        by_id[envelope.extension_id]=envelope;namespaces[envelope.namespace]=envelope.extension_id;edges[envelope.extension_id]={}
        result.records[#result.records+1]={prototype_name=name,extension_id=envelope.extension_id,status='validated'}
      end
    end
  end
  if result.status == 'quarantined' then return result end
  for id, envelope in pairs(by_id) do
    for _, fragment in ipairs(envelope.fragments) do
      if fragment.kind == 'ExtensionDependency' and fragment.data.extension_id ~= 'org.more-infinite-research.platform' then
        local dependency=fragment.data.extension_id
        if not by_id[dependency] then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-missing-dependency';return result end
        edges[id][#edges[id]+1]=dependency
      elseif fragment.kind == 'ExtensionConflict' then
        for _, conflict in ipairs(fragment.data.extension_ids or {}) do
          if by_id[conflict] then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-conflict';return result end
        end
      end
    end
  end
  local remaining, order = {}, {}
  for id, dependencies in pairs(edges) do remaining[id]=dependencies end
  while next(remaining) do
    local ready={};for id, dependencies in pairs(remaining) do if #dependencies==0 then ready[#ready+1]=id end end;table.sort(ready)
    if #ready==0 then result.status='quarantined';result.diagnostics[#result.diagnostics+1]='mir4-mep-v1-dependency-cycle';return result end
    for _, id in ipairs(ready) do
      order[#order+1]=id;remaining[id]=nil
      for _, dependencies in pairs(remaining) do for index=#dependencies,1,-1 do if dependencies[index]==id then table.remove(dependencies,index) end end end
    end
  end
  result.order=order;return result
end
return M