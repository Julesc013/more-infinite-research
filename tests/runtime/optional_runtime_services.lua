-- Optional experiments only. This file is never bound into a player package.
local M = {}
function M.attach_car(entity, factor)
  if not (entity and entity.valid and entity.type == "car") or factor < 0.5 or factor > 1 then return nil end
  local record = {entity=entity, consumption=entity.consumption_modifier, effectivity=entity.effectivity_modifier,
    force=entity.force.index, surface=entity.surface.index}
  record.applied_consumption=record.consumption*factor
  record.applied_effectivity=record.effectivity/factor
  entity.consumption_modifier=record.applied_consumption
  entity.effectivity_modifier=record.applied_effectivity
  return record
end
function M.detach_car(record)
  local entity=record.entity
  if not entity.valid then return true end
  local clean=true
  if math.abs(entity.consumption_modifier-record.applied_consumption)<0.00001 then entity.consumption_modifier=record.consumption else clean=false end
  if math.abs(entity.effectivity_modifier-record.applied_effectivity)<0.00001 then entity.effectivity_modifier=record.effectivity else clean=false end
  return clean
end
function M.car_lifecycle(record)
  local e=record.entity
  if not e.valid or e.force.index~=record.force or e.surface.index~=record.surface then return M.detach_car(record), "detached" end
  if math.abs(e.consumption_modifier-record.applied_consumption)>0.00001 or math.abs(e.effectivity_modifier-record.applied_effectivity)>0.00001 then
    M.detach_car(record); return false, "external-conflict"
  end
  return true, "active"
end
function M.maintenance(schedule)
  local service={queue={},members={},limit=256,budget=8,cooldown=600,active=false,enabled=false,processed=0}
  local function active(value)
    if service.active~=value then service.active=value; schedule(value) end
  end
  function service.enable(value)
    service.enabled=value
    if not value then service.queue={}; service.members={}; active(false) end
  end
  function service.damage(entity,tick)
    if not service.enabled or not entity.valid or (entity.type~="wall" and entity.type~="gate") or not entity.unit_number then return false end
    local old=service.members[entity.unit_number]
    if old then old.deadline=tick+service.cooldown; return true end
    if #service.queue>=service.limit then return false end
    local row={entity=entity,id=entity.unit_number,force=entity.force.index,surface=entity.surface.index,deadline=tick+service.cooldown}
    service.members[row.id]=row; service.queue[#service.queue+1]=row; active(true); return true
  end
  function service.step(tick)
    local processed=0
    for _=1,math.min(service.budget,#service.queue) do
      local row=table.remove(service.queue,1); local e=row.entity; processed=processed+1
      if e.valid and e.force.index==row.force and e.surface.index==row.surface and e.get_health_ratio()<1 then
        if tick>=row.deadline then e.health=e.health+math.min(1,e.prototype.get_max_health(e.quality)-e.health) end
        if e.get_health_ratio()<1 then service.queue[#service.queue+1]=row else service.members[row.id]=nil end
      else service.members[row.id]=nil end
    end
    service.processed=service.processed+processed
    active(#service.queue>0); return processed
  end
  return service
end
return M
