-- Execute only in the actual published MIR mod context through the existing
-- governed RCON controller, before admitting the successor. Never require,
-- repair, seed or synthesize MIR state. An absent/adverse row is evidence.
assert(script.active_mods.base=="2.1.23"
  and script.active_mods["more-infinite-research"]=="4.7.21003","published source context differs")
local mir=storage.mir
local bucket=type(mir)=="table" and mir.maximum_level_control
local managed=type(bucket)=="table" and bucket.managed_technologies
local row=type(managed)=="table" and managed["research-speed-8"]
local function copy(value,depth)
  if type(value)~="table" then
    assert(value==nil or type(value)=="boolean" or type(value)=="number" or type(value)=="string","nonplain producer field")
    return value
  end
  assert(depth<6,"producer row unexpectedly deep")
  local out={};local count=0
  for key,item in pairs(value) do
    count=count+1;assert(count<=64 and (type(key)=="string" or type(key)=="number"),"producer row unexpectedly broad")
    out[key]=copy(item,depth+1)
  end
  return out
end
local out={kind="MIRFiniteResearchSpeedActualPublishedProducerV1",tick=game.tick,
  active_mods=copy(script.active_mods,0),startup={},row_present=type(row)=="table",
  policy_version=type(bucket)=="table" and bucket.policy_version or false,
  managed_eight=type(row)=="table" and copy(row,0) or false,
  seven_history=prototypes.get_history("technology","research-speed-7"),
  eight_history=prototypes.get_history("technology","research-speed-8"),
  scope="Actual published mod-context read only; native/save/controller/hash readback remains caller custody."}
for name,value in pairs(settings.startup) do out.startup[name]=value.value end
helpers.write_file("mir-finite-source-producer.json",helpers.table_to_json(out),false)
rcon.print("[MIR_FINITE_SOURCE_PRODUCER] mir-finite-source-producer.json")
