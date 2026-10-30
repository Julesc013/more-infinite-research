"""Independent native-shaped controls for protected published F100 witnesses.

These tests exercise fixture transactions, not Factorio or release acceptance.
"""
import argparse
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import sys
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/published-f100-forward"


class PublishedF100ForwardControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function forward_flow(control_path, source_plan, target_plan, definitions, opponent, bridge_plan)
  local function clone(value)
    if type(value)~="table"then return value end
    local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out
  end
  local plan=assert(loadfile(source_plan))()
  local current=plan
  local markers,saves={},0
  local force_list={}
  local packs={"military-science-pack","utility-science-pack"}
  local function inventory(count)
    local inv={values={}}
    for _,n in ipairs(packs)do
      inv.values[n]=count
      inv[#inv+1]={name=n,valid_for_read=count>0,count=count,durability=1}
    end
    function inv.get_item_count(n)return inv.values[n]or 0 end
    function inv.insert(r)
      inv.values[r.name]=(inv.values[r.name]or 0)+r.count
      for _,stack in ipairs(inv)do if stack.name==r.name then stack.valid_for_read=true;stack.count=stack.count+r.count end end
      return r.count
    end
    return inv
  end
  local source_input=inventory(31)
  local source_lab={valid=true,active=false,energy=0,get_inventory=function()return source_input end}
  local labs={}
  local function make_force(name)
    local f={name=name,valid=true,technologies={},research_queue_enabled=true,research_queue={},
      research_progress=0,manual_mining_speed_modifier=0,laboratory_speed_modifier=0,laboratory_productivity_bonus=0,
      inserter_stack_size_bonus=0,stack_inserter_capacity_bonus=0,bulk_inserter_capacity_bonus=0,bonus=0}
    for n,definition in pairs(definitions)do
      local proto=clone(definition)
      local t={name=n,valid=true,force=f,level=proto.level,researched=false,enabled=true,
        visible_when_disabled=false,prototype=proto,prerequisites={},saved_progress=0}
      f.technologies[n]=t
    end
    f.technologies["braking-force-1"]={name="braking-force-1",valid=true,force=f,researched=false,enabled=true,prerequisites={}}
    function f.get_saved_technology_progress(t)return t.saved_progress~=0 and t.saved_progress or nil end
    function f.set_saved_technology_progress(t,v)t.saved_progress=v end
    function f.add_research(t)f.research_queue[#f.research_queue+1]=t;f.current_research=f.research_queue[1];return true end
    function f.get_gun_speed_modifier(ammo)assert(ammo==current.ammo);return f.bonus end
    function f.get_spawn_position()return{x=0,y=0}end
    function f.reset_technology_effects()
      f.bonus=0
      for i=1,7 do if f.technologies[current.laser_prefix..i].researched then f.bonus=f.bonus+({.1,.2,.3,.3,.4,.4,.5})[i]end end
      f.inserter_stack_size_bonus=f.technologies["inserter-capacity-bonus-8"].level==9 and 2 or 0
      f.stack_inserter_capacity_bonus=f.inserter_stack_size_bonus*2
    end
    force_list[name]=f;return f
  end
  local player=make_force("player")
  local direct="recipe-prod-research_character_mining_speed-1"
  player.technologies[direct].level=2;player.manual_mining_speed_modifier=.05
  player.research_queue={player.technologies[direct],player.technologies["braking-force-1"]}
  player.current_research=player.research_queue[1];player.research_progress=.42
  local original={origin="published",phase="published-ready",source_direct_finished=1,before_mining=0,
    source_lab=source_lab,source_lab_initial={[packs[1]]=32,[packs[2]]=32},saved=true}
  local bucket={mir5_historical_transition=original}
  local game={tick=100,forces=force_list,surfaces={{}}}
  function game.create_force(n)return make_force(n)end
  game.surfaces[1].create_entity=function(spec)
    assert(spec.name=="lab");local inv=inventory(0)
    local lab={valid=true,energy=0,get_inventory=function()return inv end}
    if current.target=="f210"then
      lab.disabled_by_script=false
      setmetatable(lab,{
        __index=function(value,key)if key=="active"then return not value.disabled_by_script end end,
        __newindex=function(value,key,item)
          if key=="active"then error("LuaEntity::active is read only.")end
          rawset(value,key,item)
        end})
      assert(not pcall(function()lab.active=false end),"F210 active must reject writes")
    else lab.active=true end
    labs[#labs+1]=lab;return lab
  end
  function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
  local function load_stage(stage_path, readonly)
    current=assert(loadfile(stage_path))()
    local callbacks={}
    local env={game=game,settings={startup={}},defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}},
      script={active_mods={base=current.base,["more-infinite-research"]=current.mir,["mir-fixture-mir5-historical-transition"]=current.fixture}},
      require=function(n)assert(n=="stage");return current end,
      log=function(s)markers[#markers+1]=s end}
    env._G=env
    if current.target=="f210"then env.storage=bucket else env.global=bucket end
    setmetatable(env,{__index=_G})
    for _,k in ipairs({"on_init","on_load","on_configuration_changed"})do env.script[k]=function(fn)callbacks[k]=fn end end
    function env.script.on_event(event,fn)callbacks[event]=fn end
    assert(loadfile(control_path,"t",env))()
    if readonly then
      local saved_game=env.game;env.game=setmetatable({},{__index=function()error("game accessed during on_load")end,__newindex=function()error("game written during on_load")end})
      callbacks.on_load();env.game=saved_game
    end
    return callbacks,env
  end
  if opponent=="source-mining"then player.manual_mining_speed_modifier=0 end
  if opponent=="source-queue"then player.research_progress=.41 end
  if opponent=="source-lab"then source_lab.active=true end
  if opponent=="source-science"then source_input.values[packs[1]]=32 end
  if opponent=="source-extra-laser"then player.technologies["laser-turret-speed-8"]={}end
  if opponent=="source-inserter-effect"then player.technologies["inserter-capacity-bonus-8"].prototype.effects[2].modifier=3 end
  local callbacks=load_stage(source_plan,true)
  if opponent=="fresh-world"then callbacks.on_init()end
  callbacks.on_configuration_changed();callbacks[1]();callbacks[1]()
  assert(saves==1 and #markers==1 and #labs==0,"source enhancement must save once without a new lab")
  local source_snapshot=clone(original.forward)
  callbacks=load_stage(source_plan,true);callbacks[1]();callbacks[1]()
  assert(saves==1 and #markers==2,"source cold reload must be read-only and report once")
  local function move_engine(stage_path)
    local destination=assert(loadfile(stage_path))()
    local old_prefix=current.laser_prefix
    for _,f in pairs(force_list)do
      for i=1,7 do
        local value=f.technologies[old_prefix..i];f.technologies[old_prefix..i]=nil
        value.name=destination.laser_prefix..i;f.technologies[value.name]=value
        value.prototype.effects[1].ammo_category=destination.ammo
      end
      if destination.target=="f210"then
        f.bulk_inserter_capacity_bonus=f.stack_inserter_capacity_bonus
        for _,t in pairs(f.technologies)do
          for _,e in pairs((t.prototype or{}).effects or{})do
            if e.type=="stack-inserter-capacity-bonus"then e.type="bulk-inserter-capacity-bonus"end
          end
        end
      end
    end
    return load_stage(stage_path,true)
  end
  if bridge_plan~=""then
    callbacks=move_engine(bridge_plan);callbacks.on_configuration_changed();callbacks[1]();callbacks[1]()
    assert(#labs==0 and #markers==3 and saves==2,"published bridge must not create research or a false cold marker")
  end
  callbacks=move_engine(target_plan)
  if opponent=="destination-level"then player.technologies[direct].level=1 end
  if opponent=="destination-cap"then player.technologies[direct].prototype.max_level=12 end
  if opponent=="destination-effect"then player.technologies[current.laser_prefix..7].prototype.effects[1].modifier=.4 end
  if opponent=="destination-laser"then player.bonus=0 end
  if opponent=="destination-inserter"then player.inserter_stack_size_bonus=1 end
  if opponent=="destination-foreign"then force_list["mir-published-f100-foreign"].technologies[direct].enabled=true end
  if opponent=="destination-paused"then force_list["mir-published-f100-suspended"].technologies[direct].saved_progress=.26 end
  if opponent=="destination-queue"then player.research_progress=.41 end
  callbacks.on_configuration_changed();assert(#labs==1 and original.forward.phase=="successor-lab")
  callbacks[1]();assert(labs[1].energy>0)
  player.technologies[direct].level=3;player.manual_mining_speed_modifier=.1
  local inv=labs[1].get_inventory()
  -- Native tools retain their stack count during partial durability use.
  for _,stack in ipairs(inv)do stack.durability=1-35/60 end
  if opponent=="successor-science"then inv[1].durability=1 end
  callbacks[2]({research=player.technologies[direct]})
  table.remove(player.research_queue,1);player.current_research=player.research_queue[1];player.research_progress=0
  callbacks[1]();callbacks[1]()
  local expected_saves=bridge_plan==""and 2 or 3
  assert(saves==expected_saves and original.forward.successor_labs==1)
  if current.target=="f210"then assert(labs[1].disabled_by_script==true,"F210 lab must be disabled")end
  if opponent=="completed-effect"then player.bonus=0 end
  if opponent=="cold-science"then inv[1].durability=1 end
  if opponent=="cold-lab-enabled"then
    if current.target=="f210"then labs[1].disabled_by_script=false else labs[1].active=true end
  end
  for i=1,2 do
    callbacks=load_stage(target_plan,true)
    callbacks.on_configuration_changed() -- A completed reload still checks all state.
    callbacks[1]();callbacks[1]()
  end
  assert(saves==expected_saves and #labs==1 and original.source_direct_finished==1)
  return #markers,saves,#labs,original.forward.seeded_finite_lasers,source_snapshot.player[direct].level
end
''')
        direct = json.loads((ROOT / "tests/fixtures/historical-direct-native-oracle.json").read_bytes())
        continuation = json.loads((ROOT / "tests/fixtures/historical-continuation-native-oracle.json").read_bytes())
        definitions = {}
        for oracle in (direct, continuation):
            capture = next(row for row in oracle["captures"] if row["target"] == "f100")
            for row in capture["technologies"]:
                effects = list(row["definition"]["effects"].values())
                level = int(row["id"].rsplit("-", 1)[1])
                definitions[row["id"]] = {"level": level, "max_level": row["definition"]["max_level"], "effects": effects}
        for i, modifier in enumerate((.1, .2, .3, .3, .4, .4, .5), 1):
            definitions[f"laser-turret-speed-{i}"] = {"level": i, "max_level": i, "effects": [
                {"type": "gun-speed", "ammo_category": "laser-turret", "modifier": modifier}]}
        self.definitions = self.to_lua(definitions)

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k: self.to_lua(v) for k, v in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(v) for v in value])
        return value

    def flow(self, target="f110", opponent="", bridge=False):
        return self.lua.globals().forward_flow(str(FIXTURE / "shared/control.lua"),
            str(FIXTURE / "source/stage.lua"), str(FIXTURE / target / "stage.lua"), self.definitions,
            opponent, str(FIXTURE / "bridge/stage.lua") if bridge else "")

    def test_both_exact_destinations_preserve_source_and_two_completed_reload_checks(self):
        for target in ("f110", "f210"):
            with self.subTest(target=target):
                self.setUp()
                self.assertEqual(self.flow(target), (5, 2, 1, 7, 2))

    def test_optional_published_engine_bridge_preserves_state_without_new_research(self):
        self.assertEqual(self.flow("f210", bridge=True), (6, 3, 1, 7, 2))

    def test_source_faults_refuse_before_an_enhanced_save_or_new_lab(self):
        for opponent in ("fresh-world", "source-mining", "source-queue", "source-lab", "source-science",
                         "source-extra-laser", "source-inserter-effect"):
            with self.subTest(opponent=opponent):
                self.setUp()
                with self.assertRaises(Exception):
                    self.flow(opponent=opponent)

    def test_destination_faults_and_completed_configuration_drift_remain_failures(self):
        for target in ("f110", "f210"):
            for opponent in ("destination-level", "destination-cap", "destination-effect", "destination-laser",
                             "destination-inserter", "destination-foreign", "destination-paused", "destination-queue", "completed-effect", "successor-science", "cold-science", "cold-lab-enabled"):
                with self.subTest(target=target, opponent=opponent):
                    self.setUp()
                    with self.assertRaises(Exception):
                        self.flow(target, opponent)

    def test_stages_preserve_mod_identity_and_never_change_startup_settings(self):
        expected = {"source": ("1.0", "0.2.0", "4.7.10003"), "bridge": ("1.1", "0.3.0", "4.7.11003"),
                    "f110": ("1.1", "0.4.0", "5.0.11000"), "f210": ("2.1", "0.5.0", "5.0.21000")}
        for directory, (line, version, mir) in expected.items():
            path = FIXTURE / directory
            info = json.loads((path / "info.json").read_bytes())
            self.assertEqual(info["name"], "mir-fixture-mir5-historical-transition")
            self.assertEqual((info["factorio_version"], info["version"]), (line, version))
            self.assertIn("more-infinite-research = " + mir, info["dependencies"])
            self.assertNotIn("data", (path / "settings-updates.lua").read_text())

    def test_data_preflight_refuses_changed_meaning_before_acceleration(self):
        self.lua.execute(r'''
          function preflight(path,stage_path,row,opponent)
            local plan=assert(loadfile(stage_path))()
            local env={mods={base=plan.base,["more-infinite-research"]=plan.mir},
              data={raw={technology={["recipe-prod-research_character_mining_speed-1"]=row}}},
              require=function(n)assert(n=="stage");return plan end}
            env._G=env;setmetatable(env,{__index=_G})
            if opponent=="engine"then env.mods.base="2.0.1"end
            if opponent=="mir"then env.mods["more-infinite-research"]="4.7.11002"end
            local ok,message=pcall(assert(loadfile(path,"t",env)))
            return ok,tostring(message)
          end
        ''')
        for directory in ("source", "bridge", "f110", "f210"):
            row = {"level": 1, "max_level": "infinite", "upgrade": True,
                   "effects": [{"type": "character-mining-speed", "modifier": .05}],
                   "unit": {"count_formula": "1*(8000*2^(L-1))" if directory == "f110" else "8000*2^(L-1)",
                            "time": 60, "ingredients": [["military-science-pack", 1], ["utility-science-pack", 1]]}}
            for opponent in ("", "engine", "mir", "effect", "cost", "formula", "cap", "science"):
                with self.subTest(stage=directory, opponent=opponent):
                    changed = deepcopy(row)
                    if opponent == "effect":
                        changed["effects"][0]["modifier"] = .1
                    elif opponent == "cost":
                        changed["unit"]["time"] = 120
                    elif opponent == "formula":
                        changed["unit"]["count_formula"] = (
                            "8000*2^(L-1)" if directory == "f110" else "1*(8000*2^(L-1))"
                        )
                    elif opponent == "cap":
                        changed["max_level"] = 12
                    elif opponent == "science":
                        changed["unit"]["ingredients"][1][0] = "automation-science-pack"
                    native = self.to_lua(changed)
                    ok, _ = self.lua.globals().preflight(str(FIXTURE / "shared/data-final-fixes.lua"),
                        str(FIXTURE / directory / "stage.lua"), native, opponent)
                    self.assertEqual(ok, not opponent)
                    if opponent:
                        self.assertEqual(native["unit"]["count_formula"], changed["unit"]["count_formula"])
                        self.assertIsNone(native["unit"]["count"])
                    else:
                        self.assertIsNone(native["unit"]["count_formula"])
                        self.assertEqual((native["unit"]["count"], native["unit"]["time"]), (1, 1))

        reference = json.loads((FIXTURE / "f210-mining-preflight-reference-r01.json").read_text(encoding="utf-8"))
        raw = json.dumps(reference["published_row"], sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), reference["canonical_row_sha256"])
        self.assertEqual(reference["published_row"], reference["candidate_row"])
        for opponent in ("", "wrong-wrapped-formula"):
            row = deepcopy(reference["published_row"])
            if opponent:
                row["unit"]["count_formula"] = "1*(8000*2^(L-1))"
            native = self.to_lua(row)
            ok, _ = self.lua.globals().preflight(str(FIXTURE / "shared/data-final-fixes.lua"),
                str(FIXTURE / "f210/stage.lua"), native, "")
            self.assertEqual(ok, not opponent)
            if opponent:
                self.assertEqual(native["unit"]["count_formula"], row["unit"]["count_formula"])
                self.assertIsNone(native["unit"]["count"])
            else:
                self.assertIsNone(native["unit"]["count_formula"])
                self.assertEqual((native["unit"]["count"], native["unit"]["time"]), (1, 1))

    def test_runner_preflight_binds_four_exact_stages_and_rejects_opposing_inputs(self):
        with tempfile.TemporaryDirectory(prefix="mir-published-f100-") as temporary:
            repo = Path(temporary)
            canonical = repo / "tests/fixtures/published-f100-forward"
            shutil.copytree(FIXTURE, canonical)
            for stage in ("source", "bridge", "f110", "f210"):
                source = repo / "build" / stage
                source.mkdir(parents=True)
                for name in ("info.json", "stage.lua", "control.lua", "data-final-fixes.lua", "settings-updates.lua"):
                    shutil.copyfile(canonical / stage / name, source / name)
                for name, alias in (("control.lua", "fixture_control.lua"), ("data-final-fixes.lua", "fixture_data_final.lua")):
                    shutil.copyfile(canonical / "shared" / name, source / alias)
            engine_data = repo / "engine-data/base"
            engine_data.mkdir(parents=True)
            (repo / "engine.exe").write_bytes(b"host-only engine identity surrogate;never executed")
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              $tokens=$null;$errors=$null
              $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_FORWARD_RUNNER,[ref]$tokens,[ref]$errors)
              if($errors.Count){throw 'runner parse failed'}
              foreach($name in @('Assert-Fixture','Test-F110PublishedCrossSourceRelativePath','Read-PublishedF100DirectRefusal','Get-PublishedF100ForwardFixture')){
                $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
                Invoke-Expression $node.Extent.Text
              }
              $repo=$env:MIR_FORWARD_REPO
              $engine=Join-Path $repo 'engine.exe'
              function Get-FixtureSha([string]$Path){if($Path -ceq $engine){return $script:engineSha};(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
              function New-HostRefusalBinding([string]$Opponent){
                # All bodies are synthetic temporary host controls, never native evidence.
                $folder=Join-Path $repo 'build/host-refusal';[void][IO.Directory]::CreateDirectory($folder)
                $profilePath=Join-Path $folder 'direct-profile.json';$stdoutPath=Join-Path $folder 'process-1.stdout.txt';$ledgerPath=Join-Path $folder 'process-1.resources.jsonl';$resultPath=Join-Path $folder 'result.json'
                $direct=@{schema=1;kind='published-f100-forward';stage='f210';target='f210';factorio_line='2.1';settings_mode='Defaults';predecessor_origin='published-f100-4.7.10003';protected_source_sha256=('A'*64);engine=@{version='2.1.23';sha256='8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38'};mods=@(@{name='base';version='2.1.23';enabled=$true},@{name='more-infinite-research';version='5.0.21000';enabled=$true},@{name='mir-fixture-mir5-historical-transition';version='0.5.0';enabled=$true});archive_sha256=@{'more-infinite-research_5.0.21000.zip'=('D'*64);'mir-fixture-mir5-historical-transition_0.5.0.zip'=('E'*64)}}
                $stdout="  0.000 2026-10-30 00:00:00; Factorio 2.1.23 (build host-double, win64, full)`n  0.500 Error Util.cpp:81: Map version 1.0.0-0 cannot be loaded because it is lower than the minimum input version (1.1.0-0).`n"
                $failure='[mir441-process-exit] 1'
                $ledger=@(@{process=@{id=4242;phase='running'}},@{phase='interrupted';timed_out=$false;error=$failure})
                $result=@{kind='MIR5NativeFixtureV1';status='failed';case='published-f100-forward';source_dirty=$false;source_head=('e'*40);input_save=@{sha256=('A'*64)};input_save_byte_identical=$true;engine=@{base_version='2.1.23';sha256=$direct.engine.sha256};mir_archive=@{sha256=('D'*64)};fixtures=@(@{sha256=('E'*64)});published_f100_forward=@{stage='f210';target='f210';role='successor';predecessor_origin='published-f100-4.7.10003';protected_input_sha256=('A'*64)};failure=$failure;process_runs=@(@{status='interrupted';stdout=$stdoutPath;ledger=$ledgerPath;error=$failure})}
                $result.harness_sha256='C'*64
                if($Opponent -ceq 'bridge-harness'){$result.harness_sha256='F'*64}
                if($Opponent -ceq 'bridge-source-revision'){$result.source_head='f'*40}
                if($Opponent -ceq 'bridge-source'){$direct.protected_source_sha256='F'*64;$result.input_save.sha256='F'*64}
                if($Opponent -ceq 'bridge-engine'){$result.engine.sha256='F'*64}
                if($Opponent -ceq 'bridge-mir'){$result.mir_archive.sha256='F'*64}
                if($Opponent -ceq 'bridge-fixture'){$result.fixtures[0].sha256='F'*64}
                if($Opponent -ceq 'bridge-route'){$result.published_f100_forward.target='f110'}
                if($Opponent -ceq 'bridge-no-native'){$result.process_runs=@()}
                if($Opponent -ceq 'bridge-no-pid'){$ledger[0].process.id=0}
                if($Opponent -ceq 'bridge-timeout'){$ledger[1].timed_out=$true}
                if($Opponent -ceq 'bridge-resource'){$failure='[mir441-resource-process-budget]';$result.failure=$failure;$result.process_runs[0].error=$failure;$ledger[1].error=$failure}
                if($Opponent -ceq 'bridge-non-format'){$stdout="  0.000 2026-10-30 00:00:00; Factorio 2.1.23 (build host-double, win64, full)`n  0.500 Error Util.cpp:81: Missing recipe.`n"}
                if($Opponent -ceq 'bridge-invented-phrase'){$stdout=$stdout.Replace('because it is lower than the minimum input version (1.1.0-0).','with this version of the game. The minimum supported map version is 1.1.0-0.')}
                if($Opponent -ceq 'bridge-format-suffix'){$stdout=$stdout.Replace('(1.1.0-0).','(1.1.0-0). invented bridge authorization')}
                if($Opponent -ceq 'bridge-format-trailing-space'){$stdout=$stdout.Replace('(1.1.0-0).','(1.1.0-0). ')}
                if($Opponent -ceq 'bridge-format-case'){$stdout=$stdout.Replace('Map version','map version')}
                if($Opponent -ceq 'bridge-format-crlf'){$stdout=$stdout.Replace("`n","`r`n")}
                if($Opponent -ceq 'bridge-bad-minimum'){$stdout=$stdout.Replace('(1.1.0-0).','(unknown).')}
                if($Opponent -ceq 'bridge-header'){$stdout=$stdout.Replace('Factorio 2.1.23','Factorio 1.1.110')}
                if($Opponent -ceq 'bridge-success'){$result.status='passed'}
                if($Opponent -ceq 'bridge-changed-input'){$result.input_save_byte_identical=$false}
                if($Opponent -ceq 'bridge-profile-archive'){$direct.archive_sha256['more-infinite-research_5.0.21000.zip']='F'*64}
                $profileJson=$direct|ConvertTo-Json -Depth 15
                if($Opponent -ceq 'bridge-duplicate'){$profileJson=$profileJson.Replace('"schema": 1','"schema": 1,"SCHEMA": 1')}
                [IO.File]::WriteAllText($profilePath,$profileJson)
                $result.profile=@{path=$profilePath;sha256=Get-FixtureSha $profilePath}
                if($Opponent -ceq 'bridge-profile'){$result.profile.sha256='F'*64}
                [IO.File]::WriteAllText($stdoutPath,$stdout)
                [IO.File]::WriteAllText($ledgerPath,(($ledger|ForEach-Object {$_|ConvertTo-Json -Depth 10 -Compress})-join "`n")+"`n")
                [IO.File]::WriteAllText($resultPath,($result|ConvertTo-Json -Depth 15))
                $binding=@{endpoint=@{target='f210';mir_sha256=('D'*64);fixture_sha256=('E'*64);source_revision=('e'*40);harness_sha256=('C'*64)}}
                foreach($row in @(@('result',$resultPath),@('profile',$profilePath),@('stdout',$stdoutPath),@('ledger',$ledgerPath))){$binding[$row[0]]=@{path=$row[1];sha256=Get-FixtureSha $row[1]}}
                if($Opponent -ceq 'bridge-invented'){$binding.result.sha256='B'*64}
                if($Opponent -ceq 'bridge-missing'){$binding.result.path=Join-Path $folder 'missing.json'}
                return $binding
              }
              $cases=@(
                @('source','f100','1.0','1.0.0','4.7.10003','0.2.0','99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70','C04F3543EBF99D2B76B2C9193EA0886381B7CDDF2F2C1610310E7961B24BE0E1'),
                @('bridge','f110','1.1','1.1.110','4.7.11003','0.3.0','B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1','66C127D8BFC1919FA88F19D2D9B3047316A1B90401CAA05A6D05979B7A099D1E'),
                @('f110','f110','1.1','1.1.110','5.0.11000','0.4.0','B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1',('C'*64)),
                @('f210','f210','2.1','2.1.23','5.0.21000','0.5.0','8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38',('D'*64))
              )
              $accepted=0;$refused=0
              $routeBase=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$historicalProcess' -and $n.Right.Extent.Text.Contains('$historical -or')},$true)
              $routeOverride=$ast.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$publishedF100Forward' -and $n.Clauses[0].Item2.Extent.Text.Contains('$historicalProcess=')},$true)
              $versionRoute=$ast.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$publishedF100Forward' -and $n.Clauses[0].Item2.Extent.Text.Contains('published F100 forward modes are exclusive')},$true)
              if(-not $routeBase -or -not $routeOverride -or -not $versionRoute){throw 'missing exact process routing'}
              $historical=$false;$historicalTransition=$false;$f110PublishedCrossSource=$false;$f110SameEditionSuccessor=$false;$laserTransition=$false;$CreateOnly=$false;$MIRAbsent=$false;$activeSeed=$false
              $ActiveSeedKind='';$activeModsObserverName='';$ConsumerMarkers=@();$HistoricalFixtureMetadataPath='';$HistoricalTransitionFixtureMetadataPath=''
              foreach($case in $cases){
                $stage,$target,$line,$base,$mir,$version,$script:engineSha,$mirSha=$case
                $publishedF100Forward=$true;$PublishedF100ForwardStage=$stage;$historicalProcessVersion=''
                Invoke-Expression $routeBase.Extent.Text;Invoke-Expression $routeOverride.Extent.Text;Invoke-Expression $versionRoute.Extent.Text
                $expectedLine=if($stage -ceq 'f210'){''}else{$line}
                if($historicalProcess -ne ($stage -cne 'f210') -or $historicalProcessVersion -cne $expectedLine){throw ('incorrect process route '+$stage)}
                $inputSha=if($stage -ceq 'source'){'219EF20F63B4A85FA2386BD50A81228B28F006D9731F24E069A657BB13F45811'}else{'A'*64}
                $engineData=Join-Path $repo 'engine-data'
                @{version=$base}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $engineData 'base/info.json')
                $profile=@{schema=1;kind='published-f100-forward';stage=$stage;target=$target;factorio_line=$line;settings_mode='Defaults';predecessor_origin='published-f100-4.7.10003';protected_source_sha256=$inputSha;engine=@{version=$base;sha256=$script:engineSha};mods=@(@{name='base';version=$base;enabled=$true},@{name='more-infinite-research';version=$mir;enabled=$true},@{name='mir-fixture-mir5-historical-transition';version=$version;enabled=$true});archive_sha256=@{('more-infinite-research_'+$mir+'.zip')=$mirSha;('mir-fixture-mir5-historical-transition_'+$version+'.zip')=('E'*64)}}
                $source=Join-Path $repo ('build/'+$stage)
                foreach($opponent in @('','input','origin','engine','archive','extra-mod','member','bridge-refusal','bridge-invented','bridge-missing','bridge-source','bridge-engine','bridge-mir','bridge-fixture','bridge-profile','bridge-route','bridge-no-native','bridge-no-pid','bridge-timeout','bridge-resource','bridge-non-format','bridge-invented-phrase','bridge-format-suffix','bridge-format-trailing-space','bridge-format-case','bridge-format-crlf','bridge-bad-minimum','bridge-header','bridge-duplicate','bridge-success','bridge-changed-input','bridge-profile-archive','bridge-harness','bridge-source-revision')){
                  if($opponent.StartsWith('bridge-') -and $stage -cne 'bridge'){continue}
                  $changed=($profile|ConvertTo-Json -Depth 10)|ConvertFrom-Json -AsHashtable
                  if($stage -ceq 'bridge'){$changed.engine_bridge_refusal=New-HostRefusalBinding $opponent}
                  $actualInput=$inputSha
                  if($opponent -ceq 'input'){$actualInput='F'*64}
                  if($opponent -ceq 'origin'){$changed.predecessor_origin='mir5-f100'}
                  if($opponent -ceq 'engine'){$changed.engine.sha256='F'*64}
                  if($opponent -ceq 'archive'){$changed.archive_sha256['more-infinite-research_'+$mir+'.zip']='F'*64}
                  if($opponent -ceq 'extra-mod'){$changed.mods+=@{name='undeclared';version='1.0.0';enabled=$true}}
                  if($opponent -ceq 'bridge-refusal'){$changed.engine_bridge_refusal=$null}
                  $member=Join-Path $source 'fixture_control.lua';$original=[IO.File]::ReadAllBytes($member)
                  if($opponent -ceq 'member'){[IO.File]::AppendAllText($member,"`n-- opposing payload")}
                  $ok=$true
                  $message=''
                  try{$null=Get-PublishedF100ForwardFixture -Repo $repo -Profile $changed -Sources @($source) -EngineData $engineData -Engine $engine -MIRSha $mirSha -Case 'published-f100-forward' -Stage $stage -InputSave 'protected.zip' -InputSha $actualInput}catch{$ok=$false;$message=$_.Exception.Message}
                  finally{[IO.File]::WriteAllBytes($member,$original)}
                  if($ok -ne ($opponent -cin @('','bridge-format-crlf'))){throw ('unexpected preflight result '+$stage+'/'+$opponent+': '+$message)}
                  if($ok){$accepted++}else{$refused++}
                }
              }
              @{accepted=$accepted;refused=$refused;native_processes=0}|ConvertTo-Json -Compress
            '''
            env = {**os.environ, "MIR_FORWARD_REPO": str(repo), "MIR_FORWARD_RUNNER": str(ROOT / "tools/Invoke-NativeFixture.ps1")}
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout), {"accepted": 5, "refused": 50, "native_processes": 0})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, rest = parser.parse_known_args()
    sys.path.insert(0, args.lua_runtime_dir)
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
