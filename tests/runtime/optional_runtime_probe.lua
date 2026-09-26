local probe=require("optional_runtime_services")
local passive_repair=require("prototypes.mir.runtime.effects.passive_repair")
local assertions=0
local function check(ok,why) assert(ok,why); assertions=assertions+1 end
local function energy(car)
  return car.get_fuel_inventory().get_item_count("coal")*4000000+car.burner.remaining_burning_fuel
end
local function entity_max_health(entity)
  return entity.prototype.get_max_health(entity.quality)
end
local function stored_functions(value,seen)
  if type(value)=="function" then return true end
  if type(value)~="table" then return false end
  seen=seen or {};if seen[value] then return false end;seen[value]=true
  for key,entry in pairs(value) do
    if type(key)=="function" or stored_functions(entry,seen) then return true end
  end
  return false
end
local function passive_repair_checks(surface,tick)
  local function wall(x,y)
    return surface.create_entity{name="stone-wall",position={x,y},force="player"}
  end
  local function track_damage(entity,at)
    return passive_repair.on_entity_damaged{entity=entity,tick=at or tick}
  end

  storage.mir=nil;storage.mir_test_passive_repair_enabled=false
  check(passive_repair.register(),"passive repair registers only through its explicit host hook")
  passive_repair.on_init(nil);passive_repair.on_load()
  local disabled=wall(-20,5);disabled.health=disabled.health-1
  check(not track_damage(disabled) and storage.mir==nil,"passive repair remains inert by default and load creates no state")

  storage.mir_test_passive_repair_enabled=true
  check(passive_repair.register(),"passive repair refreshes its filtered damage handler after enabling")
  local first=wall(-18,5);local second=wall(-16,5)
  first.health=entity_max_health(first)-1;second.health=entity_max_health(second)-1
  check(track_damage(first) and track_damage(second),"walls enter the persisted repair queue")
  local data=storage.mir.passive_repair
  check(type(data.queue)=="table" and type(data.members)=="table" and #data.queue==2 and data.scheduled==true,"passive repair persists bounded queue state and subscribes on demand")
  check(passive_repair.on_nth_tick({tick=tick+599})==2 and first.health<entity_max_health(first) and second.health<entity_max_health(second),"passive repair observes initial quiet time")
  check(track_damage(first,tick+500),"interleaved damage renews the first wall quiet time")
  passive_repair.on_nth_tick({tick=tick+601})
  check(first.health<entity_max_health(first) and second.health==entity_max_health(second),"interleaved damage delays only its renewed wall")
  passive_repair.on_nth_tick({tick=tick+1201})
  check(first.health==entity_max_health(first) and #data.queue==0 and data.scheduled==false,"one HP repair clamps current quality maximum and unsubscribes when empty")

  local paced=wall(-14,5);paced.health=entity_max_health(paced)-3;check(track_damage(paced,tick+1300),"paced repair witness admitted")
  passive_repair.on_nth_tick({tick=tick+1900});local once=paced.health
  passive_repair.on_nth_tick({tick=tick+1901});local before_interval=paced.health
  passive_repair.on_nth_tick({tick=tick+1960})
  check(once==entity_max_health(paced)-2 and before_interval==once and paced.health==once+1,"passive repair grants at most one HP each sixty ticks")
  paced.health=entity_max_health(paced);passive_repair.on_nth_tick({tick=tick+1961})

  local healed=wall(-12,5);healed.health=entity_max_health(healed)-2;check(track_damage(healed,tick+2000),"other-healer witness admitted")
  healed.health=entity_max_health(healed);passive_repair.on_nth_tick({tick=tick+2600})
  check(data.members[healed.unit_number]==nil,"other healer full-health record is dropped")

  local transferred=wall(-10,5);transferred.health=transferred.health-1;check(track_damage(transferred,tick+2601),"force transfer witness admitted")
  transferred.force=game.forces.enemy;passive_repair.on_nth_tick({tick=tick+2602})
  check(data.members[transferred.unit_number]==nil,"force-transferred record is dropped")

  local other_surface=game.create_surface("mir-passive-repair-other",{width=32,height=32,autoplace_settings={entity={treat_missing_as_default=false},decorative={treat_missing_as_default=false}}})
  local moved=wall(-8,5);moved.health=moved.health-1;check(track_damage(moved,tick+2603),"stale surface guard witness admitted")
  data.members[moved.unit_number].surface_index=other_surface.index
  passive_repair.on_nth_tick({tick=tick+2604})
  check(data.members[moved.unit_number]==nil,"stale persisted surface identity record is dropped without healing")

  local deleted=wall(-6,5);deleted.health=deleted.health-1;check(track_damage(deleted,tick+2605),"deletion witness admitted")
  local deleted_id=deleted.unit_number;deleted.destroy();passive_repair.on_nth_tick({tick=tick+2606})
  check(data.members[deleted_id]==nil,"deleted record is dropped without revival")
  local chest=surface.create_entity{name="steel-chest",position={-4,5},force="player"}
  check(not passive_repair.on_entity_damaged{entity=chest,tick=tick},"passive repair excludes non-wall and non-gate entities")
  local enemy=surface.create_entity{name="stone-wall",position={-2,5},force="enemy"};enemy.health=enemy.health-1
  check(not passive_repair.on_entity_damaged{entity=enemy,tick=tick},"passive repair excludes enemy walls")
  local hostile_force=game.create_force("mir-passive-repair-hostile")
  local hostile=surface.create_entity{name="stone-wall",position={4,5},force=hostile_force};hostile.health=hostile.health-1
  check(not passive_repair.on_entity_damaged{entity=hostile,tick=tick},"passive repair excludes unaffiliated custom hostile walls")
  local zero=wall(0,5);zero.health=0
  check(not passive_repair.on_entity_damaged{entity=zero,tick=tick},"zero-health walls are never queued for revival")
  local ally_force=game.create_force("mir-passive-repair-ally")
  game.forces.player.set_friend(ally_force,true);ally_force.set_friend(game.forces.player,true)
  local allied=surface.create_entity{name="stone-wall",position={6,5},force=ally_force};allied.health=allied.health-1
  check(track_damage(allied,tick+2607),"passive repair admits reciprocally allied player walls")
  allied.health=entity_max_health(allied);passive_repair.on_nth_tick({tick=tick+2608})
  check(data.members[allied.unit_number]==nil,"full reciprocal ally wall is removed from the queue")
  local gate=surface.create_entity{name="gate",position={2,5},force="player"};gate.health=gate.health-1
  check(track_damage(gate,tick+2607),"passive repair admits player gates")
  gate.health=entity_max_health(gate);passive_repair.on_nth_tick({tick=tick+2609})
  check(data.members[gate.unit_number]==nil,"full gate is removed from the queue")

  for index=1,257 do
    local x=(index%32)*2;local y=20+math.floor(index/32)*2
    local entity=wall(x,y);entity.health=entity.health-1
    check(passive_repair.on_entity_damaged{entity=entity,tick=tick+2700}==(index<=256),"passive repair queue cap "..index)
  end
  check(#data.queue==256 and passive_repair.on_nth_tick({tick=tick+2701})==8 and #data.queue==256,"passive repair processes eight pending records round-robin per tick")

  local state_before=data;local queued_before=#data.queue;local scheduled_before=data.scheduled
  passive_repair.on_load()
  check(storage.mir.passive_repair==state_before and #storage.mir.passive_repair.queue==queued_before and data.scheduled==scheduled_before,"load-handler read-only check preserves the persisted queue")
  check(not stored_functions(storage.mir.passive_repair),"passive repair persists no functions")

  storage.mir_test_passive_repair_enabled=false
  passive_repair.on_configuration_changed(nil)
  check(#data.queue==0 and next(data.members)==nil and data.scheduled==false and passive_repair.on_nth_tick({tick=tick+2702})==0,"disabled lifecycle clears pending work without idle scans")
end
script.on_nth_tick(1,function(event)
  if not storage.started then
    storage.started=true
    local surface=game.create_surface("mir-optional-probe",{width=128,height=512,autoplace_settings={entity={treat_missing_as_default=false},decorative={treat_missing_as_default=false}}})
    surface.request_to_generate_chunks({0,0},2); surface.force_generate_chunk_requests()
    local tiles={};for x=-12,12 do for y=-160,15 do tiles[#tiles+1]={name="refined-concrete",position={x,y}} end end
    surface.set_tiles(tiles)
    local function car(x)
      local c=surface.create_entity{name="car",position={x,0},force="player"}
      c.insert{name="coal",count=50}
      c.set_driver(surface.create_entity{name="character",position={x,0},force="player"})
      c.riding_state={acceleration=defines.riding.acceleration.accelerating,direction=defines.riding.direction.straight}
      return c
    end
    storage.control=car(-4);storage.economy=car(4)
    passive_repair_checks(surface,event.tick)
    storage.contribution=probe.attach_car(storage.economy,0.8)
    check(storage.contribution~=nil,"Car setters admitted")
    storage.control_energy=energy(storage.control);storage.economy_energy=energy(storage.economy)
    local scheduled={}; local service=probe.maintenance(function(value) scheduled[#scheduled+1]=value end)
    check(not service.active and service.processed==0,"disabled idle")
    local wall=surface.create_entity{name="stone-wall",position={10,5},force="player"}
    wall.health=wall.health-10
    check(not service.damage(wall,event.tick),"disabled negative")
    service.enable(true);check(service.damage(wall,event.tick),"damage admission")
    local initial=wall.health;check(service.step(event.tick+599)<=8 and wall.health==initial,"combat cooldown")
    check(service.damage(wall,event.tick+500),"repeat damage cooldown")
    service.step(event.tick+700);check(wall.health==initial,"renewed combat cooldown")
    service.step(event.tick+1100);check(wall.health==initial+1,"bounded post-combat repair")
    wall.force=game.forces.enemy;service.step(event.tick+1200)
    check(not service.active and #service.queue==0,"force change removal")
    wall.force=game.forces.player;service.damage(wall,event.tick);wall.destroy();service.step(event.tick+1200)
    check(not service.active,"entity removal")
    for i=1,257 do
      local e={valid=true,type="wall",unit_number=10000+i,force={index=1},surface={index=1},health=10,get_health_ratio=function() return 0.5 end}
      check(service.damage(e,event.tick)==(i<=256),"queue cap")
    end
    check(service.step(event.tick+1)==8 and #service.queue==256,"per-step work cap")
    service.enable(false);check(not service.active and #service.queue==0,"disable removes queue and scheduler")
    storage.maintenance_assertions=assertions
  elseif event.tick>=241 then
    local a,b=storage.control,storage.economy
    local used_a=storage.control_energy-energy(a); local used_b=storage.economy_energy-energy(b)
    check(used_a>0 and used_b>0,"burner fuel consumed")
    check(a.speed>0.1 and math.abs(a.position.y)>30,"moving vehicles positive control")
    check(math.abs(a.speed-b.speed)<0.0001 and math.abs(a.position.y-b.position.y)<0.02,"same acceleration and distance")
    check(math.abs(used_b/used_a-0.8)<0.01,"20 percent fuel reduction")
    check(probe.detach_car(storage.contribution),"clean contribution removal")
    check(b.consumption_modifier==1 and b.effectivity_modifier==1,"original setters restored")
    local conflict=probe.attach_car(b,0.8); b.consumption_modifier=0.7
    local ok,reason=probe.car_lifecycle(conflict)
    check(not ok and reason=="external-conflict" and math.abs(b.consumption_modifier-0.7)<0.0001 and b.effectivity_modifier==1,"external modifier preserved")
    b.consumption_modifier=1;local lifecycle=probe.attach_car(b,0.8);b.force=game.forces.enemy
    local clean,status=probe.car_lifecycle(lifecycle);check(clean and status=="detached" and b.effectivity_modifier==1,"Car force lifecycle")
    local dead=probe.attach_car(b,0.8);b.destroy();check(probe.detach_car(dead),"Car destruction")
    helpers.write_file("optional-probe.json",helpers.table_to_json{status="passed",assertions=assertions,engine=helpers.game_version,control_energy=used_a,economy_energy=used_b,ratio=used_b/used_a,travel=math.abs(a.position.y),speed=a.speed,scope="package-excluded-Car-and-maintenance-prototypes-plus-controlled-passive-repair-service-with-stubbed-startup-and-runtime-state-facades-and-native-LuaEntity-references-plus-scalar-identity-and-deadline-values; not-materialized-host-callback-settings-or-save-reload-acceptance"},false)
    script.on_nth_tick(1,nil)
  end
end)
