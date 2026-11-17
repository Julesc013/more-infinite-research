"""Execute the real MIR-absence admission guard without launching Factorio."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeFixtureModeControls(unittest.TestCase):
    def test_active_repair_admission_binds_current_fixture_and_retains_old_tuples(self):
        script = r'''
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
foreach($name in @('Assert-Fixture','Assert-ActiveFixtureSelection')){
 $nodes=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
 if($nodes.Count-ne1){throw 'active admission function absent'}
 Invoke-Expression $nodes[0].Extent.Text
}
$profile=Get-Content -LiteralPath $env:MIR_TEST_PROFILE -Raw | ConvertFrom-Json -AsHashtable
$mir=@($profile.mods | Where-Object {$_.name-ceq'more-infinite-research'})
Assert-ActiveFixtureSelection 'repair-stress' $profile.mods $mir
foreach($case in @(
 @{mir='4.7.21002'; fixture='0.1.0'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21000'; fixture='0.2.0'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21001'; fixture='0.2.0'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21005'; fixture='0.2.0'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21010'; fixture='0.2.1'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21010'; fixture='0.2.0'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21005'; fixture='0.2.1'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21009'; fixture='0.2.1'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21011'; fixture='0.2.1'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.20010'; fixture='0.2.1'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21010'; fixture='0.2.1'; selector='0.2.0'; accepted=$false},
 @{mir='5.0.21010'; fixture='0.2.1'; selector=''; accepted=$false}
)){
 $rows=@(@{name='mir-fixture-mir5-repair-stress';version=$case.fixture;enabled=$true})
 if($case.selector){$rows+=@{name='mir-fixture-mir5-repair-stress-active';version=$case.selector;enabled=$true}}
 $ok=$true;try{Assert-ActiveFixtureSelection 'repair-stress' $rows @(@{version=$case.mir})}catch{$ok=$false}
 if($ok-ne$case.accepted){throw ('active tuple admission differs: '+($case|ConvertTo-Json -Compress))}
}
$calls=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]-and$n.Extent.Text-ceq'Assert-ActiveFixtureSelection $ActiveSeedKind $rows $mirRows'},$true))
if($calls.Count-ne1){throw 'active runner does not call admission'}
'''
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                env=dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'),
                                         MIR_TEST_PROFILE=str(ROOT / 'tests/profiles/repair-stress-active-current-f210-2123.json')),
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_active_agriculture_admission_binds_current_core_and_retains_old(self):
        script = r'''
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
foreach($name in @('Assert-Fixture','Assert-ActiveFixtureSelection')){
 $nodes=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
 if($nodes.Count-ne1){throw 'active admission function absent'}
 Invoke-Expression $nodes[0].Extent.Text
}
foreach($tier in @(1,32,128)){
 $profile=Get-Content -LiteralPath (Join-Path $env:MIR_TEST_PROFILES "agriculture-active-matched-current-defaults-$tier-f210-2123.json") -Raw | ConvertFrom-Json -AsHashtable
 $mir=@($profile.mods | Where-Object {$_.name-ceq'more-infinite-research'})
 Assert-ActiveFixtureSelection 'agriculture-scale' $profile.mods $mir
}
foreach($case in @(
 @{mir='5.0.21005'; core='0.1.0'; selector='0.1.0'; accepted=$true},
 @{mir='4.7.21002'; core='0.1.0'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21010'; core='0.1.1'; selector='0.1.0'; accepted=$true},
 @{mir='5.0.21010'; core='0.1.0'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21005'; core='0.1.1'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21009'; core='0.1.1'; selector='0.1.0'; accepted=$false},
 @{mir='5.0.21010'; core='0.1.1'; selector='0.2.0'; accepted=$false},
 @{mir='5.0.21010'; core='0.1.1'; selector=''; accepted=$false}
)){
 $rows=@(@{name='mir-fixture-mir5-agriculture-scale';version=$case.core;enabled=$true})
 if($case.selector){$rows+=@{name='mir-fixture-mir5-agriculture-scale-active';version=$case.selector;enabled=$true}}
 $ok=$true;try{Assert-ActiveFixtureSelection 'agriculture-scale' $rows @(@{version=$case.mir})}catch{$ok=$false}
 if($ok-ne$case.accepted){throw ('agriculture tuple admission differs: '+($case|ConvertTo-Json -Compress))}
}
'''
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                env=dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'),
                                         MIR_TEST_PROFILES=str(ROOT / 'tests/profiles')),
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_retained_protected_profile_metadata_keeps_default_activation_arguments(self):
        script = r'''
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
foreach($name in @('Assert-Fixture','Get-FixtureSettingsArguments')){
 $nodes=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
 if($nodes.Count-ne1){throw 'settings admission function absent'}
 Invoke-Expression $nodes[0].Extent.Text
}
$retained=@{
 'migration-origins-1.0.0-successor-f200-2077.json'='ProtectedSourceSave'
 'migration-origins-1.0.0-successor-f210-2123.json'='ProtectedOriginalF200SourceSave'
 'migration-origins-1.1.0-successor-f210-2123.json'='ProtectedOriginalF200SourceSavePendingNative'
 'discovery-recovery-successor-control-a575-f210-2123.json'='ProtectedOriginalSourceSavePendingNative'
}
foreach($file in $retained.Keys){
 $profile=Get-Content -LiteralPath (Join-Path $env:MIR_TEST_PROFILES $file) -Raw|ConvertFrom-Json -AsHashtable
 if($profile.settings_mode-cne$retained[$file]){throw 'retained profile shape changed'}
 foreach($restricted in @($false,$true)){
  foreach($inputSave in @('','protected.zip')){
   $actual=Get-FixtureSettingsArguments $profile '' '' $restricted $inputSave 'retained-case'
   if($actual.Count-ne1-or$actual.SettingsMode-cne'Defaults'){throw ('retained activation differs: '+$file)}
  }
 }
}
$legacyWithoutMetadata=Get-FixtureSettingsArguments @{target='f200'} '' '' $true '' 'retained-case'
if($legacyWithoutMetadata.Count-ne1-or$legacyWithoutMetadata.SettingsMode-cne'Defaults'){throw 'absent metadata activation changed'}
'PASS actual retained protected-source profile activation arguments'
'''
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                env=dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'),
                                         MIR_TEST_PROFILES=str(ROOT / 'tests/profiles')),
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_explicit_file_settings_require_exact_declared_bounded_inputs(self):
        script = r'''
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-FixtureSettingsArguments')){
 $nodes=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
 if($nodes.Count-ne1){throw 'settings admission function absent'}
 Invoke-Expression $nodes[0].Extent.Text
}
$file=Join-Path $env:MIR_TEST_OUTPUT 'settings.dat'
[IO.File]::WriteAllBytes($file,[Convert]::FromHexString('020001001700000000050000000000'))
$hash=Get-FixtureSha $file
$defaults=Get-FixtureSettingsArguments @{settings_mode='Defaults'} '' '' $false '' 'old-case'
if($defaults.Count-ne1-or$defaults.SettingsMode-cne'Defaults'){throw 'default path changed'}
foreach($mode in @('valid','no-explicit-inputs','missing-path','missing-hash','defaults-profile','protected-profile','declaration','content-hash','header','oversize','restricted','no-save','wrong-case','wrong-target')){
 $profile=@{settings_mode='File';settings_sha256=$hash;target='f210'}
 $settingsArguments=@{ProfileDefinition=$profile;Path=$file;Sha256=$hash;RestrictedMode=$false;InputSave='protected.zip';Case='native-research-speed-finite'}
 if($mode-ceq'no-explicit-inputs'){$settingsArguments.Path='';$settingsArguments.Sha256=''}
 if($mode-ceq'missing-path'){$settingsArguments.Path=''}
 if($mode-ceq'missing-hash'){$settingsArguments.Sha256=''}
 if($mode-ceq'defaults-profile'){$profile.settings_mode='Defaults'}
 if($mode-ceq'protected-profile'){$profile.settings_mode='ProtectedSourceSave'}
 if($mode-ceq'declaration'){$profile.settings_sha256='A'*64}
 if($mode-ceq'content-hash'){$settingsArguments.Sha256='A'*64;$profile.settings_sha256='A'*64}
 if($mode-ceq'header'){
  $bad=Join-Path $env:MIR_TEST_OUTPUT 'bad.dat';[IO.File]::WriteAllBytes($bad,[byte[]]::new(9))
  $settingsArguments.Path=$bad;$settingsArguments.Sha256=Get-FixtureSha $bad;$profile.settings_sha256=$settingsArguments.Sha256
 }
 if($mode-ceq'oversize'){
  $large=Join-Path $env:MIR_TEST_OUTPUT 'large.dat';$stream=[IO.File]::Create($large);try{$stream.SetLength(4MB+1)}finally{$stream.Dispose()}
  $settingsArguments.Path=$large;$settingsArguments.Sha256=Get-FixtureSha $large;$profile.settings_sha256=$settingsArguments.Sha256
 }
 if($mode-ceq'restricted'){$settingsArguments.RestrictedMode=$true}
 if($mode-ceq'no-save'){$settingsArguments.InputSave=''}
 if($mode-ceq'wrong-case'){$settingsArguments.Case='historical-native'}
 if($mode-ceq'wrong-target'){$profile.target='f200'}
 $accepted=$true;try{$selected=Get-FixtureSettingsArguments @settingsArguments}catch{$accepted=$false}
 if($accepted-ne($mode-ceq'valid')){throw ('settings guard differs: '+$mode)}
 if($accepted-and($selected.SettingsMode-cne'File'-or$selected.SettingsSha256-cne$hash-or$selected.SettingsPath-cne$file)){throw 'selected settings changed'}
}
$source=[IO.File]::ReadAllText($env:MIR_TEST_RUNNER)
foreach($binding in @('$selectedSettings=Get-FixtureSettingsArguments', '$activationArguments.SettingsPath=$selectedSettings.SettingsPath', '$activationArguments.SettingsSha256=$selectedSettings.SettingsSha256')){
 if(-not$source.Contains($binding)){throw 'actual activation bypasses admitted settings'}
}
'PASS explicit settings guard and activation binding'
'''
        import tempfile
        with tempfile.TemporaryDirectory(prefix="finite-settings-guard-") as directory:
            result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                    env=dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'),
                                             MIR_TEST_OUTPUT=directory), capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_only_named_matched_workloads_add_fixed_map_seed_to_actual_stage_arguments(self):
        script = r'''
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
$function=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq'Get-FixtureCreateArguments'},$true))
if($function.Count-ne1){throw 'create argument boundary missing'}
Invoke-Expression $function[0].Extent.Text
$seed='C:\owned checkout\seed.zip'
foreach($case in @('library-paired-browser','library-multiplayer','repair-stress-active','agriculture-scale-active','agriculture-scale','historical-native')){
 foreach($only in @($false,$true)){
  $actual=@(Get-FixtureCreateArguments $seed $case $only)
  $expected=@('--create',$seed)
  if(($case-ceq'library-paired-browser'-and$only)-or$case-cin@('repair-stress-active','agriculture-scale-active')){$expected+=@('--map-gen-seed','424242')}
  if(($actual|ConvertTo-Json -Compress)-cne($expected|ConvertTo-Json -Compress)){throw 'creation inputs differ'}
 }
}
$assignment=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.AssignmentStatementAst]-and$n.Left.Extent.Text-ceq'$createArguments'},$true))
if($assignment.Count-ne1-or-not$assignment[0].Right.Extent.Text.Contains('Get-FixtureCreateArguments -Seed $seed -Case $CaseName -OnlyCreate ([bool]$CreateOnly)')){throw 'actual creation bypasses seed selection'}
$call=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]-and$n.Extent.Text-ceq"Invoke-FixtureStage 'create' $"+'createArguments'},$true))
if($call.Count-ne1){throw 'actual create stage bypasses selected arguments'}
'PASS fixed paired creation arguments'
'''
        result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                env=dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1')),
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_protected_input_save_is_copied_and_only_the_owned_copy_reaches_start_server(self):
        script = r'''
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
foreach($name in @('Assert-Fixture','Get-FixtureSha','New-FixtureWorkingInputSave')){
 $node=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
 if($node.Count-ne1){throw "working input helper missing: $name"};Invoke-Expression $node[0].Extent.Text
}
$seedAssignment=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$seed' -and $n.Right.Extent.Text.Contains('$workingInputSave.path')
},$true))
$modernProduction=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$record.production' -and $n.Right.Extent.Text.Contains("'--server-settings',`$server,'--bind','127.0.0.1','--start-server',`$seed")
},$true))
if($seedAssignment.Count-ne1-or$modernProduction.Count-ne1){throw 'actual owned seed to modern start-server route missing or ambiguous'}
function Get-MIRNativeProbeRemainingOutputBytes {param($Context) return [int64]$Context.remaining}
$source=Join-Path $env:MIR_TEST_TEMP 'protected-source.zip';$owned=Join-Path $env:MIR_TEST_TEMP 'owned-context'
[IO.Directory]::CreateDirectory($owned)|Out-Null
$original=[Text.Encoding]::UTF8.GetBytes('protected-native-save-bytes')
[IO.File]::WriteAllBytes($source,$original)
$expected=Get-FixtureSha $source
$resources=[pscustomobject]@{root=$owned;remaining=[int64]1MB}
$working=New-FixtureWorkingInputSave -InputSave $source -ExpectedSha256 $expected -Resources $resources
if($working.mode-cne'copy'-or$working.path-ceq$source-or$working.protected_path-cne$source-or$working.sha256-cne$expected-or$working.bytes-ne$original.Length){throw 'working-copy initial receipt differs'}
$inputSave=$source;$workingInputSave=$working;$seed=$null
. ([scriptblock]::Create($seedAssignment[0].Extent.Text))
$record=[ordered]@{};$server=Join-Path $owned 'server-settings.json';$completion=$null;$script:engineStart=''
function Invoke-FixtureStage {param([string]$Name,[string[]]$StageArguments,[scriptblock]$Completion)
 $index=[array]::IndexOf([string[]]$StageArguments,'--start-server')
 if($Name-cne'production'-or$index-lt0-or$index-eq($StageArguments.Count-1)){throw 'engine double did not receive an actual production start-server argument'}
 $script:engineStart=[string]$StageArguments[$index+1]
 [IO.File]::WriteAllBytes($script:engineStart,[Text.Encoding]::UTF8.GetBytes('graceful-engine-save-back'))
 return [pscustomobject]@{stage=$Name;arguments=@($StageArguments)}
}
. ([scriptblock]::Create($modernProduction[0].Extent.Text))
if($script:engineStart-cne$working.path-or(Get-FixtureSha $source)-cne$expected-or(Get-FixtureSha $working.path)-ceq$expected-or$record.production.arguments[$record.production.arguments.Count-1]-cne$working.path){throw 'owned-copy production route or protected-source preservation differs'}
# This is the exact former direct seed assignment, exercised with the same
# production statement and graceful engine double.  It proves why retaining
# only a post-run protected-source hash is insufficient without the copy.
[IO.File]::WriteAllBytes($source,$original)
$inputSave=$source;$seed=$inputSave;$record=[ordered]@{};$script:engineStart=''
. ([scriptblock]::Create($modernProduction[0].Extent.Text))
if($script:engineStart-cne$source-or(Get-FixtureSha $source)-ceq$expected){throw 'direct protected-source counterfactual did not expose the graceful save-back mutation'}
[IO.File]::WriteAllBytes($source,$original)
Remove-Item -LiteralPath $working.path -Force
foreach($mode in @('wrong-pin','budget','preexisting')){
 $resources.remaining=[int64]1MB
 if($mode-ceq'wrong-pin'){$hash='0'*64}else{$hash=$expected}
 if($mode-ceq'budget'){$resources.remaining=[int64]$original.Length}
 if($mode-ceq'preexisting'){[IO.File]::WriteAllBytes($working.path,[Text.Encoding]::UTF8.GetBytes('do-not-overwrite'))}
 $refused=$false;try{New-FixtureWorkingInputSave -InputSave $source -ExpectedSha256 $hash -Resources $resources|Out-Null}catch{$refused=$true}
 if(-not$refused){throw "prelaunch input-copy refusal missing: $mode"}
 if($mode-ceq'preexisting'){
  if([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($working.path))-cne'do-not-overwrite'){throw 'prelaunch copy overwrote an existing owned output'}
  Remove-Item -LiteralPath $working.path -Force
 }elseif(Test-Path -LiteralPath $working.path){throw "prelaunch rejection left a partial working copy: $mode"}
 if((Get-FixtureSha $source)-cne$expected){throw "prelaunch rejection changed protected source: $mode"}
}
'PASS protected source stays immutable while the actual start-server argument is writable owned output'
'''
        import tempfile
        with tempfile.TemporaryDirectory(prefix="native-fixture-working-copy-") as directory:
            result = subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-Command', script],
                                    env=dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'),
                                             MIR_TEST_TEMP=directory), capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_absent_full_and_create_modes_refuse_any_mir_selection_or_hash(self):
        script = r'''
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
$nodes=@($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.IfStatementAst] -and
  $node.Clauses[0].Item1.Extent.Text -ceq '$MIRAbsent' -and
  $node.Clauses[0].Item2.Extent.Text.Contains('Assert-Fixture')
},$true))
if($nodes.Count -ne 1){throw 'exact MIR absence admission not found'}
$body=[scriptblock]::Create($nodes[0].Clauses[0].Item2.Extent.Text.TrimStart('{').TrimEnd('}'))
function Assert-Fixture([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$rows=@()
foreach($CreateOnly in @($false,$true)){
 foreach($count in @(0,1,2)){
  foreach($ExpectedMIRArchiveSha256 in @('',('A'*64))){
   $mirRows=@(for($index=0;$index-lt$count;$index++){@{name='more-infinite-research';version='5.0.21000'}})
   $accepted=$true; $reason=$null
   try {& $body} catch {$accepted=$false; $reason=$_.Exception.Message}
   $rows+=@{create_only=$CreateOnly; count=$count; hash_supplied=($ExpectedMIRArchiveSha256-ne''); accepted=$accepted; reason=$reason}
  }
 }
}
ConvertTo-Json -InputObject $rows -Depth 4 -Compress
'''
        env = dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'))
        result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], env=env,
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        rows = json.loads(result.stdout)
        self.assertEqual(12, len(rows))
        for row in rows:
            with self.subTest(row=row):
                admitted = row['count'] == 0 and not row['hash_supplied']
                self.assertEqual(admitted, row['accepted'])
                if not admitted:
                    self.assertIn('MIR absence requires a profile without MIR or its hash', row['reason'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
