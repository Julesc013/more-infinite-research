[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$lf=[string][char]10
$rows=@(
  [ordered]@{source='assert-upgrade-3-2-11-to-4-0-21000';name='assert-upgrade-4-0-21000-to-4-1-21000';from='4.0.21000';to='4.1.21000';old_save='mir-4021000-upgraded';save='mir-4121000-upgraded';factorio='2.1';base='2.1.14';archetypes=@('base-default','space-age-native-owner','automatic-family-creation','base-continuations','mod-set-configuration-change')}
  [ordered]@{source='assert-upgrade-2-5-11-to-4-0-20000';name='assert-upgrade-4-0-20000-to-4-1-20000';from='4.0.20000';to='4.1.20000';old_save='mir-4020000-upgraded';save='mir-4120000-upgraded';factorio='2.0';base='2.0.77';archetypes=@('base-default')}
  [ordered]@{source='assert-upgrade-1-9-9-to-4-0-11000';name='assert-upgrade-4-0-11000-to-4-1-11000';from='4.0.11000';to='4.1.11000';old_save='mir-4011000-upgraded';save='mir-4111000-upgraded';factorio='1.1';base='1.1';archetypes=@('base-default')}
  [ordered]@{source='assert-upgrade-1-8-9-to-4-0-10000';name='assert-upgrade-4-0-10000-to-4-1-10000';from='4.0.10000';to='4.1.10000';old_save='mir-4010000-upgraded';save='mir-4110000-upgraded';factorio='1.0';base='1.0';archetypes=@('base-default')}
)

function Get-MIR441DerivedFixtureFiles($Row){
  $sourceRoot=Join-Path $repo "fixtures/$($Row.source)"
  $files=[ordered]@{}
  foreach($item in Get-ChildItem -LiteralPath $sourceRoot -File|Sort-Object Name){
    $text=[IO.File]::ReadAllText($item.FullName).Replace([string][char]13,'')
    $text=$text.Replace("mir-fixture-$($Row.source)","mir-fixture-$($Row.name)")
    if($item.Name-ceq'control.lua'){
      $fromRegex=[regex]'(from_version[ ]*=[ ]*")[^"]+(")'
      $toRegex=[regex]'(to_version[ ]*=[ ]*")[^"]+(")'
      if(-not$fromRegex.IsMatch($text)-or-not$toRegex.IsMatch($text)){throw "[mir441-fixture-source-version] $($Row.source)"}
      $text=$fromRegex.Replace($text,{param($match)$match.Groups[1].Value+[string]$Row.from+$match.Groups[2].Value},1)
      $text=$toRegex.Replace($text,{param($match)$match.Groups[1].Value+[string]$Row.to+$match.Groups[2].Value},1)
      $text=$text.Replace([string]$Row.old_save,[string]$Row.save)
    }elseif($item.Name-ceq'info.json'){
      $info=$text|ConvertFrom-Json -Depth 20
      $info.name="mir-fixture-$($Row.name)"
      $info.title="MIR Fixture - Assert $($Row.from) to $($Row.to) Upgrade"
      $dependencies=[Collections.Generic.List[string]]::new()
      $dependencies.Add("base >= $($Row.base)")
      if($Row.factorio-ceq'2.1'){$dependencies.Add("(?) space-age >= $($Row.base)")}
      $dependencies.Add("more-infinite-research >= $($Row.from)")
      $info.dependencies=@($dependencies)
      $text=($info|ConvertTo-Json -Depth 20).Replace([string][char]13,'')+$lf
    }elseif($item.Name-ceq'settings-updates.lua'){
      $transitionRegex=[regex]'missing [0-9]+(?:[.][0-9]+)+ to [0-9]+(?:[.][0-9]+)+ upgrade setting'
      $text=$transitionRegex.Replace($text,"missing $($Row.from) to $($Row.to) upgrade setting")
    }
    $files[$item.Name]=$text
  }
  return $files
}

foreach($row in $rows){
  $targetRoot=Join-Path $repo "fixtures/$($row.name)"
  $files=Get-MIR441DerivedFixtureFiles -Row $row
  if($Check){
    if(-not(Test-Path -LiteralPath $targetRoot -PathType Container)){throw "[mir441-fixture-missing] $($row.name)"}
    $actual=@(Get-ChildItem -LiteralPath $targetRoot -File|Sort-Object Name|ForEach-Object{$_.Name})
    if(($actual-join'|')-cne(@($files.Keys)-join'|')){throw "[mir441-fixture-file-set] $($row.name)"}
    foreach($name in $files.Keys){
      if([IO.File]::ReadAllText((Join-Path $targetRoot $name)).Replace([string][char]13,'')-cne[string]$files[$name]){throw "[mir441-fixture-stale] $($row.name)/$name"}
    }
  }else{
    if(-not(Test-Path -LiteralPath $targetRoot)){New-Item -ItemType Directory -Path $targetRoot|Out-Null}
    foreach($name in $files.Keys){[IO.File]::WriteAllText((Join-Path $targetRoot $name),[string]$files[$name],[Text.UTF8Encoding]::new($false))}
  }
}

$catalogPath=Join-Path $repo '.mir/fixtures.yml'
$catalog=[IO.File]::ReadAllText($catalogPath).Replace([string][char]13,'')
$start='# MIR441-DIRECT-UPGRADE-FIXTURES-BEGIN'
$end='# MIR441-DIRECT-UPGRADE-FIXTURES-END'
$builder=[Text.StringBuilder]::new()
[void]$builder.AppendLine($start)
foreach($row in $rows){
  $key=([string]$row.name).Substring('assert-'.Length)
  [void]$builder.AppendLine("  ${key}:")
  [void]$builder.AppendLine('    requires_features: []')
  [void]$builder.AppendLine("    assertion_path: fixtures/$($row.name)")
  [void]$builder.AppendLine('    harness: tests/runtime/Test-MIRUpgradeMatrix.ps1')
  [void]$builder.AppendLine("    primary_source_version: $($row.from)")
  [void]$builder.AppendLine('    archetypes:')
  foreach($archetype in $row.archetypes){[void]$builder.AppendLine("      - $archetype")}
  [void]$builder.AppendLine('    validates:')
  foreach($claim in @('exact-4-0-source-archive','stable-technology-and-setting-identity-retention','current-research-and-fractional-progress-retention','fixture-state-retention','upgraded-save-two-reload-proof','exact-4-1-candidate-normal-mod-directory-load')){[void]$builder.AppendLine("      - $claim")}
  [void]$builder.AppendLine('')
}
[void]$builder.AppendLine($end)
$expectedBlock=$builder.ToString().Replace([string][char]13,'').TrimEnd()+$lf
if($catalog.Contains($start)){
  $first=$catalog.IndexOf($start,[StringComparison]::Ordinal)
  $last=$catalog.IndexOf($end,$first,[StringComparison]::Ordinal)
  if($last-lt0){throw '[mir441-fixture-catalog-marker]'}
  $lineEnd=$catalog.IndexOf($lf,$last,[StringComparison]::Ordinal)
  if($lineEnd-lt0){$lineEnd=$catalog.Length-1}
  $expected=$catalog.Substring(0,$first)+$expectedBlock+$catalog.Substring($lineEnd+1)
}else{$expected=$catalog.TrimEnd()+$lf+$lf+$expectedBlock}
if($Check){
  if($catalog-cne$expected){throw '[mir441-fixture-catalog-stale]'}
}else{[IO.File]::WriteAllText($catalogPath,$expected,[Text.UTF8Encoding]::new($false))}

[pscustomobject][ordered]@{status='MIR-4.1-DIRECT-UPGRADE-FIXTURES-PASSED';fixture_count=$rows.Count;check=[bool]$Check;publication_authorized=$false}
