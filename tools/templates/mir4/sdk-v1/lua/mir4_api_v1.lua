-- MIR 4 API V1 package-excluded preview. Digest/archive I/O use explicit host ports.
local M = {}
local surfaces = {['continuity-bundle']=true,['host-manifest']=true,observation=true,profile=true,proof=true,query=true,release=true,['target-provider-abi']=true,tooling=true}
local required = {availability=true,canonicalization=true,capabilities=true,digest=true,extensions=true,items=true,kind=true,mutation_authorized=true,package_visible=true,page=true,public_support_claim=true,schema=true,source_identity=true,surface=true,target=true,versions=true}
local function fail(code) return nil, code end
local function count_keys(v) local n=0 for _ in pairs(v) do n=n+1 end return n end
local function sorted_unique(values)
  local previous=nil
  for _,value in ipairs(values) do if type(value)~='string' or (previous and previous>=value) then return false end previous=value end
  return true
end
function M.parse(raw_json, decode)
  if type(decode)~='function' then return fail('mir4-sdk-json-decoder-required') end
  local ok,value=pcall(decode,raw_json);if not ok or type(value)~='table' then return fail('mir4-canon-invalid-json') end
  return value
end
function M.canonicalize(value, encode)
  if type(encode)~='function' then return fail('mir4-sdk-canonical-encoder-required') end
  local ok,result=pcall(encode,value);if not ok then return fail('mir4-canon-invalid-json') end
  return result
end
function M.digest(value, canonicalize, sha256)
  if type(canonicalize)~='function' or type(sha256)~='function' then return fail('mir4-sdk-digest-port-required') end
  local material={} for key,child in pairs(value) do if key~='digest' then material[key]=child end end
  local bytes,err=canonicalize(material);if not bytes then return nil,err end
  return 'sha256:'..sha256('mir-canonical-json/1\0mir4:api-response-v1\0'..bytes)
end
function M.validate(v, digest_port)
  if type(v)~='table' or count_keys(v)~=17 then return fail('mir4-api-v1-schema') end
  for key in pairs(v) do if not required[key] then return fail('mir4-api-v1-schema') end end
  if v.kind~='MIR4ApiResponseV1' or v.schema~=1 or not surfaces[v.surface] then return fail('mir4-api-v1-schema') end
  if type(v.target)~='table' or type(v.target.id)~='string' or not string.match(v.target.id,'^f%d%d%d$') or type(v.target.factorio_line)~='string' or not string.match(v.target.factorio_line,'^%d+%.%d+$') or type(v.target.transport)~='string' or v.target.transport=='' then return fail('mir4-api-v1-target') end
  if type(v.versions)~='table' or type(v.versions.source)~='string' or v.versions.source=='' or type(v.versions.distribution)~='string' or v.versions.distribution=='' then return fail('mir4-api-v1-version') end
  if v.canonicalization~='mir-canonical-json/1' then return fail('mir4-api-v1-canonicalization') end
  if v.package_visible~=false or v.mutation_authorized~=false or v.public_support_claim~=false then return fail('mir4-api-v1-authority-boundary') end
  if type(v.capabilities)~='table' or #v.capabilities>128 or not sorted_unique(v.capabilities) then return fail('mir4-api-v1-capability-order') end
  if type(v.availability)~='table' or (v.availability.status~='available' and v.availability.status~='unavailable') or type(v.availability.reason)~='string' or v.availability.reason=='' or type(v.availability.evidence)~='table' or not sorted_unique(v.availability.evidence) then return fail('mir4-api-v1-availability') end
  if type(v.page)~='table' or type(v.items)~='table' or type(v.page.offset)~='number' or type(v.page.limit)~='number' or type(v.page.returned)~='number' or v.page.offset<0 or v.page.limit<1 or v.page.limit>128 or v.page.returned~=#v.items then return fail('mir4-api-v1-page') end
  if v.page.next_cursor~=nil and (type(v.page.next_cursor)~='string' or not string.match(v.page.next_cursor,'^%d+$')) then return fail('mir4-api-v1-cursor') end
  if v.availability.status=='unavailable' and (v.page.total~=nil or v.page.returned~=0 or #v.items~=0 or v.page.next_cursor~=nil) then return fail('mir4-api-v1-unavailable-is-not-zero') end
  if type(v.extensions)~='table' or count_keys(v.extensions)>32 then return fail('mir4-api-v1-extension-cardinality') end
  if digest_port then local expected,err=digest_port(v);if not expected then return nil,err end;if v.digest~=expected then return fail('mir4-api-v1-digest') end end
  return v
end
function M.negotiate_capabilities(v,requested,required,digest_port)
  local ok,err=M.validate(v,digest_port);if not ok then return nil,err end
  local offered={} for _,item in ipairs(v.capabilities) do offered[item]=true end
  local selected={} for _,item in ipairs(requested or v.capabilities) do if offered[item] then selected[#selected+1]=item end end
  for _,item in ipairs(required or {}) do if not offered[item] then return fail('mir4-api-v1-capability-required') end end
  table.sort(selected);return {offered=v.capabilities,selected=selected,missing={}}
end
function M.decode_availability(v,digest_port) local ok,err=M.validate(v,digest_port);if not ok then return nil,err end;return {available=v.availability.status=='available',status=v.availability.status,reason=v.availability.reason,evidence=v.availability.evidence} end
function M.bounded_page(v,expected_cursor,digest_port) local ok,err=M.validate(v,digest_port);if not ok then return nil,err end;if expected_cursor and expected_cursor~=tostring(v.page.offset) then return fail('mir4-api-v1-cursor-mismatch') end;return {items=v.items,offset=v.page.offset,limit=v.page.limit,returned=v.page.returned,total=v.page.total,next_cursor=v.page.next_cursor} end
function M.compare_snapshots(a,b,digest_port) local left,e=M.validate(a,digest_port);if not left then return nil,e end;local right,e2=M.validate(b,digest_port);if not right then return nil,e2 end;if a.surface~=b.surface or a.target.id~=b.target.id then return fail('mir4-api-v1-snapshot-identity') end;return {equal=a.digest==b.digest,before_digest=a.digest,after_digest=b.digest,items_changed=a.digest~=b.digest} end
function M.render_diagnostic(diagnostic,registry) for _,row in ipairs(registry.diagnostics or {}) do if row.code==diagnostic.code then return '['..row.code..'] '..(diagnostic.path or '$')..' '..(diagnostic.message or '') end end return fail('mir4-api-v1-diagnostic-code') end
function M.validate_extension(extension,digest_port)
  local forbidden={callback=true,callbacks=true,compiler_context=true,data_raw=true,executor=true,prototype=true,prototype_write=true,safety_kernel=true,safety_kernel_override=true}
  local function scan(value) if type(value)=='table' then for key,child in pairs(value) do if forbidden[key] then return false end;if not scan(child) then return false end end end return true end
  if type(extension)~='table' or extension.kind~='MIR4ExtensionEnvelopeV1' or extension.schema~=1 or extension.canonicalization~='mir-canonical-json/1' then return fail('mir4-mep-v1-schema') end
  if not scan(extension) then return fail('mir4-mep-v1-forbidden-field') end
  if digest_port and extension.digest~=digest_port(extension) then return fail('mir4-mep-v1-digest') end
  return extension
end
function M.verify_manifest(manifest,read_bytes,sha256)
  if type(manifest)~='table' or type(manifest.files)~='table' or #manifest.files==0 then return fail('mir4-api-v1-manifest-empty') end
  local seen={} for _,row in ipairs(manifest.files) do local path=row.path;if type(path)~='string' or path=='' or string.sub(path,1,1)=='/' or string.find(path,'..',1,true) or string.find(path,':',1,true) or seen[path] then return fail('mir4-api-v1-manifest-path') end;seen[path]=true;local bytes=read_bytes(path);if not bytes or #bytes~=row.bytes or sha256(bytes)~=row.sha256 then return fail('mir4-api-v1-manifest-digest') end end
  return true
end
function M.verify_archive(manifest,read_entry,sha256) return M.verify_manifest(manifest,read_entry,sha256) end
return M
