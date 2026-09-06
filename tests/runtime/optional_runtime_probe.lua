local probe=require("optional_runtime_services")
local assertions=0
local function check(ok,why) assert(ok,why); assertions=assertions+1 end
local function energy(car)
  return car.get_fuel_inventory().get_item_count("coal")*4000000+car.burner.remaining_burning_fuel
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
    helpers.write_file("optional-probe.json",helpers.table_to_json{status="passed",assertions=assertions,engine=helpers.game_version,control_energy=used_a,economy_energy=used_b,ratio=used_b/used_a,travel=math.abs(a.position.y),speed=a.speed,scope="package-excluded-Car-and-maintenance-prototypes; no-multiplayer-or-save-migration-qualification"},false)
    script.on_nth_tick(1,nil)
  end
end)
