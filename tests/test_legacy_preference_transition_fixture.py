# Host controls for the prepared F200 legacy competing-preference transition.
# They exercise a native-shaped fixture mock only; native save qualification is
# intentionally owned by the Black Glass worker.
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'tests/fixtures/legacy-preference-transition'
FACTS = ROOT / 'tests/fixtures/competing-fixed-f200-sa-captured-facts.json'
NAME = 'mir-fixture-mir5-legacy-preference-transition'
VARIANTS = {
    'published-false': ('4.7.20002', '0.1.0', False),
    'published-true': ('4.7.20002', '0.1.1', True),
    'published-473-false': ('4.7.20003', '0.1.2', False),
    'published-473-true': ('4.7.20003', '0.1.3', True),
    'mir5-false': ('5.0.20000', '0.2.0', False),
    'mir5-true': ('5.0.20000', '0.2.1', True),
}


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (list, tuple)):
        return lua.table_from([lua_value(lua, item) for item in value])
    return value


def plain(value, seen=None):
    if not hasattr(value, 'items'):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError('cyclic Lua fixture result')
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


class LegacyPreferenceTransitionFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        facts = json.loads(FACTS.read_text(encoding='utf-8'))
        fish = next(item for item in facts['providers'] if item['key'] == 'fish')
        cls.full = fish['arms']['published']['mir_rows']['recipe-prod-research_breeding-1']
        cls.reduced = fish['foreign_remaining_mir_rows']['recipe-prod-research_breeding-1']

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        fixture_path = str(FIXTURE.resolve()).replace('\\', '/')
        self.lua.execute(f'package.path = "{fixture_path}/?.lua;" .. package.path')
        self.lua.execute(r'''
function legacy_fixture_data(path, common_path, row, mir, fixture, preference, runtime_preference)
  if runtime_preference == nil then runtime_preference = preference end
  local raw={technology={['recipe-prod-research_breeding-1']=row},
    ['bool-setting']={['mir-prefer-this-mod-for-competing-techs']={default_value=not preference}}}
  local env={mods={base='2.0.77',['space-age']='2.0.77',['more-infinite-research']=mir,
    ['mir-fixture-mir5-legacy-preference-transition']=fixture,
    ['plates-n-circuit-productivity']='0.0.2',Science_packs_productivity='0.0.1',
    ['bioflux-productivity']='0.1.0',['fish-productivity']='1.0.0'},data={raw=raw},
    settings={startup={['mir-prefer-this-mod-for-competing-techs']={value=runtime_preference}}}}
  local common
  env.require=function(name)
    if name ~= 'data-final-common' then error('unexpected fixture module: ' .. tostring(name)) end
    if common ~= nil then return common end
    local shared,message=loadfile(common_path,'t',env);assert(shared,message);common=shared();return common
  end
  env._G=env;setmetatable(env,{__index=function(_, key)return _G[key]end})
  local update=path:gsub('data%-final%-fixes%.lua$','settings-updates.lua')
  local chunk,message=loadfile(update,'t',env);assert(chunk,message);local ok,result=pcall(chunk)
  if not ok then return {ok=false,message=tostring(result),raw=raw} end
  local setting_default=raw['bool-setting']['mir-prefer-this-mod-for-competing-techs'].default_value
  raw['bool-setting']=nil
  chunk,message=loadfile(path,'t',env);assert(chunk,message);ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),raw=raw,setting_default=setting_default}
end
function legacy_fixture_parse(path, mir, fixture, preference)
  local callbacks,reads={events={}},{ }
  local env={script={active_mods={base='2.0.77',['space-age']='2.0.77',['more-infinite-research']=mir,
    ['mir-fixture-mir5-legacy-preference-transition']=fixture,
    ['plates-n-circuit-productivity']='0.0.2',Science_packs_productivity='0.0.1',
    ['bioflux-productivity']='0.1.0',['fish-productivity']='1.0.0'},
    on_init=function(f) callbacks.init=f end,on_load=function(f) callbacks.load=f end,
    on_configuration_changed=function(f) callbacks.changed=f end,on_event=function(e,f) callbacks.events[e]=f end},
    defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
    settings={startup={['mir-prefer-this-mod-for-competing-techs']={value=preference}}}}
  env._G=env;setmetatable(env,{__index=function(_,key)
    if key=='game' or key=='storage' then reads[key]=(reads[key]or 0)+1 end
    return _G[key]
  end})
  local chunk,message=loadfile(path,'t',env);assert(chunk,message);local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end
function legacy_fixture_flow(path, source_preference, opponent, source_mir)
  source_mir = source_mir or '4.7.20002'
  local callbacks,markers,saves={events={}},0,0
  local function inventory()
    local values={items={}}
    function values.clear() values.items={} end
    function values.insert(stack) values.items[stack.name]=(values.items[stack.name]or 0)+stack.count;return stack.count end
    function values.get_item_count(name) return values.items[name]or 0 end
    return values
  end
  local input=inventory();local lab={valid=true,disabled_by_script=true,energy=0}
  function lab.get_inventory(_) return input end
  local function research(force,name)
    return {name=name,valid=true,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
      prototype={max_level=4294967295,hidden=false,effects={{type='change-recipe-productivity',recipe='fish-breeding',change=.1}}},
      prerequisites={},research_unit_count=1,research_unit_energy=60,
      research_unit_ingredients={{name='automation-science-pack',amount=1}}}
  end
  local function force(name,index)
    local value={name=name,index=index,valid=true,technologies={},recipes={},research_queue={},research_progress=0}
    for _,recipe in ipairs({'biter-egg','fish-breeding','pentapod-egg'}) do value.recipes[recipe]={productivity_bonus=0} end
    value.technologies['recipe-prod-research_breeding-1']=research(value,'recipe-prod-research_breeding-1')
    value.technologies['braking-force-1']=research(value,'braking-force-1')
    function value.add_research(item)
      value.current_research=item;value.research_queue={item};value.research_progress=item.saved_progress or 0;item.saved_progress=0;return true
    end
    return value
  end
  local player=force('player',1);local foreign
  local game={tick=1,forces={player=player,[1]=player},surfaces={[1]={create_entity=function(_) return lab end}}}
  function game.create_force(name) foreign=force(name,2);game.forces[2]=foreign;game.forces[name]=foreign;return foreign end
  function game.server_save(name) assert(name=='mir5-native-complete');saves=saves+1 end
  local source_fixture=source_preference and '0.1.1' or '0.1.0'
  if source_mir=='4.7.20003' and opponent~='wrong-source-fixture' then
    source_fixture=source_preference and '0.1.3' or '0.1.2'
  end
  local active={base='2.0.77',['space-age']='2.0.77',['more-infinite-research']=source_mir,
    ['mir-fixture-mir5-legacy-preference-transition']=source_fixture,
    ['plates-n-circuit-productivity']='0.0.2',Science_packs_productivity='0.0.1',
    ['bioflux-productivity']='0.1.0',['fish-productivity']='1.0.0'}
  local setting={value=source_preference}
  local env={script={active_mods=active,on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,
    on_configuration_changed=function(f)callbacks.changed=f end,on_event=function(e,f)callbacks.events[e]=f end},
    defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage={},
    settings={startup={['mir-prefer-this-mod-for-competing-techs']=setting}},
    helpers={table_to_json=function(value) assert(value.status=='passed' and (value.stage=='initial'or value.stage=='reload'));return '{}'end},
    log=function(value) assert(value:match('^%[MIR5_NATIVE_FIXTURE%] RESULT '));markers=markers+1 end}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(path,'t',env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)}end
  ok,result=pcall(callbacks.init);if not ok then return {ok=false,message=tostring(result)}end
  local row=player.technologies['recipe-prod-research_breeding-1']
  local function finish(recipes)
    row.level=row.level+1;player.current_research=nil;player.research_queue={};player.research_progress=0
    for _,recipe in ipairs(recipes) do player.recipes[recipe].productivity_bonus=player.recipes[recipe].productivity_bonus+.1 end
    local event_ok,event_result=pcall(callbacks.events[2],{research=row});if not event_ok then return false,tostring(event_result)end
    event_ok,event_result=pcall(callbacks.events[1]);if not event_ok then return false,tostring(event_result)end
    return true,''
  end
  local source_recipes=source_preference and {'biter-egg','fish-breeding','pentapod-egg'} or {'biter-egg','pentapod-egg'}
  local done;done,message=finish(source_recipes);if not done then return {ok=false,message=message}end
  callbacks.events[1]()
  done,message=finish(source_recipes);if not done then return {ok=false,message=message}end
  callbacks.events[1]()
  if opponent=='lost-source-mir' then env.storage.mir5_legacy_preference_transition.source_mir='4.7.20004' end
  active['more-infinite-research']='5.0.20000';active['mir-fixture-mir5-legacy-preference-transition']=source_preference and '0.2.1' or '0.2.0'
  local function carrier(name,level)
    local value=research(player,name);value.level=level;value.enabled=false;value.prototype.hidden=true;value.prototype.max_level=4294967295;return value
  end
  player.technologies['mir-native-credit-research_breeding-fish-breeding-positive']=carrier('mir-native-credit-research_breeding-fish-breeding-positive',1)
  player.technologies['mir-native-credit-research_breeding-fish-breeding-negative']=carrier('mir-native-credit-research_breeding-fish-breeding-negative',1)
  if opponent=='bad-first-event' then setting.value=source_preference;ok,result=pcall(callbacks.changed,{mod_startup_settings_changed=true})
  else ok,result=pcall(callbacks.changed,{mod_startup_settings_changed=false}) end
  if not ok then return {ok=false,message=tostring(result)}end
  callbacks.events[1]()
  if opponent=='bad-first-event' then return {ok=false,message='first event unexpectedly passed'} end
  local switched=not source_preference;setting.value=switched;active['mir-fixture-mir5-legacy-preference-transition']=switched and '0.2.1' or '0.2.0'
  if source_preference then player.technologies['mir-native-credit-research_breeding-fish-breeding-positive'].level=3
  else player.technologies['mir-native-credit-research_breeding-fish-breeding-negative'].level=3 end
  if opponent=='lost-source-fish' then player.recipes['fish-breeding'].productivity_bonus=player.recipes['fish-breeding'].productivity_bonus-.1 end
  ok,result=pcall(callbacks.changed,{mod_startup_settings_changed=true});if not ok then return {ok=false,message=tostring(result)}end
  local switched_recipes=switched and {'biter-egg','fish-breeding','pentapod-egg'} or {'biter-egg','pentapod-egg'}
  done,message=finish(switched_recipes);if not done then return {ok=false,message=message}end
  callbacks.events[1]()
  return {ok=true,message='',phase=env.storage.mir5_legacy_preference_transition.phase,markers=markers,saves=saves,
    level=row.level,fish=player.recipes['fish-breeding'].productivity_bonus,
    biter=player.recipes['biter-egg'].productivity_bonus,pentapod=player.recipes['pentapod-egg'].productivity_bonus,
    foreign_progress=foreign.research_progress,source_mir=env.storage.mir5_legacy_preference_transition.source_mir}
end
''')

    def row(self, preference):
        return deepcopy(self.full if preference else self.reduced)

    def test_473_source_runs_the_same_bounded_flow_without_accepting_mixed_stage_ids(self):
        run = self.lua.eval('legacy_fixture_flow')
        for preference, fish in ((False, .1), (True, .2)):
            result = run(str(FIXTURE / 'control.lua'), preference, '', '4.7.20003')
            self.assertTrue(result['ok'], result['message'])
            self.assertEqual('4.7.20003', result['source_mir'])
            self.assertEqual(('m5-switch-complete', 3, 3, 4),
                             (result['phase'], result['markers'], result['saves'], result['level']))
            self.assertAlmostEqual(fish, result['fish'])
            self.assertAlmostEqual(.42, result['foreign_progress'])
        for opponent, phrase in (
                ('wrong-source-fixture', 'fixture/MIR version differs'),
                ('lost-source-mir', 'published source witness differs'),
                ('bad-first-event', 'unchanged first upgrade reported startup settings changed'),
                ('lost-source-fish', 'MIR5 preference switch productivity differs: fish-breeding')):
            result = run(str(FIXTURE / 'control.lua'), True, opponent, '4.7.20003')
            self.assertFalse(result['ok'])
            self.assertIn(phrase, result['message'])

    def test_473_profiles_pin_the_public_archive_and_preserve_the_original_upstream_closure(self):
        profiles = ROOT / 'tests/profiles'
        for mode, version in (('false', '0.1.2'), ('true', '0.1.3')):
            original = json.loads((profiles / f'legacy-preference-transition-published-{mode}-f200-sa-2077.json').read_text())
            current = json.loads((profiles / f'legacy-preference-transition-published-473-{mode}-f200-sa-2077.json').read_text())
            for field in ('schema', 'kind', 'target', 'factorio_line', 'engine', 'settings_mode'):
                self.assertEqual(original[field], current[field], field)
            expected = deepcopy(original['mods'])
            for row in expected:
                if row['name'] == 'more-infinite-research': row['version'] = '4.7.20003'
                if row['name'] == NAME: row['version'] = version
            self.assertEqual(expected, current['mods'])
            old_info = json.loads((FIXTURE / f'published-{mode}' / 'info.json').read_text())
            new_info = json.loads((FIXTURE / f'published-473-{mode}' / 'info.json').read_text())
            self.assertEqual([value.replace('more-infinite-research = 4.7.20002',
                                            'more-infinite-research = 4.7.20003')
                              for value in old_info['dependencies']], new_info['dependencies'])
            hashes = dict(current['archive_sha256'])
            self.assertEqual('FBBA844DD04011A12BB6DA885745B0733AD37FAB181EAAD9EE4346B9B0D32647',
                             hashes.pop('more-infinite-research_4.7.20003.zip'))
            self.assertEqual(original['archive_sha256'], hashes)
            self.assertEqual(f'published-473-{mode}', current['fixture_variant'])
            self.assertEqual('8643cc91bc915e008556a5315dbb0a743247e7ab',
                             current['published_predecessor']['source_commit'])
            result = self.lua.eval('legacy_fixture_data')(
                str(FIXTURE / f'published-473-{mode}' / 'data-final-fixes.lua'),
                str(FIXTURE / 'data-final-common.lua'), lua_value(self.lua, self.row(mode == 'true')),
                '4.7.20002', version, mode == 'true')
            self.assertFalse(result['ok'], 'new role accepted the old MIR distribution')
            untouched = plain(result['raw']['technology']['recipe-prod-research_breeding-1'])
            self.assertEqual((None, '8000*2^(L-1)', 60),
                             (untouched['unit'].get('count'), untouched['unit'].get('count_formula'), untouched['unit']['time']))

    def test_all_stage_metadata_and_exact_preflight_precede_acceleration(self):
        for directory, (mir, fixture, preference) in VARIANTS.items():
            with self.subTest(directory=directory):
                info = json.loads((FIXTURE / directory / 'info.json').read_text(encoding='utf-8'))
                self.assertEqual((NAME, fixture, '2.0'), (info['name'], info['version'], info['factorio_version']))
                self.assertIn(f'more-infinite-research = {mir}', info['dependencies'])
                result = self.lua.eval('legacy_fixture_data')(str(FIXTURE / directory / 'data-final-fixes.lua'), str(FIXTURE / 'data-final-common.lua'),
                    lua_value(self.lua, self.row(preference)), mir, fixture, preference)
                self.assertTrue(result['ok'], result['message'])
                row = plain(result['raw']['technology']['recipe-prod-research_breeding-1'])
                self.assertEqual(preference, result['setting_default'])
                self.assertNotIn('bool-setting', plain(result['raw']))
                self.assertEqual((1, None, 1), (row['unit'].get('count'), row['unit'].get('count_formula'), row['unit']['time']))
                expected = [effect['recipe'] for effect in self.row(preference)['effects']]
                self.assertEqual(expected, [effect['recipe'] for effect in row['effects']])
        changed = self.row(True)
        changed['effects'][1]['change'] = .2
        result = self.lua.eval('legacy_fixture_data')(str(FIXTURE / 'published-true' / 'data-final-fixes.lua'), str(FIXTURE / 'data-final-common.lua'),
            lua_value(self.lua, changed), '4.7.20002', '0.1.1', True)
        self.assertFalse(result['ok'])
        self.assertIn('captured MIR breeding effect changed', result['message'])
        wrong_runtime = self.lua.eval('legacy_fixture_data')(str(FIXTURE / 'published-true' / 'data-final-fixes.lua'),
            str(FIXTURE / 'data-final-common.lua'), lua_value(self.lua, self.row(True)), '4.7.20002', '0.1.1', True, False)
        self.assertFalse(wrong_runtime['ok'])
        self.assertIn('fixture preference setting differs', wrong_runtime['message'])
        untouched = plain(wrong_runtime['raw']['technology']['recipe-prod-research_breeding-1'])
        self.assertEqual((None, '8000*2^(L-1)', 60),
            (untouched['unit'].get('count'), untouched['unit'].get('count_formula'), untouched['unit']['time']))

    def test_controls_are_parse_time_only_and_source_to_switch_flow_is_bounded(self):
        source = (FIXTURE / 'control.lua').read_text(encoding='utf-8')
        on_load = source.split('script.on_load(function()', 1)[1].split('script.on_configuration_changed', 1)[0]
        self.assertNotIn('game.', on_load)
        self.assertNotRegex(on_load, r'storage\\s*\\[.*?\\]\\s*=')
        self.assertIn('simultaneous first preference switch reached fixture after MIR guard', source)
        self.assertIn('event.mod_startup_settings_changed ~= false', source)
        self.assertIn('event.mod_startup_settings_changed ~= true', source)
        self.assertIn('foreign.research_progress = .42', source)
        self.assertIn('game.server_save(SAVE)', source)
        for directory, (mir, fixture, preference) in VARIANTS.items():
            result = self.lua.eval('legacy_fixture_parse')(str(FIXTURE / 'control.lua'), mir, fixture, preference)
            self.assertTrue(result['ok'], result['message'])
            self.assertEqual({}, plain(result['reads']))
            self.assertIsNotNone(result['callbacks']['load'])
            if mir.startswith('4.7.'): self.assertIsNotNone(result['callbacks']['init'])
            else: self.assertIsNotNone(result['callbacks']['changed'])
        run = self.lua.eval('legacy_fixture_flow')
        expected = {False: (4, .1, .3, .3), True: (4, .2, .3, .3)}
        for source_preference, values in expected.items():
            with self.subTest(source_preference=source_preference):
                result = run(str(FIXTURE / 'control.lua'), source_preference, '')
                self.assertTrue(result['ok'], result['message'])
                self.assertEqual(('m5-switch-complete', 3, 3, values[0]),
                    (result['phase'], result['markers'], result['saves'], result['level']))
                for actual, expected_rate in zip((result['fish'], result['biter'], result['pentapod'],
                                                   result['foreign_progress']), (*values[1:], .42)):
                    self.assertAlmostEqual(expected_rate, actual, places=6)
        for opponent, phrase in (('bad-first-event', 'unchanged first upgrade reported startup settings changed'),
                                 ('lost-source-fish', 'MIR5 preference switch productivity differs: fish-breeding')):
            result = run(str(FIXTURE / 'control.lua'), True, opponent)
            self.assertFalse(result['ok'])
            self.assertIn(phrase, result['message'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua-runtime-dir', type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyPreferenceTransitionFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
