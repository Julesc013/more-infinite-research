-- Generated MIR Extension Protocol V0 preview structural validator.
local M = {}
local kinds = {CompatibilityFragment=true,ProfileFragment=true,ProofFragment=true,PresentationFragment=true,CapabilityRequirement=true,ExtensionDependency=true,ExtensionConflict=true,FinalizationRequirement=true}
local forbidden = {callback=true,callbacks=true,compiler_context=true,data_raw=true,executor=true,prototype=true,prototype_write=true,safety_kernel=true}
local function scan(v)
  if type(v) ~= 'table' then return true end
  for k,item in pairs(v) do if forbidden[k] then return nil,'mir4-mep-forbidden-field' end; local ok,err=scan(item); if not ok then return nil,err end end
  return true
end
function M.validate(v)
  if type(v)~='table' or v.kind~='MIR4ExtensionEnvelopeV0' or v.schema~=0 or type(v.fragments)~='table' or #v.fragments<1 then return nil,'mir4-mep-schema' end
  local seen={}; for _,f in ipairs(v.fragments) do if type(f)~='table' or not kinds[f.kind] or type(f.id)~='string' or seen[f.id] or type(f.data)~='table' then return nil,'mir4-mep-schema' end; seen[f.id]=true end
  return scan(v)
end
return M