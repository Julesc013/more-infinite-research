-- Private native control for one bounded fixed-provider removal chain.
-- It records native provider disappearance separately from retained MIR state.
local KEY='mir5_fixed_provider_removal_control'
local CASE='f200-fixed-provider-removal-control'
local FIXTURE='mir-fixture-mir5-fixed-provider-removal-control'
local SAVE='mir5-native-complete'
local UINT32_MAX=4294967295
local DEADLINE=60*60*10
local PLAYER_CURRENT='braking-force-1'
local PLAYER_TAIL='laser-shooting-speed-1'
local FOREIGN_CURRENT='electric-circuit-productivity'
local FOREIGN_TAIL='braking-force-1'
local FOREIGN_DISABLED='basic-plate-productivity'
local MIR_BIOFLUX='recipe-prod-research_bioflux-1'
local MIR_BREEDING='recipe-prod-research_breeding-1'
local POSITIVE='mir-native-credit-research_breeding-fish-breeding-positive'
local NEGATIVE='mir-native-credit-research_breeding-fish-breeding-negative'
local SOURCE_BIOFLUX='bioflux-productivity'
local SOURCE_FISH='fish-breeding-productivity'
local FOREIGN_FORCE='mir5-fixed-provider-removal-engine-observer'
local loaded_snapshot,reload_logged,pending_save=nil,false,false

local function fail(message) error('[mir5-fixed-provider-removal-control] '..message) end
local function close(actual, expected) return type(actual)=='number' and type(expected)=='number' and math.abs(actual-expected)<=.000001 end
local function technology(force, name)
  local value=force and force.technologies[name]
  if value==nil or value.valid==false or value.name~=name then fail('technology is absent: '..tostring(name)) end
  return value
end
local function optional(force,name)
  local value=force and force.technologies[name]
  return value~=nil and value.valid~=false and value or nil
end
local function require_mode(mir,fixture,preference,providers,label)
  local active=script.active_mods
  if active.base~='2.0.77' or active['space-age']~='2.0.77' or active['more-infinite-research']~=mir or active[FIXTURE]~=fixture then
    fail(label..' fixture closure differs')
  end
  local present=active['plates-n-circuit-productivity']~=nil or active.Science_packs_productivity~=nil
    or active['bioflux-productivity']~=nil or active['fish-productivity']~=nil
  if providers then
    if active['plates-n-circuit-productivity']~='0.0.2' or active.Science_packs_productivity~='0.0.1'
      or active['bioflux-productivity']~='0.1.0' or active['fish-productivity']~='1.0.0' then fail(label..' provider closure differs') end
  elseif present then fail(label..' unexpectedly retains a provider') end
  local setting=settings.startup['mir-prefer-this-mod-for-competing-techs']
  if setting==nil or setting.value~=preference then fail(label..' preference differs') end
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function status(force,name)
  local value=technology(force,name)
  return {level=value.level,researched=value.researched,enabled=value.enabled,visible=value.visible_when_disabled,
    maximum=value.prototype.max_level,saved=value.saved_progress}
end
local function assert_status(force,name,wanted,label)
  local actual=status(force,name)
  if actual.level~=wanted.level or actual.researched~=wanted.researched or actual.enabled~=wanted.enabled
    or actual.visible~=wanted.visible or actual.maximum~=wanted.maximum or not close(actual.saved,wanted.saved) then
    fail(label..' status differs: '..name..' level='..tostring(actual.level)..' enabled='..tostring(actual.enabled)
      ..' visible='..tostring(actual.visible)..' saved='..tostring(actual.saved))
  end
  return actual
end
local function queue_snapshot(force)
  local queue={}
  for index,value in ipairs(force.research_queue or {}) do queue[index]=value.name end
  return {current=force.current_research and force.current_research.name or false,queue=queue,progress=force.research_progress}
end
local function copy_queue(value)
  local out={current=value.current,progress=value.progress,queue={}}
  for index,name in ipairs(value.queue or {}) do out.queue[index]=name end
  return out
end
local function assert_queue(force,wanted,label)
  local actual=queue_snapshot(force)
  if actual.current~=wanted.current or #actual.queue~=#wanted.queue or not close(actual.progress,wanted.progress) then
    fail(label..' queue/progress differs')
  end
  for index,name in ipairs(wanted.queue) do if actual.queue[index]~=name then fail(label..' queue changed at '..tostring(index)) end end
  return actual
end
local function recipe_bonus(force,name)
  local value=force.recipes[name]
  if value==nil then fail('recipe is absent: '..name) end
  return value.productivity_bonus
end
local function assert_bonus(force,name,wanted,label)
  local actual=recipe_bonus(force,name)
  if not close(actual,wanted) then fail(label..' productivity differs: '..name..' expected='..tostring(wanted)..' actual='..tostring(actual)) end
end
local function assert_accelerated(value,label)
  if value.research_unit_count~=1 or not close(value.research_unit_energy,60) then fail(label..' is not one-unit one-second') end
end
local function fill(lab,value)
  local inventory=lab.get_inventory(defines.inventory.lab_input)
  if inventory==nil then fail('lab input is absent') end
  inventory.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if inventory.insert{name=ingredient.name,count=100}~=100 then fail('lab science insertion failed: '..ingredient.name) end
  end
  lab.active=true;lab.energy=1000000000
end
local function freeze(state)
  local lab=state.lab
  if lab==nil or lab.valid==false then fail('fixture biolab is absent') end
  lab.active=false;lab.energy=0
  local inventory=lab.get_inventory(defines.inventory.lab_input)
  if inventory==nil then fail('lab input is absent') end
  inventory.clear()
end
local function assert_frozen(state)
  local lab=state.lab
  if lab==nil or lab.valid==false or lab.active~=false or lab.energy~=0 then fail('fixture lab was not frozen') end
end
local function queue_native(force,current,tail,progress,label)
  local current_value,tail_value=technology(force,current),technology(force,tail)
  current_value.saved_progress=progress;tail_value.saved_progress=.42
  force.research_queue={current_value,tail_value};force.research_progress=progress
  return assert_queue(force,{current=current,queue={current,tail},progress=progress},label)
end
local function assert_native_queue(force,current,tail,progress,label)
  assert_queue(force,{current=current,queue={current,tail},progress=progress},label)
  if not close(technology(force,current).saved_progress,0) or not close(technology(force,tail).saved_progress,.42) then
    fail(label..' raw progress differs')
  end
end
local function prepend_mir(state,name,label)
  local player=game.forces.player
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,label..' before')
  local current,tail=technology(player,PLAYER_CURRENT),technology(player,PLAYER_TAIL)
  current.saved_progress=player.research_progress
  player.research_queue={technology(player,name),current,tail}
  assert_queue(player,{current=name,queue={name,PLAYER_CURRENT,PLAYER_TAIL},progress=0},label..' queued')
  if not close(current.saved_progress,.27) or not close(tail.saved_progress,.42) then fail(label..' lost queued investment') end
  fill(state.lab,technology(player,name))
end
local function assert_credit(force,positive,negative,label)
  assert_status(force,POSITIVE,{level=positive,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},label..' positive carrier')
  assert_status(force,NEGATIVE,{level=negative,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},label..' negative carrier')
end
local function assert_source_witness(state)
  if state.source_mir~='4.7.20002' or state.fixture_version~='0.1.0' or state.source_actual_labs~=2
      or state.milestone~='two-native-fixed-provider-labs' then fail('published source witness differs') end
end
local function assert_source(state)
  assert_source_witness(state)
  local player=game.forces.player
  assert_status(player,SOURCE_BIOFLUX,{level=2,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'published bioflux')
  assert_status(player,SOURCE_FISH,{level=2,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'published fish')
  assert_bonus(player,'bioflux',state.bioflux_base+.1,'published bioflux')
  assert_bonus(player,'fish-breeding',state.fish_base+.1,'published fish')
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'published player')
  if type(state.player_queue)~='table' then fail('published player queue witness is absent') end
  assert_frozen(state)
  local foreign=game.forces[state.foreign_force_index]
  if foreign==nil or foreign.valid==false or foreign.name~=FOREIGN_FORCE then fail('engine observer force is absent') end
  assert_queue(foreign,{current=FOREIGN_CURRENT,queue={FOREIGN_CURRENT,FOREIGN_TAIL},progress=.27},'engine observer source')
  assert_status(foreign,FOREIGN_DISABLED,{level=1,researched=false,enabled=false,visible=true,maximum=UINT32_MAX,saved=0},'pre-disabled foreign provider')
  if not close(technology(foreign,FOREIGN_CURRENT).saved_progress,0) or not close(technology(foreign,FOREIGN_TAIL).saved_progress,.42) then fail('engine observer source raw progress differs') end
end
local function assert_earned_source(state,label)
  assert_source_witness(state)
  local player=game.forces.player
  for _, name in ipairs({SOURCE_BIOFLUX,SOURCE_FISH}) do
    local value=technology(player,name)
    if value.level~=2 or value.researched then fail(label..' earned source level changed: '..name) end
  end
  assert_bonus(player,'bioflux',state.bioflux_base+.1,label..' source bioflux')
  assert_bonus(player,'fish-breeding',state.fish_base+.1,label..' source fish')
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,label..' player')
  assert_frozen(state)
end
local function assert_true(state, now_foreign)
  assert_source_witness(state)
  assert_frozen(state)
  local player=game.forces.player
  if state.mir_actual_labs~=2 then fail('preferred MIR actual lab witness differs') end
  assert_status(player,MIR_BIOFLUX,{level=2,researched=false,enabled=not now_foreign,visible=false,maximum=UINT32_MAX,saved=0},'preferred MIR bioflux')
  assert_status(player,MIR_BREEDING,{level=2,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'preferred MIR breeding')
  assert_bonus(player,'bioflux',state.bioflux_base+.2,'preferred MIR bioflux')
  assert_bonus(player,'fish-breeding',state.fish_base+.2,'preferred MIR fish')
  assert_bonus(player,'biter-egg',state.biter_base+.1,'preferred MIR biter egg')
  assert_bonus(player,'pentapod-egg',state.pentapod_base+.1,'preferred MIR pentapod egg')
  assert_credit(player,now_foreign and 2 or 1,1,'preferred MIR')
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'preferred player')
  assert_status(game.forces[state.foreign_force_index],MIR_BIOFLUX,{level=1,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},'pre-disabled foreign MIR bioflux')
  assert_status(game.forces[state.foreign_force_index],FOREIGN_DISABLED,{level=1,researched=false,enabled=false,visible=true,maximum=UINT32_MAX,saved=0},'pre-disabled foreign provider')
end
local function assert_false(state)
  assert_source_witness(state)
  assert_frozen(state)
  local player=game.forces.player
  if state.mir_actual_labs~=3 then fail('foreign-preference MIR actual lab witness differs') end
  assert_status(player,MIR_BIOFLUX,{level=2,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},'foreign MIR bioflux')
  assert_status(player,MIR_BREEDING,{level=3,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'foreign MIR breeding')
  assert_bonus(player,'bioflux',state.bioflux_base+.2,'foreign MIR bioflux')
  assert_bonus(player,'fish-breeding',state.fish_base+.2,'foreign MIR fish')
  assert_bonus(player,'biter-egg',state.biter_base+.2,'foreign MIR biter egg')
  assert_bonus(player,'pentapod-egg',state.pentapod_base+.2,'foreign MIR pentapod egg')
  assert_credit(player,2,1,'foreign MIR')
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'foreign player')
  assert_status(game.forces[state.foreign_force_index],MIR_BIOFLUX,{level=1,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},'foreign pre-disabled MIR bioflux')
  assert_status(game.forces[state.foreign_force_index],FOREIGN_DISABLED,{level=1,researched=false,enabled=false,visible=true,maximum=UINT32_MAX,saved=0},'foreign pre-disabled provider')
end
local function provider_absent(force,name) if optional(force,name)~=nil then fail('removed provider row remains: '..name) end end
local function removed_observation(force)
  local current=force.current_research
  return {provider_present=optional(force,FOREIGN_CURRENT)~=nil,current=current and current.name or false,
    queue=queue_snapshot(force).queue,progress=force.research_progress,tail_present=optional(force,FOREIGN_TAIL)~=nil,
    tail_saved=optional(force,FOREIGN_TAIL) and technology(force,FOREIGN_TAIL).saved_progress or 'absent'}
end
local function assert_removed(state)
  local player=game.forces.player
  provider_absent(player,SOURCE_BIOFLUX);provider_absent(player,SOURCE_FISH)
  provider_absent(game.forces[state.foreign_force_index],FOREIGN_CURRENT);provider_absent(game.forces[state.foreign_force_index],FOREIGN_DISABLED)
  assert_status(player,MIR_BIOFLUX,{level=2,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'provider-absent MIR bioflux')
  assert_status(player,MIR_BREEDING,{level=3,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'provider-absent MIR breeding')
  assert_credit(player,1,2,'provider-absent MIR')
  assert_bonus(player,'bioflux',state.bioflux_base+.1,'provider-absent MIR bioflux')
  assert_bonus(player,'fish-breeding',state.fish_base+.1,'provider-absent MIR fish')
  assert_bonus(player,'biter-egg',state.biter_base+.2,'provider-absent MIR biter egg')
  assert_bonus(player,'pentapod-egg',state.pentapod_base+.2,'provider-absent MIR pentapod egg')
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'provider-absent player')
  assert_status(game.forces[state.foreign_force_index],MIR_BIOFLUX,{level=1,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},'provider-absent foreign MIR bioflux')
end
local function assert_readded(state)
  local player,foreign=game.forces.player,game.forces[state.foreign_force_index]
  assert_status(player,SOURCE_BIOFLUX,{level=1,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'readded bioflux provider')
  assert_status(player,SOURCE_FISH,{level=1,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'readded fish provider')
  assert_status(foreign,FOREIGN_CURRENT,{level=1,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'readded engine provider')
  assert_status(foreign,FOREIGN_DISABLED,{level=1,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'readded foreign provider')
  assert_status(player,MIR_BIOFLUX,{level=2,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},'readded MIR bioflux')
  assert_status(player,MIR_BREEDING,{level=3,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'readded MIR breeding')
  assert_credit(player,2,1,'readded MIR')
  assert_bonus(player,'bioflux',state.bioflux_base+.1,'readded bioflux no foreign credit')
  assert_bonus(player,'fish-breeding',state.fish_base+.1,'readded fish no foreign credit')
  assert_bonus(player,'biter-egg',state.biter_base+.2,'readded biter egg')
  assert_bonus(player,'pentapod-egg',state.pentapod_base+.2,'readded pentapod egg')
  assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'readded player')
  assert_status(foreign,MIR_BIOFLUX,{level=1,researched=false,enabled=false,visible=false,maximum=UINT32_MAX,saved=0},'readded foreign MIR bioflux')
end
local function marker(stage,state)
  local player,foreign=game.forces.player,game.forces[state.foreign_force_index]
  -- Published false preference has no MIR bioflux or new signed carriers.
  -- Phase assertions require their presence once MIR5 introduces them.
  local bioflux,positive,negative=optional(player,MIR_BIOFLUX),optional(player,POSITIVE),optional(player,NEGATIVE)
  local foreign_bioflux=optional(foreign,MIR_BIOFLUX)
  log('[MIR5_NATIVE_FIXTURE] REMOVAL_OBSERVATION '..helpers.table_to_json(removed_observation(foreign)))
  log('[MIR5_NATIVE_FIXTURE] RESULT '..helpers.table_to_json({stage=stage,case=CASE,status='passed',qualification='native-runner-readback-required',witnesses={
    source_actual_provider_labs=state.source_actual_labs,mir_actual_labs=state.mir_actual_labs,phase=state.phase,
    native_current=queue_snapshot(player).current,native_current_progress=queue_snapshot(player).progress,
    native_tail_saved=technology(player,PLAYER_TAIL).saved_progress,mir_bioflux_next=bioflux and bioflux.level or false,
    mir_breeding_next=technology(player,MIR_BREEDING).level,credit_positive_next=positive and positive.level or false,
    credit_negative_next=negative and negative.level or false,bioflux_bonus=recipe_bonus(player,'bioflux'),fish_bonus=recipe_bonus(player,'fish-breeding'),
    biter_bonus=recipe_bonus(player,'biter-egg'),pentapod_bonus=recipe_bonus(player,'pentapod-egg'),
    foreign_mir_bioflux_disabled=foreign_bioflux ~= nil and foreign_bioflux.enabled==false,on_load_read_only=stage=='reload',
  }}))
end
local function complete_phase(state)
  if state.phase=='source-completed' then assert_source(state)
  elseif state.phase=='true-completed' then assert_true(state)
  elseif state.phase=='false-completed' then assert_false(state)
  elseif state.phase=='removed-completed' then assert_removed(state)
  elseif state.phase=='readded-completed' then assert_readded(state)
  else fail('unknown completed phase') end
end
script.on_init(function()
  require_mode('4.7.20002','0.1.0',false,true,'published source')
  if storage[KEY]~=nil then fail('source storage exists') end
  game.speed=16
  local player=game.forces.player;player.enable_all_prototypes()
  for _,name in ipairs({SOURCE_BIOFLUX,SOURCE_FISH,PLAYER_CURRENT,PLAYER_TAIL}) do prerequisites(technology(player,name)) end
  for _,name in ipairs({PLAYER_CURRENT,PLAYER_TAIL}) do if technology(player,name).researched then fail('native queue target was researched by prerequisites: '..name) end end
  local bases={bioflux=recipe_bonus(player,'bioflux'),fish=recipe_bonus(player,'fish-breeding'),biter=recipe_bonus(player,'biter-egg'),pentapod=recipe_bonus(player,'pentapod-egg')}
  for _,name in ipairs({SOURCE_BIOFLUX,SOURCE_FISH}) do
    assert_accelerated(technology(player,name),'published '..name)
    assert_status(player,name,{level=1,researched=false,enabled=true,visible=false,maximum=UINT32_MAX,saved=0},'published pre-lab')
  end
  local foreign=game.create_force(FOREIGN_FORCE);foreign.enable_all_prototypes()
  for _,name in ipairs({FOREIGN_CURRENT,FOREIGN_TAIL,FOREIGN_DISABLED}) do prerequisites(technology(foreign,name)) end
  if technology(foreign,FOREIGN_CURRENT).researched or technology(foreign,FOREIGN_TAIL).researched or technology(foreign,FOREIGN_DISABLED).researched then fail('engine observer targets were researched by prerequisites') end
  technology(foreign,FOREIGN_DISABLED).enabled=false;technology(foreign,FOREIGN_DISABLED).visible_when_disabled=true
  local foreign_queue=queue_native(foreign,FOREIGN_CURRENT,FOREIGN_TAIL,.27,'engine observer source')
  local lab=game.surfaces[1].create_entity{name='biolab',position={0,0},force=player}
  if lab==nil or lab.valid==false then fail('could not create F200 Space Age biolab') end
  local state={phase='await-source',source_mir='4.7.20002',fixture_version='0.1.0',source_actual_labs=0,mir_actual_labs=0,
    milestone='source-pending',bioflux_base=bases.bioflux,fish_base=bases.fish,biter_base=bases.biter,pentapod_base=bases.pentapod,
    foreign_force_index=foreign.index,foreign_queue=foreign_queue,lab=lab,deadline_tick=game.tick+DEADLINE}
  storage[KEY]=state;fill(lab,technology(player,SOURCE_BIOFLUX))
  if player.add_research(technology(player,SOURCE_BIOFLUX))~=true then fail('could not queue source bioflux provider') end
end)
script.on_configuration_changed(function()
  loaded_snapshot,reload_logged=nil,false
  local state=storage[KEY]
  local active=script.active_mods
  if active['more-infinite-research']=='5.0.20000' and active[FIXTURE]=='0.2.0' then
    require_mode('5.0.20000','0.2.0',true,true,'preferred successor')
    if type(state)~='table' or state.phase~='source-completed' then fail('preferred source witness differs') end
    local foreign=game.forces[state.foreign_force_index]
    local foreign_full=technology(foreign,MIR_BIOFLUX)
    if foreign_full.level~=1 or foreign_full.researched then fail('MIR foreign row introduction differs') end
    foreign_full.enabled=false;foreign_full.visible_when_disabled=false
    assert_earned_source(state,'preferred source')
    local bioflux=technology(game.forces.player,MIR_BIOFLUX);prerequisites(bioflux);assert_accelerated(bioflux,'preferred MIR bioflux')
    state.phase='await-true-bioflux';state.deadline_tick=game.tick+DEADLINE;prepend_mir(state,MIR_BIOFLUX,'preferred MIR bioflux')
  elseif active['more-infinite-research']=='5.0.20000' and active[FIXTURE]=='0.3.0' then
    require_mode('5.0.20000','0.3.0',false,true,'foreign successor')
    if type(state)~='table' or state.phase~='true-completed' then fail('foreign source witness differs') end
    assert_true(state,true);state.phase='await-false-breeding';state.deadline_tick=game.tick+DEADLINE;prepend_mir(state,MIR_BREEDING,'foreign MIR breeding')
  elseif active['more-infinite-research']=='5.0.20000' and active[FIXTURE]=='0.4.0' then
    require_mode('5.0.20000','0.4.0',false,false,'provider removal')
    if type(state)~='table' or state.phase~='false-completed' then fail('provider removal source witness differs') end
    assert_removed(state);state.removed_observation=removed_observation(game.forces[state.foreign_force_index]);state.phase='removed-completed';pending_save=true
  elseif active['more-infinite-research']=='5.0.20000' and active[FIXTURE]=='0.5.0' then
    require_mode('5.0.20000','0.5.0',false,true,'provider readdition')
    if type(state)~='table' or state.phase~='removed-completed' then fail('provider readdition source witness differs') end
    assert_readded(state);state.phase='readded-completed';pending_save=true
  end
end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[KEY]
  if type(state)~='table' or event.research==nil or event.research.force~=game.forces.player then return end
  if state.phase=='await-source' then
    local expected=state.source_actual_labs==0 and SOURCE_BIOFLUX or SOURCE_FISH
    if event.research.name~=expected then return end
    state.source_actual_labs=state.source_actual_labs+1
    if state.source_actual_labs==1 then state.phase='await-source-next' else state.phase='await-source-restore' end
  elseif state.phase=='await-true-bioflux' and event.research.name==MIR_BIOFLUX then state.mir_actual_labs=state.mir_actual_labs+1;state.phase='restore-true-bioflux'
  elseif state.phase=='await-true-breeding' and event.research.name==MIR_BREEDING then state.mir_actual_labs=state.mir_actual_labs+1;state.phase='restore-true-breeding'
  elseif state.phase=='await-false-breeding' and event.research.name==MIR_BREEDING then state.mir_actual_labs=state.mir_actual_labs+1;state.phase='restore-false-breeding' end
end)
script.on_load(function()
  local state=storage[KEY]
  if type(state)=='table' and (state.phase=='source-completed' or state.phase=='true-completed' or state.phase=='false-completed' or state.phase=='removed-completed' or state.phase=='readded-completed') then
    loaded_snapshot={phase=state.phase,source_labs=state.source_actual_labs,mir_labs=state.mir_actual_labs,queue=copy_queue(state.player_queue)}
  else loaded_snapshot=nil end
  reload_logged,pending_save=false,false
end)
script.on_event(defines.events.on_tick,function()
  local state=storage[KEY]
  if type(state)~='table' then return end
  if pending_save then complete_phase(state);marker('initial',state);game.server_save(SAVE);pending_save=false;return end
  if loaded_snapshot and not reload_logged then
    complete_phase(state)
    if state.source_actual_labs~=loaded_snapshot.source_labs or state.mir_actual_labs~=loaded_snapshot.mir_labs then fail('cold reload changed actual lab witnesses') end
    assert_queue(game.forces.player,loaded_snapshot.queue,'cold reload player');marker('reload',state);reload_logged=true;return
  end
  if state.phase=='source-completed' or state.phase=='true-completed' or state.phase=='false-completed' or state.phase=='removed-completed' or state.phase=='readded-completed' then return end
  if game.tick>state.deadline_tick then fail('fixture did not complete bounded native labs') end
  local player=game.forces.player
  if state.phase=='await-source-next' and player.current_research==nil and #(player.research_queue or {})==0 then
    fill(state.lab,technology(player,SOURCE_FISH));if player.add_research(technology(player,SOURCE_FISH))~=true then fail('could not queue source fish provider') end;state.phase='await-source'
  elseif state.phase=='await-source-restore' then
    if player.current_research==nil and #(player.research_queue or {})==0 then
      freeze(state);state.milestone='two-native-fixed-provider-labs';state.player_queue=queue_native(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'published player');state.phase='source-completed';assert_source(state);marker('initial',state);game.server_save(SAVE)
    end
  elseif state.phase=='restore-true-bioflux' and player.current_research and player.current_research.name==PLAYER_CURRENT then
    freeze(state);assert_native_queue(player,PLAYER_CURRENT,PLAYER_TAIL,.27,'preferred bioflux restore')
    local breeding=technology(player,MIR_BREEDING);prerequisites(breeding);assert_accelerated(breeding,'preferred MIR breeding')
    state.phase='await-true-breeding';prepend_mir(state,MIR_BREEDING,'preferred MIR breeding')
  elseif state.phase=='restore-true-breeding' and player.current_research and player.current_research.name==PLAYER_CURRENT then
    freeze(state);state.phase='true-completed';assert_true(state);marker('initial',state);game.server_save(SAVE)
  elseif state.phase=='restore-false-breeding' and player.current_research and player.current_research.name==PLAYER_CURRENT then
    freeze(state);state.phase='false-completed';assert_false(state);marker('initial',state);game.server_save(SAVE)
  elseif state.phase=='await-source' or state.phase=='await-true-bioflux' or state.phase=='await-true-breeding' or state.phase=='await-false-breeding' then state.lab.energy=1000000000 end
end)
