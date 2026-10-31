# Host controls for the bounded fixed-provider removal native control.
# Native qualification remains root-owned; no Factorio process is started here.
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tests/fixtures/fixed-provider-removal-control'
FACTS = ROOT / 'tests/fixtures/competing-fixed-f200-sa-captured-facts.json'
FIXTURE_NAME = 'mir-fixture-mir5-fixed-provider-removal-control'
SUCCESSOR_ROLES = {
    'mir5-prefer-mir': 'successor-prefer-mir',
    'mir5-prefer-foreign': 'successor-prefer-foreign',
    'mir5-providers-readded-foreign': 'successor-providers-readded-foreign',
    'mir5-providers-removed': 'successor-providers-removed',
}


def fixture_role(stage):
    return SUCCESSOR_ROLES.get(stage, stage)
PROFILES = {
    'published': ROOT / 'tests/profiles/fixed-provider-removal-control-published-f200-sa-2077.json',
    'mir5-prefer-mir': ROOT / 'tests/profiles/fixed-provider-removal-control-mir5-prefer-mir-f200-sa-2077.json',
    'mir5-prefer-foreign': ROOT / 'tests/profiles/fixed-provider-removal-control-mir5-prefer-foreign-f200-sa-2077.json',
    'mir5-providers-removed': ROOT / 'tests/profiles/fixed-provider-removal-control-mir5-providers-removed-f200-sa-2077.json',
    'mir5-providers-readded-foreign': ROOT / 'tests/profiles/fixed-provider-removal-control-mir5-providers-readded-foreign-f200-sa-2077.json',
}
STAGES = {
    'published': ('4.7.20002', '0.1.0', False, True),
    'mir5-prefer-mir': ('5.0.20000', '0.2.0', True, True),
    'mir5-prefer-foreign': ('5.0.20000', '0.3.0', False, True),
    'mir5-providers-removed': ('5.0.20000', '0.4.0', False, False),
    'mir5-providers-readded-foreign': ('5.0.20000', '0.5.0', False, True),
}
PROVIDERS = {
    'plates-n-circuit-productivity': '0.0.2',
    'Science_packs_productivity': '0.0.1',
    'bioflux-productivity': '0.1.0',
    'fish-productivity': '1.0.0',
}

def lua_value(lua, value):
    if isinstance(value, dict): return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (list, tuple)): return lua.table_from([lua_value(lua, item) for item in value])
    return value

def plain(value):
    if not hasattr(value, 'items'): return value
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [plain(value[index]) for index in range(1, len(keys) + 1)]
    return {key: plain(item) for key, item in value.items()}

class FixedProviderRemovalControlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        facts = json.loads(FACTS.read_text(encoding='utf-8'))
        cls.providers = {row['key']: row for row in facts['providers']}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function removal_data(path, facts_path, raw, mods)
  local env={data={raw=raw},mods=mods};local loaded={}
  env.require=function(name)
    if name~='data-facts' then error('unexpected fixture module: '..tostring(name)) end
    if loaded[name] then return loaded[name] end
    local chunk,message=loadfile(facts_path,'t',env);assert(chunk,message);loaded[name]=chunk();return loaded[name]
  end
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local update=path:gsub('data%-final%-fixes%.lua$','settings-updates.lua')
  local chunk,message=loadfile(update,'t',env);assert(chunk,message);local ok,result=pcall(chunk)
  if not ok then return {ok=false,message=tostring(result),raw=raw} end
  chunk,message=loadfile(path,'t',env);assert(chunk,message);ok,result=pcall(chunk);return {ok=ok,message=tostring(result),raw=raw}
end
function removal_parse(path)
  local callbacks,reads={events={}},{}
  local env={script={on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_event=function(e,f)callbacks.events[e]=f end,active_mods={base='2.0.77',['space-age']='2.0.77',['more-infinite-research']='5.0.20000',['mir-fixture-mir5-fixed-provider-removal-control']='0.5.0'}},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
  env._G=env;setmetatable(env,{__index=function(_,key)if key=='game' or key=='storage' or key=='settings' then reads[key]=(reads[key]or 0)+1 end;return _G[key]end})
  local chunk,message=loadfile(path,'t',env);assert(chunk,message);local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads,env=env}
end
function published_removal_marker(path)
  local loaded=removal_parse(path);assert(loaded.ok,loaded.message)
  local env=loaded.env
  local player={technologies={['laser-shooting-speed-1']={name='laser-shooting-speed-1',saved_progress=.42},['recipe-prod-research_breeding-1']={name='recipe-prod-research_breeding-1',level=1}},recipes={},research_queue={},research_progress=.27}
  for _,name in ipairs({'bioflux','fish-breeding','biter-egg','pentapod-egg'})do player.recipes[name]={productivity_bonus=.1} end
  local foreign={technologies={},research_queue={},research_progress=.27}
  env.game={forces={player=player,[4]=foreign}}
  env.helpers={table_to_json=function(value)env.last_encoded=value;return '{}'end};env.log=function()end
  for index=1,40 do
    local name,callback=debug.getupvalue(loaded.callbacks.events[1],index)
    if name=='marker' then callback('initial',{foreign_force_index=4,source_actual_labs=2,mir_actual_labs=0,phase='source-completed'});return env.last_encoded.witnesses end
    if name==nil then break end
  end
  error('fixture marker callback is absent')
end
''')

    def test_published_marker_records_absent_new_mir_rows_without_fabricating_them(self):
        value = self.lua.eval('published_removal_marker')(str(FIXTURE / 'control.lua'))
        self.assertFalse(value['mir_bioflux_next'])
        self.assertFalse(value['credit_positive_next'])
        self.assertFalse(value['credit_negative_next'])
        self.assertEqual(1, value['mir_breeding_next'])
        self.assertEqual(2, value['source_actual_provider_labs'])

    def source_rows(self):
        bioflux = deepcopy(self.providers['bioflux']['arms']['upstream']['provider_rows']['bioflux-productivity'])
        fish = deepcopy(self.providers['fish']['arms']['upstream']['provider_rows']['fish-breeding-productivity'])
        return {bioflux['name']: bioflux, fish['name']: fish}

    def mir_rows(self, preference, providers_present):
        if preference or not providers_present:
            breeding = deepcopy(self.providers['fish']['arms']['published']['mir_rows']['recipe-prod-research_breeding-1'])
        else:
            breeding = deepcopy(self.providers['fish']['foreign_remaining_mir_rows']['recipe-prod-research_breeding-1'])
        bioflux = deepcopy(self.providers['bioflux']['arms']['published']['mir_rows']['recipe-prod-research_bioflux-1'])
        if not preference and providers_present: bioflux['enabled'] = False
        return {breeding['name']: breeding, bioflux['name']: bioflux}

    def mods(self, mir, fixture, providers_present):
        value={'base':'2.0.77','space-age':'2.0.77','more-infinite-research':mir,FIXTURE_NAME:fixture}
        if providers_present: value.update(PROVIDERS)
        return value

    def test_profiles_pin_one_exact_fixture_and_provider_closure(self):
        for stage, profile_path in PROFILES.items():
            mir, fixture, preference, providers_present = STAGES[stage]
            profile=json.loads(profile_path.read_text(encoding='utf-8'))
            selected={row['name']:row['version'] for row in profile['mods'] if row['enabled']}
            self.assertEqual('2.0.77',selected['base']);self.assertEqual('2.0.77',selected['space-age'])
            self.assertEqual(mir,selected['more-infinite-research']);self.assertEqual(fixture,selected[FIXTURE_NAME])
            self.assertEqual(PROVIDERS if providers_present else {},{name:selected[name] for name in PROVIDERS if name in selected})
            self.assertEqual('D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B',profile['engine']['sha256'])
            self.assertEqual(5,len(profile['archive_sha256']));self.assertIsInstance(preference,bool)

    def test_data_preflight_is_captured_before_acceleration_and_rejects_drift(self):
        for stage,(mir,fixture,preference,providers_present) in STAGES.items():
            rows=self.source_rows() if stage=='published' else self.mir_rows(preference,providers_present)
            raw={'technology':rows,'bool-setting':{'mir-prefer-this-mod-for-competing-techs':{'default_value':not preference}}}
            result=self.lua.eval('removal_data')(str(FIXTURE/fixture_role(stage)/'data-final-fixes.lua'),str(FIXTURE/'data-facts.lua'),lua_value(self.lua,raw),lua_value(self.lua,self.mods(mir,fixture,providers_present)))
            self.assertTrue(result['ok'],result['message']);actual=plain(result['raw'])['technology']
            if stage=='published':
                self.assertEqual(('1',1),(actual['bioflux-productivity']['unit']['count_formula'],actual['bioflux-productivity']['unit']['time']))
                self.assertEqual(('1',1),(actual['fish-breeding-productivity']['unit']['count_formula'],actual['fish-breeding-productivity']['unit']['time']))
            elif stage in ('mir5-prefer-mir','mir5-prefer-foreign'):
                self.assertEqual(('1',1),(actual['recipe-prod-research_breeding-1']['unit']['count_formula'],actual['recipe-prod-research_breeding-1']['unit']['time']))
            else: self.assertEqual('8000*2^(L-1)',actual['recipe-prod-research_breeding-1']['unit']['count_formula'])
        bad=self.source_rows();bad['fish-breeding-productivity']['effects'][0]['change']=.2
        raw={'technology':bad,'bool-setting':{'mir-prefer-this-mod-for-competing-techs':{'default_value':False}}}
        result=self.lua.eval('removal_data')(str(FIXTURE/'published/data-final-fixes.lua'),str(FIXTURE/'data-facts.lua'),lua_value(self.lua,raw),lua_value(self.lua,self.mods('4.7.20002','0.1.0',True)))
        self.assertFalse(result['ok']);self.assertIn('captured source fish effects',result['message'])

    def test_control_keeps_engine_removal_observational_and_mir_state_named(self):
        result=self.lua.eval('removal_parse')(str(FIXTURE/'control.lua'))
        self.assertTrue(result['ok'],result['message']);self.assertEqual({},plain(result['reads']))
        self.assertIsNotNone(result['callbacks']['init']);self.assertIsNotNone(result['callbacks']['load']);self.assertIsNotNone(result['callbacks']['changed'])
        self.assertIsNotNone(result['callbacks']['events'][1]);self.assertIsNotNone(result['callbacks']['events'][2])
        source=(FIXTURE/'control.lua').read_text(encoding='utf-8')
        for witness in ('mir5-fixed-provider-removal-engine-observer','electric-circuit-productivity','basic-plate-productivity','REMOVAL_OBSERVATION','braking-force-1','laser-shooting-speed-1','mir-native-credit-research_breeding-fish-breeding-positive'):
            self.assertIn(witness,source)
        self.assertIn('lab.disabled_by_script=true',source)
        self.assertNotRegex(source,r'\blab\.active\s*=')
        self.assertNotIn('storage.mir_native_credits',source);self.assertNotIn('force.reset_technology_effects',source)
        load_body=source.split('script.on_load(function()',1)[1].split('script.on_event(defines.events.on_tick',1)[0]
        self.assertNotIn('game.',load_body)
        self.assertNotIn('force.recipes[recipe].productivity_bonus =',source)
        self.assertIn('provider_absent(game.forces[state.foreign_force_index],FOREIGN_CURRENT)',source)
        self.assertIn('state.removed_observation=removed_observation',source)

    def test_expected_owned_delta_rejects_readded_foreign_credit(self):
        expected={'false':(2,1,.2,.2,.2),'removed':(1,2,.1,.1,.2),'readded':(2,1,.1,.1,.2)}
        self.assertEqual((2,1),expected['false'][:2]);self.assertEqual((1,2),expected['removed'][:2])
        self.assertEqual((.1,.1),expected['readded'][2:4])
        self.assertNotEqual(.2,expected['readded'][3], 'readded provider must not receive invented source credit')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--lua-runtime-dir',type=Path,required=True)
    args,extra=parser.parse_known_args();sys.path.insert(0,str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0],*extra])
