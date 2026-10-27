import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tests/fixtures/sif-science-retirement'
SHARED = FIXTURE / 'shared'
CORE = SHARED / 'core'
SELECTORS = SHARED / 'selectors'
PROFILES = ROOT / 'tests/profiles'
POLICIES = ('configured','space','space-and-promethium','space-age-progression','official-progression','mod-progression','all-official','all')
TARGETS = {
 'f200': {'engine':'2.0.77','line':'2.0','engine_sha':'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B','sif':'1.0.60','sif_sha':'860F2048A7E6F4C2ECD1A9CECA6ECDD340ECF797773EC582A6E60FFE6F8D87AC','commons':'1.0.27','commons_sha':'6F3622AE6270F9B365A9E2E07FA5E07B61B2BBFCAB3A4D930CC410EBDEB63B92','observer_sha':'723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87','published':'4.7.20002','candidate':'5.0.20000'},
 # F210 uses the independently filed 1.0.10 archive. Its active_mods value
 # is the same semantic version declared by that archive's info.json.
 'f210': {'engine':'2.1.23','line':'2.1','engine_sha':'FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060','sif':'1.0.78','sif_sha':'3B5F2A381ADF1D9AECF048293E20035963A528720FBDC148CCC2B0418049FF13','commons':'1.0.33','commons_sha':'378D3114B09C872358088B33500BC4AB0B9B9EFD9E5650DBEA0E87B5914C29BB','extras':'1.0.10','runtime_extras':'1.0.10','extras_sha':'3AB74877E49FB245E62593B669EB4D5C762207C047CA6F70E4D0CC9B67DF0225','observer_sha':'2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C','published':'4.7.21002','candidate':'5.0.21000'},
}
CURRENT_F210_SOURCE = '98fbdd33fe47eb678a5e1aaf17fee903eba2a22a'
CURRENT_F210_PLAYER_TREE = 'ffc5f2e3359de4f326a184cf6a3c29a55941150a'
CURRENT_F210_ARCHIVE = '58F04FB9D417F2726835F4A6740490DE3C1841665DAC81C2BA3DFA94050D9457'
CURRENT_F210_ARCHIVE_BYTES = 679860

# Independent published continuation rows and the separately derived corrected
# MIR5 SIF expectation. This intentionally does not import contract.lua.
BASE = {
 'research-speed-7': [('automation-science-pack',1),('logistic-science-pack',1),('chemical-science-pack',1),('production-science-pack',1),('utility-science-pack',1),('military-science-pack',1)],
 'weapon-shooting-speed-7': [('automation-science-pack',1),('logistic-science-pack',1),('chemical-science-pack',1),('military-science-pack',1),('utility-science-pack',1)],
}
SPACE_AGE = [('agricultural-science-pack',1),('metallurgic-science-pack',1),('electromagnetic-science-pack',1),('cryogenic-science-pack',1),('promethium-science-pack',1)]
PUBLISHED_ANCHORS = {
 'research-speed-7': ['research-speed-5','utility-science-pack','research-speed-6','automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack','military-science-pack','agricultural-science-pack','metallurgic-science-pack','electromagnetic-science-pack','cryogenic-science-pack','promethium-science-pack'],
 'weapon-shooting-speed-7': ['weapon-shooting-speed-5','utility-science-pack','weapon-shooting-speed-6','automation-science-pack','logistic-science-pack','chemical-science-pack','military-science-pack'],
}
# Kept distinct even where a successor policy has the same values: predecessor
# facts are pinned to published 4.7.2, while successor rows come from current
# authored continuations plus the narrow SIF retirement correction.
CANDIDATE_ANCHORS = {name:list(rows) for name, rows in PUBLISHED_ANCHORS.items()}
OBSOLETE_CANDIDATE_ANCHORS = {
 'research-speed-7': ['research-speed-5','utility-science-pack','research-speed-6'],
 'weapon-shooting-speed-7': ['weapon-shooting-speed-5','utility-science-pack','weapon-shooting-speed-6'],
}


def fixture_role(stage):
    return 'successor' if stage == 'mir5' else stage
EFFECTS = {
 'research-speed-7': [{'type':'laboratory-speed','modifier':.6}],
 'weapon-shooting-speed-7': [{'type':'gun-speed','ammo_category':'bullet','modifier':.4},{'type':'gun-speed','ammo_category':'shotgun-shell','modifier':.4}],
}
FORMULA = '683.4375*1.5^(L-7)'

def expected_row(name, policy, stage='mir5'):
    assert policy in POLICIES
    science=list(BASE[name])
    if name == 'research-speed-7':
        science += list(SPACE_AGE)
    elif stage == 'mir5':
        if policy == 'space-and-promethium':
            science += [('promethium-science-pack',1)]
        elif policy == 'official-progression':
            science += [('production-science-pack',1)]
        elif policy in ('all-official','all'):
            science += [('production-science-pack',1)] + list(SPACE_AGE)
    if stage == 'published':
        assert policy == 'configured'
        return science, list(PUBLISHED_ANCHORS[name])
    assert stage == 'mir5'
    prerequisites=list(CANDIDATE_ANCHORS[name])
    if name == 'weapon-shooting-speed-7':
        if policy == 'space-and-promethium':
            prerequisites += ['promethium-science-pack']
        elif policy == 'official-progression':
            prerequisites += ['production-science-pack']
        elif policy in ('all-official','all'):
            prerequisites += ['production-science-pack'] + [name for name, _ in SPACE_AGE]
    return science, prerequisites

def obsolete_candidate_rows():
    # The disproved 6/3 research candidate was once asserted by this fixture.
    # Keep weapon correct so the test proves research science fails first.
    result={}
    for name in BASE:
        science, prerequisites=expected_row(name,'configured')
        if name == 'research-speed-7':
            science, prerequisites=list(BASE[name]), list(OBSOLETE_CANDIDATE_ANCHORS[name])
        result[name]={'type':'technology','name':name,'level':7,'upgrade':True,'max_level':'infinite','hidden':False,
          'unit':{'count_formula':FORMULA,'time':120,'ingredients':[{'name':item,'amount':amount} for item,amount in science]},
          'prerequisites':prerequisites,'effects':deepcopy(EFFECTS[name])}
    return result

def lua_value(runtime, value):
    if isinstance(value, dict):
        out=runtime.table()
        for key, item in value.items(): out[key]=lua_value(runtime,item)
        return out
    if isinstance(value, (list,tuple)):
        out=runtime.table()
        for index,item in enumerate(value,1): out[index]=lua_value(runtime,item)
        return out
    return value

def plain(value):
    if hasattr(value,'keys'):
        keys=list(value.keys())
        if keys and all(isinstance(key,int) for key in keys): return [plain(value[key]) for key in range(1,max(keys)+1)]
        return {key:plain(value[key]) for key in keys}
    return value

def raw_rows(policy, stage='mir5'):
    result={}
    for name in BASE:
        science, prerequisites=expected_row(name,policy,stage)
        result[name]={'type':'technology','name':name,'level':7,'upgrade':True,'max_level':'infinite','hidden':False,
          'unit':{'count_formula':FORMULA,'time':120,'ingredients':[{'name':item,'amount':amount} for item,amount in science]},
          'prerequisites':prerequisites,'effects':deepcopy(EFFECTS[name])}
    return result

class SIFScienceRetirementFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function sif_data(path,contract_path,mods,raw,policy)
            local env={mods=mods,settings={startup={['mir-science-pack-ingredient-policy']={value=policy}}},data={raw=raw}}
            function env.require(name) assert(name:match('/contract$'));return assert(loadfile(contract_path,'t',env))()end
            env._G=env;setmetatable(env,{__index=_G});local chunk,message=loadfile(path,'t',env);assert(chunk,message)
            local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),raw=raw}
          end
          function sif_selector(path,raw)
            local env={data={raw=raw}};env._G=env;setmetatable(env,{__index=_G});local chunk,message=loadfile(path,'t',env);assert(chunk,message)
            local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),raw=raw}
          end
          function sif_parse(path,contract_path)
            local callbacks,reads={events={}},{}
            local parsing, imports = true, 0
            local env={script={mod_name='mir-fixture-mir5-sif-science-retirement-f200',on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,on_configuration_changed=function(f)callbacks.configuration=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            function env.require(name)
              assert(parsing, 'late contract import')
              assert(name == '__' .. env.script.mod_name .. '__/contract')
              imports = imports + 1
              return assert(loadfile(contract_path,'t',env))()
            end
            env._G=env;setmetatable(env,{__index=function(_,key)if key=='game'or key=='storage'then reads[key]=(reads[key]or 0)+1;error('parse '..key)end;return _G[key]end})
            local chunk,message=loadfile(path,'t',env);assert(chunk,message);local ok,result=pcall(chunk);parsing=false;return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads,imports=imports}
          end
          function sif_transition(source_path,successor_path,source_contract,successor_contract,target,bad)
            local exact
            if target == 'f200' then
              exact = {base='2.0.77', sif='1.0.60', commons='1.0.27', source='4.7.20002', successor='5.0.20000'}
            else
              exact = {base='2.1.23', sif='1.0.78', commons='1.0.33', extras='1.0.10', source='4.7.21002', successor='5.0.21000'}
            end
            local contract = assert(loadfile(source_contract))()
            local callbacks, storage, reports, saves = {events={}}, {}, {}, 0
            local inventory = {counts={}}
            function inventory.insert(row)
              inventory.counts[row.name] = (inventory.counts[row.name] or 0) + row.count
              return row.count
            end
            function inventory.get_item_count(name) return inventory.counts[name] or 0 end

            local modules = {occupied=bad == 'module'}
            function modules.is_empty() return not modules.occupied end
            local lab = {valid=true, energy=0}
            function lab.get_inventory(kind)
              assert(kind == 1)
              return inventory
            end
            function lab.get_module_inventory() return modules end

            local player = {
              name='player', index=1, valid=true, technologies={}, research_queue={}, research_progress=0,
              laboratory_speed_modifier=0, bullet=0, shotgun=0
            }
            function player.enable_all_prototypes() end
            function player.get_gun_speed_modifier(name)
              return name == 'bullet' and player.bullet or (name == 'shotgun-shell' and player.shotgun or 0)
            end
            function player.add_research(value)
              if player.current_research ~= nil or not value then return false end
              player.current_research, player.research_queue = value, {value}
              player.research_progress = value.saved_progress or 0
              return true
            end
            local function set_runtime_rows(value_contract, stage)
              for _, name in ipairs({'research-speed-7', 'weapon-shooting-speed-7'}) do
                local row = value_contract.rows[name]
                local science = stage == 'source' and row.published.science or row.science.configured
                local prerequisites = stage == 'source' and row.published.prerequisites or row.prerequisites.configured
                local tech = player.technologies[name]
                if not tech then
                  tech = {
                    valid=true, name=name, force=player, level=7, researched=false, enabled=true, saved_progress=0,
                    research_unit_count=2, research_unit_energy=60
                  }
                  player.technologies[name] = tech
                end
                tech.research_unit_ingredients, tech.prerequisites = {}, {}
                for index, item in ipairs(science) do tech.research_unit_ingredients[index] = {name=item[1], amount=item[2]} end
                for index, item in ipairs(prerequisites) do
                  tech.prerequisites[index] = {name=item, research_recursive=function() end}
                end
              end
            end
            set_runtime_rows(contract, 'source')
            if bad == 'unit-count' then player.technologies['research-speed-7'].research_unit_count = 1 end

            local game = {tick=0, speed=1, forces={player=player}, surfaces={}}
            game.surfaces[1] = {
              create_entity=function(row)
                assert(row.name == 'biolab' and row.force == player)
                return lab
              end
            }
            function game.server_save(name)
              assert(name == 'mir5-native-complete')
              saves = saves + 1
            end
            local function active(stage)
              local core = 'mir-fixture-mir5-sif-science-retirement-' .. target
              local selector = 'mir-fixture-mir5-sif-policy-configured-' .. target
              local rows = {
                base=exact.base, ['elevated-rails']=exact.base, quality=exact.base, ['space-age']=exact.base,
                ['space-is-fake']=exact.sif, ['cr-commons']=exact.commons,
                ['more-infinite-research']=stage == 'source' and exact.source or exact.successor,
                [core]=stage == 'source' and '0.1.0' or '0.2.0', [selector]='0.1.0'
              }
               if exact.extras then
                 rows.recycler, rows['cr-extras'] = exact.base, exact.extras
                 if bad == 'extras-version-under' then rows['cr-extras'] = '1.0.0'
                 elseif bad == 'extras-version-over' then rows['cr-extras'] = '1.0.2' end
               end
              return rows
            end
            local function load(path, contract_path, stage)
              callbacks = {events={}}
              local parsing = true
              local env = {
                script={
                  mod_name='mir-fixture-mir5-sif-science-retirement-' .. target,
                  active_mods=active(stage),
                  on_init=function(f) callbacks.init=f end,
                  on_load=function(f) callbacks.load=f end,
                  on_configuration_changed=function(f) callbacks.configuration=f end,
                  on_event=function(e,f) callbacks.events[e]=f end
                },
                defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
                game=game, storage=storage,
                settings={startup={['mir-science-pack-ingredient-policy']={value='configured'}}},
                helpers={table_to_json=function() return '{}' end},
                log=function(value)
                  if value:match('^%[MIR5_NATIVE_FIXTURE%] RESULT ') then reports[#reports+1]=value end
                end
              }
              function env.require(name)
                assert(parsing, 'late contract import')
                assert(name == '__' .. env.script.mod_name .. '__/contract')
                return assert(loadfile(contract_path,'t',env))()
              end
              env._G=env
              setmetatable(env,{__index=_G})
              local chunk, message = loadfile(path,'t',env)
              assert(chunk, message)
              local ok, result = pcall(chunk)
              parsing = false
              if ok then set_runtime_rows(assert(loadfile(contract_path))(), stage) end
              return ok, tostring(result)
            end
            local function invoke(fn, event)
              if type(fn) ~= 'function' then return false, 'missing callback' end
              local ok, result = pcall(fn, event)
              return ok, tostring(result)
            end
            local function tick()
              game.tick = game.tick + 1
              return invoke(callbacks.events[1])
            end
            local function complete(name)
              local value = player.technologies[name]
              assert(player.current_research == value)
              local remaining = 1 - player.research_progress
              player.current_research, player.research_queue, player.research_progress = nil, {}, 0
              value.saved_progress, value.level = 0, value.level + 1
              if name == 'research-speed-7' then
                player.laboratory_speed_modifier = player.laboratory_speed_modifier + .6
              else
                player.bullet, player.shotgun = player.bullet + .4, player.shotgun + .4
              end
              -- The host double keeps partial successor consumption observational.
              for _, row in ipairs(value.research_unit_ingredients) do
                inventory.counts[row.name] = inventory.counts[row.name] - row.amount * remaining
              end
              return invoke(callbacks.events[2], {research=value, by_script=false})
            end

            local ok, message = load(source_path, source_contract, 'source')
            if not ok then return {ok=false,message=message} end
            ok, message = invoke(callbacks.init)
            if not ok then return {ok=false,message=message} end
            ok, message = invoke(callbacks.events[2], {research=player.technologies['research-speed-7'], by_script=true})
            if not ok then return {ok=false,message=message} end
            local ignored = storage.mir5_sif_science_retirement.source_labs == 0
              and storage.mir5_sif_science_retirement.phase == 'source-first'
            if not ignored then return {ok=false,message='scripted research completion changed fixture state'} end

            ok, message = complete('research-speed-7')
            if not ok then return {ok=false,message=message} end
            ok, message = tick()
            if not ok then return {ok=false,message=message} end
            ok, message = complete('weapon-shooting-speed-7')
            if not ok then return {ok=false,message=message} end
            ok, message = tick()
            if not ok then return {ok=false,message=message} end
            for _=1,2 do
              lab.energy = 17
              ok, message = invoke(callbacks.load)
              if not ok then return {ok=false,message=message} end
              ok, message = tick()
              if not ok then return {ok=false,message=message} end
              if bad == 'reload-read-only' and lab.energy ~= 17 then
                return {ok=false,message='completed source observer changed lab energy'}
              end
            end

            if bad == 'source-state' then
              storage.mir5_sif_science_retirement.source_rows['research-speed-7'].level = 7
            elseif bad == 'source-progress' then
              storage.mir5_sif_science_retirement.source_rows['research-speed-7'].progress = .41
            end
            ok, message = load(successor_path, successor_contract, 'successor')
            if not ok then return {ok=false,message=message} end
            ok, message = invoke(callbacks.load)
            if not ok then return {ok=false,message=message} end
            ok, message = invoke(callbacks.configuration)
            if not ok then
              return {
                ok=false, message=message, phase=storage.mir5_sif_science_retirement.phase,
                current=player.current_research and player.current_research.name or false
              }
            end
            ok, message = complete('research-speed-7')
            if not ok then return {ok=false,message=message} end
            ok, message = tick()
            if not ok then return {ok=false,message=message} end
            ok, message = complete('weapon-shooting-speed-7')
            if not ok then return {ok=false,message=message} end
            ok, message = tick()
            if not ok then return {ok=false,message=message} end
            local completed_state = storage.mir5_sif_science_retirement
            -- A native server keeps ticking after its completion marker/save.
            -- Do not immediately replace the pre-configuration load snapshot
            -- with another on_load callback and hide an ordinary-tick failure.
            ok, message = tick()
            if not ok then return {ok=false,message=message} end
            local completed_consumption = completed_state.successor_consumption
            local completed_after = completed_consumption.after
            local completed_rows = completed_state.successor_rows
            local finished = player.technologies['research-speed-7']
            if bad == 'reload-enabled' then finished.enabled = false
            elseif bad == 'reload-researched' then finished.researched = true
            elseif bad == 'reload-progress' then finished.saved_progress = .13
            elseif bad == 'reload-queue' then player.current_research, player.research_queue = finished, {finished}
            elseif bad == 'reload-consumption' then completed_after['automation-science-pack'] = -1
            elseif bad == 'reload-inventory' then inventory.counts['automation-science-pack'] = -1
            elseif bad == 'reload-bonus' then completed_state.successor_bonus.lab = -1
            elseif bad == 'reload-missing-rows' then completed_state.successor_rows = nil
            elseif bad == 'reload-missing-consumption' then completed_state.successor_consumption = nil
            elseif bad == 'reload-successor-labs' then completed_state.successor_labs = 1
            elseif bad == 'reload-phase' then completed_state.phase = 'source-complete' end
            for _=1,2 do
              lab.energy = 17
              ok, message = invoke(callbacks.load)
              if not ok then return {ok=false,message=message} end
              ok, message = tick()
              if not ok then return {ok=false,message=message} end
              if bad == 'reload-read-only' and (lab.energy ~= 17
                  or completed_state.successor_consumption ~= completed_consumption
                  or completed_state.successor_consumption.after ~= completed_after
                  or completed_state.successor_rows ~= completed_rows) then
                return {ok=false,message='completed successor observer changed durable/native state'}
              end
            end
            return {
              ok=true,message='',reports=#reports,saves=saves,scripted_ignored=ignored,
              state=storage.mir5_sif_science_retirement,
              research=player.technologies['research-speed-7'].level,
              weapon=player.technologies['weapon-shooting-speed-7'].level,
              lab=player.laboratory_speed_modifier,bullet=player.bullet,shotgun=player.shotgun
            }
          end
          function sif_candidate_create(path,contract_path,target,policy,bad)
            local exact
            if target == 'f200' then
              exact = {base='2.0.77', sif='1.0.60', commons='1.0.27', successor='5.0.20000'}
            else
              exact = {base='2.1.23', sif='1.0.78', commons='1.0.33', extras='1.0.10', successor='5.0.21000'}
            end
            local contract = assert(loadfile(contract_path))()
            local core = 'mir-fixture-mir5-sif-science-retirement-' .. target
            local selector = 'mir-fixture-mir5-sif-policy-' .. policy .. '-' .. target
            local active = {
              base=exact.base, ['elevated-rails']=exact.base, quality=exact.base, ['space-age']=exact.base,
              ['space-is-fake']=exact.sif, ['cr-commons']=exact.commons,
              ['more-infinite-research']=exact.successor, [core]='0.2.0', [selector]='0.1.0'
            }
             if exact.extras then
               active.recycler, active['cr-extras'] = exact.base, exact.extras
               if bad == 'extras-version-under' then active['cr-extras'] = '1.0.0'
               elseif bad == 'extras-version-over' then active['cr-extras'] = '1.0.2' end
             end
            local player = {
              name='player', index=1, valid=true, technologies={}, research_queue={},
              laboratory_speed_modifier=bad == 'bonus' and .1 or 0, bullet=0, shotgun=0
            }
            function player.enable_all_prototypes() error('fresh candidate mutated prototypes') end
            function player.add_research() error('fresh candidate started research') end
            function player.get_gun_speed_modifier(name)
              return name == 'bullet' and player.bullet or (name == 'shotgun-shell' and player.shotgun or 0)
            end
            for _, name in ipairs({'research-speed-7', 'weapon-shooting-speed-7'}) do
              local ingredients, prerequisites = {}, {}
              for index, row in ipairs(contract.rows[name].science[policy]) do
                ingredients[index] = {name=row[1],amount=row[2]}
              end
              if bad == 'science-permuted' then
                ingredients[1], ingredients[#ingredients] = ingredients[#ingredients], ingredients[1]
              elseif bad == 'science-amount' then ingredients[1].amount = 2
              elseif bad == 'science-duplicate' then ingredients[2] = ingredients[1]
              elseif bad == 'science-name' then ingredients[1].name = 'unrelated-science-pack'
              elseif bad == 'science-space' then ingredients[1].name = 'space-science-pack'
              end
              for index, row in ipairs(contract.rows[name].prerequisites[policy]) do prerequisites[index] = {name=row} end
              player.technologies[name] = {
                valid=true, name=name, force=player, level=bad == 'level' and 8 or 7,
                researched=false, enabled=true, saved_progress=0,
                research_unit_count=bad == 'unit-count' and 1 or 2, research_unit_energy=60,
                research_unit_ingredients=ingredients, prerequisites=prerequisites
              }
            end
            local callbacks, markers, payload, writes = {events={}}, 0, nil, 0
            local storage = {}
            setmetatable(storage, {__newindex=function()
              writes = writes + 1
              error('fresh candidate wrote storage')
            end})
            local env = {
              script={
                mod_name=core,
                active_mods=active,
                on_init=function(f) callbacks.init=f end,
                on_load=function(f) callbacks.load=f end,
                on_configuration_changed=function(f) callbacks.configuration=f end,
                on_event=function(e,f) callbacks.events[e]=f end
              },
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
              game={forces={player=player}}, storage=storage,
              settings={startup={['mir-science-pack-ingredient-policy']={value=policy}}},
              helpers={table_to_json=function(value) payload=value; return '{}' end},
              log=function(value)
                if value:match('^%[MIR5_SIF_CANDIDATE%] RESULT ') then markers=markers+1
                else error('unexpected fresh candidate marker') end
              end
            }
            local parsing = true
            function env.require(name)
              assert(parsing, 'late contract import')
              assert(name == '__' .. env.script.mod_name .. '__/contract')
              return assert(loadfile(contract_path,'t',env))()
            end
            env._G=env
            setmetatable(env,{__index=_G})
            local chunk, message = loadfile(path,'t',env)
            assert(chunk,message)
            local ok, result = pcall(chunk)
            parsing = false
            if not ok then return {ok=false,message=tostring(result),writes=writes,markers=markers} end
            ok, result = pcall(callbacks.init)
            if not ok then return {ok=false,message=tostring(result),writes=writes,markers=markers} end
            ok, result = pcall(callbacks.events[1])
            if not ok then return {ok=false,message=tostring(result),writes=writes,markers=markers} end
            return {ok=true,message='',writes=writes,markers=markers,payload=payload,storage_empty=next(storage)==nil}
          end        ''')
    def core(self,target,stage): return FIXTURE/target/fixture_role(stage)
    def core_lua(self,name): return CORE/name
    def selector_lua(self,policy): return SELECTORS/policy/'settings-updates.lua'
    def data(self,target,stage,policy,raw=None,mods=None):
        meta=TARGETS[target];core=self.core(target,stage);fixture=f'mir-fixture-mir5-sif-science-retirement-{target}'
        expected_mods={'base':meta['engine'],'elevated-rails':meta['engine'],'quality':meta['engine'],'space-age':meta['engine'],'space-is-fake':meta['sif'],'cr-commons':meta['commons'],'more-infinite-research':meta['published' if stage=='published' else 'candidate'],fixture:'0.1.0' if stage=='published' else '0.2.0',f'mir-fixture-mir5-sif-policy-{policy}-{target}':'0.1.0'}
        if target=='f210':expected_mods.update({'recycler':meta['engine'],'cr-extras':meta['runtime_extras']})
        raw=raw or {'technology':raw_rows(policy, 'published' if stage=='published' else 'mir5')}
        raw.setdefault('lab',{}).setdefault('biolab',{'science_pack_drain_rate_percent':50})
        return plain(self.lua.eval('sif_data')(str(self.core_lua('data-final-fixes.lua')),str(self.core_lua('contract.lua')),lua_value(self.lua,mods or expected_mods),lua_value(self.lua,raw),policy))
    def test_all_eight_candidate_policy_rows_are_independent_on_both_targets(self):
        for target in TARGETS:
            for policy in POLICIES:
                with self.subTest(target=target,policy=policy):
                    result=self.data(target,'mir5',policy);self.assertTrue(result['ok'],result['message'])
                    for name in BASE:
                        actual=result['raw']['technology'][name];science,prereqs=expected_row(name,policy)
                        self.assertEqual(science,[(row['name'],row['amount'])for row in actual['unit']['ingredients']]);self.assertEqual(prereqs,actual['prerequisites']);self.assertEqual(EFFECTS[name],actual['effects']);self.assertEqual((2,None,1),(actual['unit'].get('count'),actual['unit'].get('count_formula'),actual['unit']['time']));self.assertNotIn('space-science-pack',actual['prerequisites'])
    def test_published_configured_preflight_and_bad_second_row_are_atomic(self):
        for target in TARGETS:
            result=self.data(target,'published','configured');self.assertTrue(result['ok'],result['message'])
            for name in BASE:
                actual=result['raw']['technology'][name]
                science,prerequisites=expected_row(name,'configured','published')
                self.assertEqual(science,[(row['name'],row['amount']) for row in actual['unit']['ingredients']])
                self.assertEqual(prerequisites,actual['prerequisites'])
        # The former Base-six/three-anchor candidate oracle is specifically
        # forbidden. Both failures precede the fixture's disposable tuning.
        obsolete={'technology':obsolete_candidate_rows()}
        result=self.data('f200','mir5','configured',obsolete);self.assertFalse(result['ok']);self.assertIn('science count differs',result['message'])
        for name in BASE:self.assertEqual((None,FORMULA,120),(result['raw']['technology'][name]['unit'].get('count'),result['raw']['technology'][name]['unit'].get('count_formula'),result['raw']['technology'][name]['unit']['time']))
        obsolete_prerequisites={'technology':raw_rows('configured')}
        obsolete_prerequisites['technology']['research-speed-7']['prerequisites']=list(OBSOLETE_CANDIDATE_ANCHORS['research-speed-7'])
        result=self.data('f200','mir5','configured',obsolete_prerequisites);self.assertFalse(result['ok']);self.assertIn('prerequisites count differs',result['message'])
        for name in BASE:self.assertEqual((None,FORMULA,120),(result['raw']['technology'][name]['unit'].get('count'),result['raw']['technology'][name]['unit'].get('count_formula'),result['raw']['technology'][name]['unit']['time']))
        raw={'technology':raw_rows('configured')};raw['technology']['weapon-shooting-speed-7']['effects'][0]['modifier']=.3
        result=self.data('f200','mir5','configured',raw);self.assertFalse(result['ok']);self.assertIn('effects differs',result['message'])
        for name in BASE:self.assertEqual((None,FORMULA,120),(result['raw']['technology'][name]['unit'].get('count'),result['raw']['technology'][name]['unit'].get('count_formula'),result['raw']['technology'][name]['unit']['time']))
        raw={'technology':raw_rows('configured'),'lab':{'biolab':{'science_pack_drain_rate_percent':100}}}
        result=self.data('f200','mir5','configured',raw);self.assertFalse(result['ok']);self.assertIn('native biolab drain differs',result['message'])
        for name in BASE:self.assertEqual((None,FORMULA,120),(result['raw']['technology'][name]['unit'].get('count'),result['raw']['technology'][name]['unit'].get('count_formula'),result['raw']['technology'][name]['unit']['time']))
        mismatch=self.data('f210','published','space',{'technology':raw_rows('configured','published')});self.assertFalse(mismatch['ok']);self.assertIn('configured-only',mismatch['message'])
        f200_missing_quality={'base':'2.0.77','elevated-rails':'2.0.77','space-age':'2.0.77','space-is-fake':'1.0.60','cr-commons':'1.0.27','more-infinite-research':'5.0.20000','mir-fixture-mir5-sif-science-retirement-f200':'0.2.0','mir-fixture-mir5-sif-policy-configured-f200':'0.1.0'}
        raw={'technology':raw_rows('configured')};missing=self.data('f200','mir5','configured',raw,f200_missing_quality);self.assertFalse(missing['ok']);self.assertIn('exact engine or native archive closure differs',missing['message'])
        for name in BASE:self.assertEqual((None,FORMULA,120),(missing['raw']['technology'][name]['unit'].get('count'),missing['raw']['technology'][name]['unit'].get('count_formula'),missing['raw']['technology'][name]['unit']['time']))
        f210_missing_recycler={'base':'2.1.23','elevated-rails':'2.1.23','quality':'2.1.23','space-age':'2.1.23','space-is-fake':'1.0.78','cr-commons':'1.0.33','cr-extras':'1.0.10','more-infinite-research':'5.0.21000','mir-fixture-mir5-sif-science-retirement-f210':'0.2.0','mir-fixture-mir5-sif-policy-configured-f210':'0.1.0'}
        raw={'technology':raw_rows('configured')};missing=self.data('f210','mir5','configured',raw,f210_missing_recycler);self.assertFalse(missing['ok']);self.assertIn('F210 closure differs',missing['message'])
        for name in BASE:self.assertEqual((None,FORMULA,120),(missing['raw']['technology'][name]['unit'].get('count'),missing['raw']['technology'][name]['unit'].get('count_formula'),missing['raw']['technology'][name]['unit']['time']))
    def test_f210_engine_runtime_version_is_canonical_and_rejects_fixed_opponents(self):
        meta=TARGETS['f210']
        self.assertEqual(('1.0.10','1.0.10'),(meta['extras'],meta['runtime_extras']))
        for wrong in ('1.0.01','1.0.09','1.0.11'):
            mods={'base':meta['engine'],'elevated-rails':meta['engine'],'quality':meta['engine'],'space-age':meta['engine'],'recycler':meta['engine'],'space-is-fake':meta['sif'],'cr-commons':meta['commons'],'cr-extras':wrong,'more-infinite-research':meta['candidate'],'mir-fixture-mir5-sif-science-retirement-f210':'0.2.0','mir-fixture-mir5-sif-policy-configured-f210':'0.1.0'}
            raw={'technology':raw_rows('configured')};result=self.data('f210','mir5','configured',raw,mods)
            self.assertFalse(result['ok']);self.assertIn('F210 closure differs',result['message'])
            for name in BASE:self.assertEqual((None,FORMULA,120),(result['raw']['technology'][name]['unit'].get('count'),result['raw']['technology'][name]['unit'].get('count_formula'),result['raw']['technology'][name]['unit']['time']))
        for opponent in ('extras-version-under','extras-version-over'):
            result=plain(self.lua.eval('sif_transition')(str(self.core_lua('control.lua')),str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),str(self.core_lua('contract.lua')),'f210',opponent))
            self.assertFalse(result['ok']);self.assertIn('F210 closure differs',result['message'])
            result=plain(self.lua.eval('sif_candidate_create')(str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),'f210','configured',opponent))
            self.assertFalse(result['ok']);self.assertIn('F210 closure differs',result['message']);self.assertEqual((0,0),(result['writes'],result['markers']))
    def test_selectors_are_single_startup_value_mutations(self):
        for target in TARGETS:
            for policy in POLICIES:
                raw={'string-setting':{'mir-science-pack-ingredient-policy':{'setting_type':'startup','default_value':'configured','allowed_values':list(POLICIES)}}}
                result=plain(self.lua.eval('sif_selector')(str(self.selector_lua(policy)),lua_value(self.lua,raw)));self.assertTrue(result['ok'],result['message']);self.assertEqual(policy,result['raw']['string-setting']['mir-science-pack-ingredient-policy']['default_value'])
        raw={'string-setting':{'mir-science-pack-ingredient-policy':{'setting_type':'runtime-global','default_value':'configured','allowed_values':list(POLICIES)}}}
        result=plain(self.lua.eval('sif_selector')(str(self.selector_lua('space')),lua_value(self.lua,raw)));self.assertFalse(result['ok']);self.assertIn('setting contract differs',result['message']);self.assertEqual('configured',result['raw']['string-setting']['mir-science-pack-ingredient-policy']['default_value'])
    def test_contract_is_imported_once_during_control_parsing(self):
        result = self.lua.eval('sif_parse')(
            str(self.core_lua('control.lua')), str(self.core_lua('contract.lua')))
        self.assertTrue(result['ok'], result['message'])
        self.assertEqual(1, result['imports'])
        self.assertEqual({}, plain(result['reads']))

    def test_completed_reload_observation_preserves_native_and_durable_state(self):
        for target in TARGETS:
            with self.subTest(target=target):
                result = plain(self.lua.eval('sif_transition')(
                    str(self.core_lua('control.lua')), str(self.core_lua('control.lua')),
                    str(self.core_lua('contract.lua')), str(self.core_lua('contract.lua')),
                    target, 'reload-read-only'))
                self.assertTrue(result['ok'], result['message'])
                self.assertEqual(6, result['reports'])

    def test_completed_reload_rejects_changed_saved_state(self):
        opponents = {
            'reload-enabled': 'successor durable research-speed-7 technology state differs',
            'reload-researched': 'successor durable research-speed-7 technology state differs',
            'reload-progress': 'successor durable research-speed-7 technology state differs',
            'reload-queue': 'successor completed research is queued',
            'reload-consumption': 'successor durable science inventory differs',
            'reload-inventory': 'successor durable science inventory differs',
            'reload-bonus': 'successor durable native effects differ',
            'reload-missing-rows': 'successor durable witness is absent',
            'reload-missing-consumption': 'successor durable witness is absent',
            'reload-successor-labs': 'successor did not complete two named labs',
            'reload-phase': 'research-speed-7 published level differs',
        }
        for target in TARGETS:
            for opponent, expected in opponents.items():
                with self.subTest(target=target, opponent=opponent):
                    result = plain(self.lua.eval('sif_transition')(
                        str(self.core_lua('control.lua')), str(self.core_lua('control.lua')),
                        str(self.core_lua('contract.lua')), str(self.core_lua('contract.lua')),
                        target, opponent))
                    self.assertFalse(result['ok'], result['message'])
                    self.assertIn(expected, result['message'])

    def test_control_protocol_requires_real_lab_events_restoration_and_read_only_reloads(self):
        for target in TARGETS:
            source,successor=self.core(target,'published'),self.core(target,'mir5')
            for path in (source,successor):
                self.assertTrue((path/'info.json').is_file())
                parsed=self.lua.eval('sif_parse')(str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')));self.assertTrue(parsed['ok'],parsed['message']);self.assertEqual({},plain(parsed['reads']));self.assertEqual({'init','load','configuration'},{key for key in parsed['callbacks'].keys() if key!='events'});self.assertEqual({1,2},set(parsed['callbacks']['events'].keys()))
            result=plain(self.lua.eval('sif_transition')(str(self.core_lua('control.lua')),str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),str(self.core_lua('contract.lua')),target,''));self.assertTrue(result['ok'],result['message']);self.assertTrue(result['scripted_ignored']);self.assertEqual((6,2,9,9),(result['reports'],result['saves'],result['research'],result['weapon']));self.assertAlmostEqual(1.2,result['lab']);self.assertAlmostEqual(.8,result['bullet']);self.assertAlmostEqual(.8,result['shotgun']);self.assertEqual((.42,.27),(result['state']['source_rows']['research-speed-7']['progress'],result['state']['source_rows']['weapon-shooting-speed-7']['progress']));self.assertEqual(set(result['state']['successor_consumption']['before']),set(result['state']['successor_consumption']['after']))
            bad=plain(self.lua.eval('sif_transition')(str(self.core_lua('control.lua')),str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),str(self.core_lua('contract.lua')),target,'source-state'));self.assertFalse(bad['ok']);self.assertIn('successor restored research-speed-7 technology state differs',bad['message'])
            bad=plain(self.lua.eval('sif_transition')(str(self.core_lua('control.lua')),str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),str(self.core_lua('contract.lua')),target,'source-progress'));self.assertFalse(bad['ok']);self.assertIn('successor restored research-speed-7 technology state differs',bad['message']);self.assertEqual(('source-complete',False),(bad['phase'],bad['current']))
            bad=plain(self.lua.eval('sif_transition')(str(self.core_lua('control.lua')),str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),str(self.core_lua('contract.lua')),target,'unit-count'));self.assertFalse(bad['ok']);self.assertIn('fixture acceleration differs',bad['message'])
            bad=plain(self.lua.eval('sif_transition')(str(self.core_lua('control.lua')),str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),str(self.core_lua('contract.lua')),target,'module'));self.assertFalse(bad['ok']);self.assertIn('real lab modules differ',bad['message'])
    def test_fresh_candidate_create_only_witness_is_read_only_and_not_an_upgrade(self):
        for target in TARGETS:
            for policy in POLICIES:
                result=plain(self.lua.eval('sif_candidate_create')(str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),target,policy,''))
                self.assertTrue(result['ok'],result['message']);self.assertEqual((0,1,True),(result['writes'],result['markers'],result['storage_empty']))
                self.assertEqual((f'sif-science-retirement-{target}-{policy}','init','passed'),(result['payload']['case'],result['payload']['stage'],result['payload']['status']))
                self.assertEqual((True,False,False),(result['payload']['witnesses']['fresh_candidate'],result['payload']['witnesses']['storage_writes'],result['payload']['witnesses']['native_state_writes']))
        for bad,expected in (('level','fresh candidate research-speed-7 state differs'),('bonus','fresh candidate native effects differ'),('unit-count','fixture acceleration differs')):
            result=plain(self.lua.eval('sif_candidate_create')(str(self.core_lua('control.lua')),str(self.core_lua('contract.lua')),'f200','configured',bad))
            self.assertFalse(result['ok']);self.assertIn(expected,result['message']);self.assertEqual((0,0),(result['writes'],result['markers']))

    def test_runtime_science_uses_exact_unique_names_and_amounts_without_array_order(self):
        for target in TARGETS:
            for policy in POLICIES:
                with self.subTest(target=target, policy=policy):
                    result = plain(self.lua.eval('sif_candidate_create')(
                        str(self.core_lua('control.lua')), str(self.core_lua('contract.lua')),
                        target, policy, 'science-permuted'))
                    self.assertTrue(result['ok'], result['message'])
                    self.assertEqual((0, 1, True),
                                     (result['writes'], result['markers'], result['storage_empty']))
            for bad, expected in (
                ('science-amount', 'automation-science-pack: expected 1, got 2'),
                ('science-duplicate', 'duplicate runtime science: automation-science-pack'),
                ('science-name', 'automation-science-pack: expected 1, got nil'),
                ('science-space', 'retained space science'),
            ):
                with self.subTest(target=target, opponent=bad):
                    result = plain(self.lua.eval('sif_candidate_create')(
                        str(self.core_lua('control.lua')), str(self.core_lua('contract.lua')),
                        target, 'configured', bad))
                    self.assertFalse(result['ok'], result['message'])
                    self.assertIn(expected, result['message'])
                    self.assertEqual((0, 0), (result['writes'], result['markers']))

    def test_profiles_pin_exact_archives_and_disclose_configured_only_transition(self):
        for target,meta in TARGETS.items():
            suffix=meta['engine'].replace('.','');expected={f'space-is-fake_{meta["sif"]}.zip':meta['sif_sha'],f'cr-commons_{meta["commons"]}.zip':meta['commons_sha'],'mir-fixture-mir5-active-mods-observer_0.1.0.zip':meta['observer_sha']}
            if target=='f210':expected[f'cr-extras_{meta["extras"]}.zip']=meta['extras_sha']
            published=json.loads((PROFILES/f'sif-science-retirement-published-configured-{target}-{suffix}.json').read_text());self.assertEqual(expected,published['archive_sha256']);self.assertIn('two actual named continuation labs',published['scope'])
            for policy in POLICIES:
                candidate=json.loads((PROFILES/f'sif-science-retirement-mir5-{policy}-{target}-{suffix}.json').read_text());mods={row['name']:row['version']for row in candidate['mods']};self.assertEqual((target,meta['line'],meta['engine'],meta['engine_sha'],'Defaults'),(candidate['target'],candidate['factorio_line'],candidate['engine']['version'],candidate['engine']['sha256'],candidate['settings_mode']));expected_mods={'base':meta['engine'],'elevated-rails':meta['engine'],'quality':meta['engine'],'space-age':meta['engine'],'cr-commons':meta['commons'],'space-is-fake':meta['sif'],'more-infinite-research':meta['candidate'],f'mir-fixture-mir5-sif-science-retirement-{target}':'0.2.0',f'mir-fixture-mir5-sif-policy-{policy}-{target}':'0.1.0','mir-fixture-mir5-active-mods-observer':'0.1.0'};
                if target=='f210':expected_mods.update({'recycler':meta['engine'],'cr-extras':meta['extras']})
                self.assertEqual(expected_mods,mods);self.assertEqual(expected,candidate['archive_sha256']);self.assertIn('does not qualify saved-game upgrade persistence',candidate['scope'])

    def test_current_f210_configured_successor_is_distinct_from_generic_candidate_policy(self):
        generic=json.loads((PROFILES/'sif-science-retirement-mir5-configured-f210-2123.json').read_text())
        current=json.loads((PROFILES/'sif-science-retirement-mir5-configured-current-f210-2123.json').read_text())
        meta=TARGETS['f210']
        self.assertEqual((1,'mir5-sif-science-retirement-current-successor','f210','2.1','Defaults'),
                         (current['schema'],current['kind'],current['target'],current['factorio_line'],current['settings_mode']))
        self.assertEqual((meta['engine'],meta['engine_sha']),
                         (current['engine']['version'],current['engine']['sha256']))
        self.assertEqual(generic['mods'],current['mods'])
        self.assertEqual(generic['archive_sha256'] | {
            'more-infinite-research_5.0.21000.zip': CURRENT_F210_ARCHIVE,
        },current['archive_sha256'])
        self.assertEqual(meta['observer_sha'],current['archive_sha256']['mir-fixture-mir5-active-mods-observer_0.1.0.zip'])
        self.assertIn(CURRENT_F210_SOURCE,current['scope'])
        self.assertIn(CURRENT_F210_PLAYER_TREE,current['scope'])
        self.assertIn(CURRENT_F210_ARCHIVE,current['scope'])
        self.assertIn(f'{CURRENT_F210_ARCHIVE_BYTES} bytes',current['scope'])
        self.assertIn('published4.7.21002 configured source save',current['scope'])
        self.assertIn('two source cold reloads',current['scope'])
        self.assertIn('two real successor BioLab completions',current['scope'])
        self.assertIn('queued 42% and paused 27%',current['scope'])
        self.assertIn('Prepared input only',current['scope'])

    def test_current_f210_policy_profiles_bind_each_fresh_zero_write_case(self):
        meta=TARGETS['f210']
        for policy in POLICIES:
            with self.subTest(policy=policy):
                generic=json.loads((PROFILES/f'sif-science-retirement-mir5-{policy}-f210-2123.json').read_text())
                filename=(f'sif-science-retirement-mir5-configured-current-f210-2123.json'
                          if policy == 'configured' else
                          f'sif-science-retirement-mir5-{policy}-current-f210-2123.json')
                current=json.loads((PROFILES/filename).read_text())
                self.assertEqual(generic['mods'],current['mods'])
                self.assertEqual(generic['archive_sha256'] | {
                    'more-infinite-research_5.0.21000.zip': CURRENT_F210_ARCHIVE,
                },current['archive_sha256'])
                self.assertEqual((meta['engine'],meta['engine_sha']),
                                 (current['engine']['version'],current['engine']['sha256']))
                self.assertIn(CURRENT_F210_SOURCE,current['scope'])
                self.assertIn(CURRENT_F210_PLAYER_TREE,current['scope'])
                self.assertIn(CURRENT_F210_ARCHIVE,current['scope'])
                self.assertIn(f'{CURRENT_F210_ARCHIVE_BYTES} bytes',current['scope'])
                self.assertIn('2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C',current['scope'])
                if policy == 'configured':
                    self.assertEqual('mir5-sif-science-retirement-current-successor',current['kind'])
                    self.assertIn('published4.7.21002 configured source save',current['scope'])
                else:
                    self.assertEqual('mir5-sif-science-retirement-current-policy',current['kind'])
                    self.assertIn(f'MIR5_SIF_CANDIDATE marker for sif-science-retirement-f210-{policy}',current['scope'])
                    self.assertIn('returns before a storage or native-state write',current['scope'])
                    self.assertIn('does not qualify saved-game upgrade persistence',current['scope'])
    def test_upstream_f210_control_omits_mir_without_changing_dependency_inputs(self):
        upstream=json.loads((PROFILES/'sif-upstream-f210-2123.json').read_text())
        candidate=json.loads((PROFILES/'sif-science-retirement-mir5-configured-f210-2123.json').read_text())
        meta=TARGETS['f210']
        expected={name:meta['engine'] for name in ('base','elevated-rails','quality','recycler','space-age')}
        expected.update({'cr-commons':meta['commons'],'cr-extras':meta['extras'],
          'space-is-fake':meta['sif'],'mir-fixture-mir5-active-mods-observer':'0.1.0'})
        self.assertEqual(expected,{row['name']:row['version'] for row in upstream['mods']})
        self.assertEqual(len(expected),len(upstream['mods']))
        self.assertTrue(all(row['enabled'] is True for row in upstream['mods']))
        omitted={'more-infinite-research','mir-fixture-mir5-sif-science-retirement-f210',
          'mir-fixture-mir5-sif-policy-configured-f210'}
        self.assertEqual([row for row in candidate['mods'] if row['name'] not in omitted],upstream['mods'])
        for key in ('target','factorio_line','engine','settings_mode','archive_sha256'):
            self.assertEqual(candidate[key],upstream[key],key)
        self.assertEqual('Defaults',upstream['settings_mode'])
        self.assertEqual('f210',upstream['target'])

    def test_fixture_metadata_binds_exact_source_and_selector_closures(self):
        for target,meta in TARGETS.items():
            core_name=f'mir-fixture-mir5-sif-science-retirement-{target}'
            for stage,version,mir in (('published','0.1.0',meta['published']),('mir5','0.2.0',meta['candidate'])):
                info=json.loads((self.core(target,stage)/'info.json').read_text())
                expected_dependencies=[f'base = {meta["engine"]}',f'space-age = {meta["engine"]}',f'space-is-fake = {meta["sif"]}',f'cr-commons = {meta["commons"]}']
                if target=='f210':expected_dependencies.append(f'cr-extras = {meta["extras"]}')
                expected_dependencies.append(f'more-infinite-research = {mir}')
                self.assertEqual((core_name,version,meta['line'],expected_dependencies),(info['name'],info['version'],info['factorio_version'],info['dependencies']))
            for policy in POLICIES:
                info=json.loads((FIXTURE/target/f'policy-{policy}'/'info.json').read_text())
                self.assertEqual((f'mir-fixture-mir5-sif-policy-{policy}-{target}','0.1.0',meta['line'],[f'base = {meta["engine"]}',f'{core_name} >= 0.1.0']),
                                 (info['name'],info['version'],info['factorio_version'],info['dependencies']))

    def test_private_fixture_lua_has_one_explicit_shared_staging_authority(self):
        expected={CORE/'contract.lua',CORE/'data-final-fixes.lua',CORE/'control.lua'} | {self.selector_lua(policy) for policy in POLICIES}
        actual=set(FIXTURE.rglob('*.lua'));self.assertEqual(expected,actual)
        for path in actual:
            text=path.read_text();self.assertNotIn('__more-infinite-research__',text);self.assertNotIn('require("research.',text);self.assertNotIn('require("compatibility.',text)
        for target in TARGETS:
            for stage in ('published','mir5'):
                self.assertEqual([],list(self.core(target,stage).glob('*.lua')))
            for policy in POLICIES:self.assertEqual([],list((FIXTURE/target/f'policy-{policy}').glob('*.lua')))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--lua-runtime-dir',type=Path,required=True);args=parser.parse_args();sys.path.insert(0,str(args.lua_runtime_dir.resolve(strict=True)));from lupa.lua52 import LuaRuntime
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SIFScienceRetirementFixtureTests));sys.exit(0 if result.wasSuccessful() else 1)
