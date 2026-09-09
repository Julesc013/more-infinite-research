# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$CombinedModsDir='C:\Projects\Factorio\testmods\2.1',
  [string]$OutputRoot='build/tests/mir42-bob-angel-tin-route-safety'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$modsRoot=(Resolve-Path -LiteralPath $CombinedModsDir).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
if(-not $output.StartsWith((Join-Path $repo 'build')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Route-safety outputs must be under build.'}

$expectedEngineSha256='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'
$expectedArchives=[ordered]@{
  'boblibrary_3.0.0.zip'='49EAE2D4D8E58EBD28BAFDB7E71D5307CBCE2077E0642440ED7EC527D466FFC4'
  'bobores_3.0.0.zip'='7F8E33E35F59BB3F2CD72E3AB2FED30D1C2AE9C117E3731324AC307D9965082B'
  'bobplates_3.0.1.zip'='503D7BF6E88DA1F99463AC00CEC959C2003B2701D80DC4A564CF2EC3920AC8AF'
  'angelsrefining_2.1.2.zip'='AF5E79E35E591F68D52F13EDA082950E10AC98A4B7722B3F568D0211E3FEB813'
  'angelsrefininggraphics_2.1.0.zip'='79F373BC628F619EDE3B1875827172390D2C3F5EAB56310F6F1572C4553CB6EF'
  'angelspetrochem_2.1.2.zip'='9B4CC14156CF16C9F41784108CCA5E767180A7330B1AF23A387231653CE10A49'
  'angelspetrochemgraphics_2.1.0.zip'='DECDC2FCD5BBBDEF70784943C142C30FAA7294B98E814296C5D44D09A9DE4790'
  'angelssmelting_2.1.1.zip'='1DFCDD77D075FD545CFEE74BD8A6443E7E90B133D3832FDD47649C84892243A9'
  'angelssmeltinggraphics_2.1.0.zip'='EBEF8D1F6F13F84B242DF295CE9FAB9618ED90B4C52852A0B4345908A88D5D35'
}
$expectedNonClaims=@('combined-productivity-admission','MIR-emission','F200','gameplay-progression-or-reachability','upgrade-or-persisted-save-recovery','balance-or-process-safety','PIPE-01','infinite-continuation','full-BA-07-or-PROG-01','release-readiness')
$expectedProducers=@('angels-plate-tin','angels-plate-tin-2','angels-plate-tin-recycling','angels-wire-tin-recycling','bob-tin-plate','bob-tin-plate-recycling')

function Assert-Exact([string]$Name,$Actual,$Expected){
  if($null -eq $Actual -and $null -eq $Expected){return}
  if($null -eq $Actual -or $null -eq $Expected -or $Actual -cne $Expected){throw "Route-safety $Name differs."}
}
function Assert-Array([string]$Name,$Actual,[string[]]$Expected){$values=@($Actual|ForEach-Object{[string]$_});if(($values -join "`n") -cne ($Expected -join "`n")){throw "Route-safety $Name differs."}}
function Assert-Props([string]$Name,$Object,[string[]]$Expected){if($null -eq $Object){throw "Route-safety $Name is absent."};$actual=@($Object.PSObject.Properties.Name|Sort-Object);$wanted=@($Expected|Sort-Object);if(($actual -join "`n") -cne ($wanted -join "`n")){throw "Route-safety $Name properties differ."}}
function New-RouteEntry([string]$Type,[string]$Name,[int]$Amount){[pscustomobject][ordered]@{type=$Type;name=$Name;amount=$Amount}}
function New-Witness([string]$From,[string]$Recipe,[string]$To){[pscustomobject][ordered]@{from=$From;recipe=$Recipe;to=$To}}
function New-RoleEvidence($Kind,$Hidden,$Enabled,$Category,$AutoRecycle,$AllowDecomposition,$AllowProductivity,$RecoveryStructure){[pscustomobject][ordered]@{evidence_kind=$Kind;hidden=$Hidden;enabled=$Enabled;category=$Category;auto_recycle=$AutoRecycle;allow_decomposition=$AllowDecomposition;allow_productivity=$AllowProductivity;recovery_structure=$RecoveryStructure}}
function Assert-EntryArray([string]$Name,$Actual,$Expected){
  $actualRows=@($Actual);$expectedRows=@($Expected)
  if($actualRows.Count -ne $expectedRows.Count){throw "Route-safety $Name count differs."}
  for($index=0;$index -lt $expectedRows.Count;$index++){
    Assert-Props "$Name[$index]" $actualRows[$index] @('type','name','amount')
    Assert-Exact "$Name[$index].type" $actualRows[$index].type $expectedRows[$index].type
    Assert-Exact "$Name[$index].name" $actualRows[$index].name $expectedRows[$index].name
    Assert-Exact "$Name[$index].amount" $actualRows[$index].amount $expectedRows[$index].amount
  }
}
function Assert-RoleEvidence([string]$Name,$Actual,$Expected){
  $fields=@('evidence_kind','hidden','enabled','category','auto_recycle','allow_decomposition','allow_productivity','recovery_structure')
  Assert-Props $Name $Actual $fields
  foreach($field in $fields){Assert-Exact "$Name.$field" $Actual.$field $Expected.$field}
}
function Assert-Witness([string]$Name,$Actual,$Expected){
  $actualRows=@($Actual);$expectedRows=@($Expected)
  if($actualRows.Count -ne $expectedRows.Count){throw "Route-safety $Name witness count differs."}
  for($index=0;$index -lt $expectedRows.Count;$index++){
    Assert-Props "$Name[$index]" $actualRows[$index] @('from','recipe','to')
    Assert-Exact "$Name[$index].from" $actualRows[$index].from $expectedRows[$index].from
    Assert-Exact "$Name[$index].recipe" $actualRows[$index].recipe $expectedRows[$index].recipe
    Assert-Exact "$Name[$index].to" $actualRows[$index].to $expectedRows[$index].to
    if($index -gt 0){Assert-Exact "$Name[$index].continuity" $actualRows[$index].from $actualRows[$index-1].to}
  }
}
function ConvertTo-RouteText($Value){if($null -eq $Value){return 'nil'};if($Value -is [bool]){if($Value){return 'true'};return 'false'};return [string]$Value}
function Format-Entries($Entries){return (@($Entries|ForEach-Object{"$($_.type):$($_.name):$($_.amount)"}|Sort-Object) -join ',')}
function Format-RoleEvidence($Evidence){return "hidden=$(ConvertTo-RouteText $Evidence.hidden) enabled=$(ConvertTo-RouteText $Evidence.enabled) category=$(ConvertTo-RouteText $Evidence.category) auto-recycle=$(ConvertTo-RouteText $Evidence.auto_recycle) allow-decomposition=$(ConvertTo-RouteText $Evidence.allow_decomposition) allow-productivity=$(ConvertTo-RouteText $Evidence.allow_productivity)"}
function Format-Witness($Witness){return (@($Witness|ForEach-Object{"$($_.from)--$($_.recipe)-->$($_.to)"}) -join '|')}

$expectedRows=[ordered]@{
  'angels-plate-tin'=[pscustomobject][ordered]@{role='non-recycling';classification='unsafe-under-conservative-potential-return-certificate';reason='potential-return-path:angels-liquid-molten-tin';positive_ingredients=@(New-RouteEntry fluid angels-liquid-molten-tin 40);declared_products=@(New-RouteEntry item bob-tin-plate 4);role_evidence=(New-RoleEvidence productive-final-plate-transformation $null $false $null $false $null $true not-applicable);witness_target=(New-RouteEntry fluid angels-liquid-molten-tin 40);witness=@((New-Witness bob-tin-plate bob-bronze-alloy bob-bronze-alloy),(New-Witness bob-bronze-alloy angels-advanced-chemical-plant angels-advanced-chemical-plant),(New-Witness angels-advanced-chemical-plant angels-advanced-chemical-plant-recycling electronic-circuit),(New-Witness electronic-circuit agricultural-tower agricultural-tower),(New-Witness agricultural-tower agricultural-tower-recycling spoilage),(New-Witness spoilage burnt-spoilage angels-solid-carbon),(New-Witness angels-solid-carbon angels-ingot-tin-3 angels-ingot-tin),(New-Witness angels-ingot-tin angels-liquid-molten-tin angels-liquid-molten-tin))}
  'angels-plate-tin-2'=[pscustomobject][ordered]@{role='non-recycling';classification='unsafe-under-conservative-potential-return-certificate';reason='potential-return-path:angels-roll-tin';positive_ingredients=@(New-RouteEntry item angels-roll-tin 1);declared_products=@(New-RouteEntry item bob-tin-plate 4);role_evidence=(New-RoleEvidence productive-final-plate-transformation $null $false $null $false $false $true not-applicable);witness_target=(New-RouteEntry item angels-roll-tin 1);witness=@((New-Witness bob-tin-plate bob-bronze-alloy bob-bronze-alloy),(New-Witness bob-bronze-alloy angels-advanced-chemical-plant angels-advanced-chemical-plant),(New-Witness angels-advanced-chemical-plant angels-advanced-chemical-plant-recycling electronic-circuit),(New-Witness electronic-circuit poison-capsule poison-capsule),(New-Witness poison-capsule poison-capsule-recycling coal),(New-Witness coal angels-coal-cracking-2 angels-liquid-mineral-oil),(New-Witness angels-liquid-mineral-oil angels-liquid-coolant angels-liquid-coolant),(New-Witness angels-liquid-coolant angels-roll-tin-2 angels-roll-tin))}
  'angels-plate-tin-recycling'=[pscustomobject][ordered]@{role='recycling';classification='excluded-recovery';positive_ingredients=@(New-RouteEntry item bob-tin-plate 1);declared_products=@(New-RouteEntry item bob-tin-plate 1);role_evidence=(New-RoleEvidence hidden-disabled-recovery-structure $true $false $null $null $null $null same-final-plate-input-and-output)}
  'angels-wire-tin-recycling'=[pscustomobject][ordered]@{role='recycling';classification='excluded-recovery';positive_ingredients=@(New-RouteEntry item angels-wire-tin 1);declared_products=@(New-RouteEntry item bob-tin-plate 0),(New-RouteEntry item copper-cable 0);role_evidence=(New-RoleEvidence hidden-disabled-recovery-structure $true $false $null $null $false $null all-declared-products-zero-amount)}
  'bob-tin-plate'=[pscustomobject][ordered]@{role='non-recycling';classification='unsafe-under-conservative-potential-return-certificate';reason='potential-return-path:bob-tin-ore';positive_ingredients=@(New-RouteEntry item bob-tin-ore 1);declared_products=@(New-RouteEntry item bob-tin-plate 1);role_evidence=(New-RoleEvidence productive-final-plate-transformation $true $false $null $false $false $true not-applicable);witness_target=(New-RouteEntry item bob-tin-ore 1);witness=@((New-Witness bob-tin-plate bob-bronze-alloy bob-bronze-alloy),(New-Witness bob-bronze-alloy angels-advanced-chemical-plant angels-advanced-chemical-plant),(New-Witness angels-advanced-chemical-plant angels-advanced-chemical-plant-recycling angels-clay-brick),(New-Witness angels-clay-brick angels-sintering-oven angels-sintering-oven),(New-Witness angels-sintering-oven angels-sintering-oven-recycling iron-plate),(New-Witness iron-plate sulfuric-acid sulfuric-acid),(New-Witness sulfuric-acid angels-ore3-crystal angels-ore3-crystal),(New-Witness angels-ore3-crystal angels-ore3-crystal-processing bob-tin-ore))}
  'bob-tin-plate-recycling'=[pscustomobject][ordered]@{role='recycling';classification='excluded-recovery';positive_ingredients=@(New-RouteEntry item bob-tin-plate 1);declared_products=@(New-RouteEntry item bob-tin-plate 1);role_evidence=(New-RoleEvidence hidden-disabled-recovery-structure $true $false $null $null $null $null same-final-plate-input-and-output)}
}

function Assert-ProducerRow([string]$Name,$Actual,$Expected){
  $fields=@('recipe','role','classification','positive_ingredients','declared_products','role_evidence')
  if($Expected.role -eq 'non-recycling'){$fields+=@('reason','witness_target','witness')}
  Assert-Props "producer.$Name" $Actual $fields
  Assert-Exact "producer.$Name.recipe" $Actual.recipe $Name
  Assert-Exact "producer.$Name.role" $Actual.role $Expected.role
  Assert-Exact "producer.$Name.classification" $Actual.classification $Expected.classification
  Assert-EntryArray "producer.$Name.positive_ingredients" $Actual.positive_ingredients $Expected.positive_ingredients
  Assert-EntryArray "producer.$Name.declared_products" $Actual.declared_products $Expected.declared_products
  Assert-RoleEvidence "producer.$Name.role_evidence" $Actual.role_evidence $Expected.role_evidence
  if($Expected.role -eq 'non-recycling'){
    Assert-Exact "producer.$Name.reason" $Actual.reason $Expected.reason
    Assert-Props "producer.$Name.witness_target" $Actual.witness_target @('type','name','amount')
    Assert-Exact "producer.$Name.witness_target.type" $Actual.witness_target.type $Expected.witness_target.type
    Assert-Exact "producer.$Name.witness_target.name" $Actual.witness_target.name $Expected.witness_target.name
    Assert-Exact "producer.$Name.witness_target.amount" $Actual.witness_target.amount $Expected.witness_target.amount
    Assert-Exact "producer.$Name.witness_target.ingredient.type" $Actual.witness_target.type @($Actual.positive_ingredients)[0].type
    Assert-Exact "producer.$Name.witness_target.ingredient.name" $Actual.witness_target.name @($Actual.positive_ingredients)[0].name
    Assert-Exact "producer.$Name.witness_target.ingredient.amount" $Actual.witness_target.amount @($Actual.positive_ingredients)[0].amount
    Assert-Exact "producer.$Name.witness_target.reason" $Actual.witness_target.name ($Actual.reason -replace '^potential-return-path:','')
    Assert-Witness "producer.$Name.witness" $Actual.witness $Expected.witness
  }
}

$engineSha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
if($engineSha256 -cne $expectedEngineSha256){throw "Route-safety requires exact F210 engine SHA-256 $expectedEngineSha256."}
$version=(& $engine --version|Out-String)
if($LASTEXITCODE -ne 0 -or $version -notmatch 'Version: 2[.]1[.]17'){throw 'Route-safety requires Steam F210 2.1.17.'}
$engineVersion=([regex]::Match($version,'Version:\s+2[.]1[.]17[^\r\n]*').Value).Trim()
if([string]::IsNullOrWhiteSpace($engineVersion)){throw 'Route-safety could not bind exact engine version.'}
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim();$sourceTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
if($sourceCommit -notmatch '^[0-9a-f]{40}$' -or $sourceTree -notmatch '^[0-9a-f]{40}$'){throw 'Route-safety requires 40-hex source commit/tree bindings.'}
$sourceChanges=@(& git -C $repo status --porcelain --untracked-files=all -- src/mod)
if($sourceChanges.Count -ne 0){throw "Route-safety refuses a changed package-source root: $($sourceChanges -join '; ')"}

$fixture=Join-Path $repo 'fixtures/assert-bob-angel-tin-route-safety'
$dossier=Join-Path $fixture 'route-safety-dossier.json'
$combinedDossier=Join-Path $repo 'fixtures/assert-bob-angel-tin-final-state-audit/route-dossier.json'
$packageSource=Join-Path $repo 'src/mod/package-source.json'
try{$record=Get-Content -Raw -LiteralPath $dossier|ConvertFrom-Json -ErrorAction Stop;$combined=Get-Content -Raw -LiteralPath $combinedDossier|ConvertFrom-Json -ErrorAction Stop}catch{throw "Route-safety dossier JSON is invalid: $($_.Exception.Message)"}

Assert-Props root $record @('schema','kind','scope','target','official_mod_closure','archive_closure','combined_audit_binding','bounds','producer_classifications','controls','direct_vs_mir','observed_disposition','evidence_role','explicit_non_claims')
Assert-Exact schema $record.schema 1;Assert-Exact kind $record.kind 'MIR4BobAngelTinRouteSafetyV1';Assert-Exact scope $record.scope 'F210 exact combined Bob plus Angel Tin route-safety diagnostic classification; package-excluded evidence';Assert-Exact observed_disposition $record.observed_disposition 'all-real-non-recycling-final-plate-transformations-unsafe-under-conservative-potential-return-certificate-no-combined-Tin-route-admitted';Assert-Exact evidence_role $record.evidence_role 'bounded diagnostic input to A06 BA-07 A17 and PROG-01; not completion authority';Assert-Array explicit_non_claims $record.explicit_non_claims $expectedNonClaims
Assert-Props target $record.target @('factorio_line','factorio_version','engine_sha256');Assert-Exact target.line $record.target.factorio_line '2.1';Assert-Exact target.version $record.target.factorio_version '2.1.17';Assert-Exact target.engine $record.target.engine_sha256 $expectedEngineSha256;Assert-Array official_mod_closure $record.official_mod_closure @('base','elevated-rails','quality','recycler','space-age')
if(@($record.archive_closure).Count -ne $expectedArchives.Count){throw 'Route-safety archive closure count differs.'};$seen=@{};foreach($archive in @($record.archive_closure)){Assert-Props archive $archive @('name','version','sha256');$file="$($archive.name)_$($archive.version).zip";if(-not $expectedArchives.Contains($file) -or $seen.Contains($file)){throw "Route-safety archive identity differs $file"};$seen[$file]=$true;Assert-Exact "archive.$file" $archive.sha256 $expectedArchives[$file]};if($seen.Count -ne $expectedArchives.Count){throw 'Route-safety archive closure identities differ.'}
Assert-Props combined_audit_binding $record.combined_audit_binding @('path','schema','all_declared_final_plate_producer_recipe_ids','direct_plate_to_ore_recipe_edges','mir_potential_return_omission');Assert-Exact combined.path $record.combined_audit_binding.path 'fixtures/assert-bob-angel-tin-final-state-audit/route-dossier.json';Assert-Exact combined.schema $record.combined_audit_binding.schema 1;Assert-Exact combined.actual_schema $combined.schema 1;Assert-Array combined.producers $record.combined_audit_binding.all_declared_final_plate_producer_recipe_ids $expectedProducers;Assert-Array combined.actual_producers $combined.all_declared_final_plate_producer_recipe_ids $expectedProducers;Assert-Array combined.direct $record.combined_audit_binding.direct_plate_to_ore_recipe_edges @();Assert-Array combined.actual_direct $combined.side_paths.direct_plate_to_ore_recipe_edges @();Assert-Exact combined.mir_recipe $combined.side_paths.mir_potential_return_omission.recipe 'bob-tin-plate';Assert-Exact combined.mir_reason $combined.side_paths.mir_potential_return_omission.reason 'potential-return-path:bob-tin-ore'
Assert-Props bounds $record.bounds @('max_graph_nodes','max_graph_edges','max_search_entries','max_depth','observed_graph_nodes');Assert-Exact bounds.nodes $record.bounds.max_graph_nodes 30000;Assert-Exact bounds.edges $record.bounds.max_graph_edges 100000;Assert-Exact bounds.search $record.bounds.max_search_entries 30000;Assert-Exact bounds.depth $record.bounds.max_depth 64;Assert-Exact bounds.observed_nodes $record.bounds.observed_graph_nodes 1074
if(@($record.producer_classifications).Count -ne $expectedRows.Count){throw 'Route-safety producer classification count differs.'};$classified=@{};foreach($row in @($record.producer_classifications)){if($classified.ContainsKey([string]$row.recipe)){throw "Route-safety duplicate producer $($row.recipe)"};$classified[[string]$row.recipe]=$row};foreach($recipe in $expectedProducers){if(-not $classified.ContainsKey($recipe)){throw "Route-safety producer absent $recipe"};Assert-ProducerRow $recipe $classified[$recipe] $expectedRows[$recipe]}
$driftWitness=@($expectedRows['bob-tin-plate'].witness|ForEach-Object{New-Witness $_.from $_.recipe $_.to});$driftWitness[3]=New-Witness $driftWitness[3].from 'synthetic-intermediate-drift' $driftWitness[3].to;$witnessRejected=$false;try{Assert-Witness 'synthetic-witness-drift' $driftWitness $expectedRows['bob-tin-plate'].witness}catch{$witnessRejected=$true};if(-not $witnessRejected){throw 'Route-safety intermediate witness drift negative was not rejected.'}
$driftIngredients=@(New-RouteEntry item bob-tin-ore 2);$ingredientRejected=$false;try{Assert-EntryArray 'synthetic-ingredient-drift' $driftIngredients $expectedRows['bob-tin-plate'].positive_ingredients}catch{$ingredientRejected=$true};if(-not $ingredientRejected){throw 'Route-safety producer ingredient drift negative was not rejected.'}
Assert-Props controls $record.controls @('synthetic_known_safe','difficult_known_unsafe','fail_closed');Assert-Props controls.safe $record.controls.synthetic_known_safe @('classification','fixture_only','combined_tin_route_admitted');Assert-Exact controls.safe.classification $record.controls.synthetic_known_safe.classification 'safe';Assert-Exact controls.safe.fixture $record.controls.synthetic_known_safe.fixture_only $true;Assert-Exact controls.safe.admission $record.controls.synthetic_known_safe.combined_tin_route_admitted $false;Assert-Props controls.unsafe $record.controls.difficult_known_unsafe @('recipe','classification','witness_length');Assert-Exact controls.unsafe.recipe $record.controls.difficult_known_unsafe.recipe 'bob-tin-plate';Assert-Exact controls.unsafe.classification $record.controls.difficult_known_unsafe.classification 'unsafe-under-conservative-potential-return-certificate';Assert-Exact controls.unsafe.length $record.controls.difficult_known_unsafe.witness_length 8;Assert-Array controls.fail_closed $record.controls.fail_closed @('malformed-entry','search-budget','node-budget','edge-budget')
Assert-Props direct_vs_mir $record.direct_vs_mir @('direct_plate_to_ore_recipe_edges','mir_observable_agreement','angel_matcher_disposition');Assert-Array direct_vs_mir.direct $record.direct_vs_mir.direct_plate_to_ore_recipe_edges @();Assert-Props direct_vs_mir.mir $record.direct_vs_mir.mir_observable_agreement @('recipe','reason','scope');Assert-Exact direct_vs_mir.mir.recipe $record.direct_vs_mir.mir_observable_agreement.recipe 'bob-tin-plate';Assert-Exact direct_vs_mir.mir.reason $record.direct_vs_mir.mir_observable_agreement.reason 'potential-return-path:bob-tin-ore';Assert-Exact direct_vs_mir.mir.scope $record.direct_vs_mir.mir_observable_agreement.scope 'exact-log-observation-only';Assert-Exact direct_vs_mir.angel $record.direct_vs_mir.angel_matcher_disposition 'independent-checker-only-because-Factorio-cross-mod-private-require-isolation'

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
if([string]::IsNullOrWhiteSpace($CandidateZip)){$candidate=New-MIR4TargetPackage -RepoRoot $repo -Target f210 -CandidateId ('TIN-ROUTE-SAFETY-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()) -SourceVersion '4.2.0' -DistributionVersion '4.2.21000' -OutputRoot 'build/bob-angel-tin-route-safety/packages';$CandidateZip=[string]$candidate.archive_path}
$candidateZip=(Resolve-Path -LiteralPath $CandidateZip).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem;$zip=[IO.Compression.ZipFile]::OpenRead($candidateZip);try{$forbidden=@($zip.Entries|Where-Object {$_.FullName -match '(^|/)(fixtures|tests|docs|[.]mir|build|dist)(/|$)'});if($forbidden.Count -ne 0){throw "Candidate includes package-excluded path $($forbidden[0].FullName)"}}finally{$zip.Dispose()}
$run=Join-Path $output ([guid]::NewGuid().ToString('N'));$mods=Join-Path $run 'mods';New-Item -ItemType Directory -Force -Path $mods,(Join-Path $run 'userdata')|Out-Null
Copy-Item -LiteralPath $candidateZip -Destination $mods
$archiveHashes=[ordered]@{};foreach($entry in $expectedArchives.GetEnumerator()){$path=Join-Path $modsRoot $entry.Key;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Route-safety archive missing $path"};$hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;if($hash -cne $entry.Value){throw "Route-safety archive hash differs $($entry.Key)"};$archiveHashes[$entry.Key]=$hash;Copy-Item -LiteralPath $path -Destination $mods}
Publish-MIRModDirectoryArchive -Source $fixture -Name 'mir-fixture-assert-bob-angel-tin-route-safety' -Version '0.1.0' -ModsDir $mods|Out-Null
@{mods=@(@{name='base';enabled=$true},@{name='space-age';enabled=$true},@{name='elevated-rails';enabled=$true},@{name='quality';enabled=$true},@{name='recycler';enabled=$true},@{name='more-infinite-research';enabled=$true},@{name='boblibrary';enabled=$true},@{name='bobores';enabled=$true},@{name='bobplates';enabled=$true},@{name='angelsrefining';enabled=$true},@{name='angelsrefininggraphics';enabled=$true},@{name='angelspetrochem';enabled=$true},@{name='angelspetrochemgraphics';enabled=$true},@{name='angelssmelting';enabled=$true},@{name='angelssmeltinggraphics';enabled=$true},@{name='mir-fixture-assert-bob-angel-tin-route-safety';enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding utf8
$engineRoot=Split-Path (Split-Path (Split-Path $engine -Parent)-Parent)-Parent
[IO.File]::WriteAllText((Join-Path $run 'config.ini'),"[path]`nread-data=$($engineRoot.Replace('\','/'))/data`nwrite-data=$($run.Replace('\','/'))/userdata`n",[Text.UTF8Encoding]::new($false))
$start=[Diagnostics.ProcessStartInfo]::new($engine);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;foreach($argument in @('--config',(Join-Path $run 'config.ini'),'--mod-directory',$mods,'--create',(Join-Path $run 'route-safety.zip'))){$start.ArgumentList.Add($argument)};$process=[Diagnostics.Process]::Start($start);try{$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(120000)){$process.Kill($true);throw "Route-safety timed out $run"};$text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $run 'engine.log'),$text,[Text.UTF8Encoding]::new($false));if($process.ExitCode -ne 0){throw "Route-safety engine failed: $run`n$($text.Substring([Math]::Max(0,$text.Length-2500)))"}}finally{$process.Dispose()}
$log=Join-Path $run 'userdata/factorio-current.log';if(-not(Test-Path -LiteralPath $log -PathType Leaf)){throw 'Route-safety Factorio log is absent.'};$logText=Get-Content -Raw -LiteralPath $log
if($logText -notmatch [regex]::Escape('[mir-bob-angel-tin-route-safety] DATA PASS graph-nodes=1074 declared=6 recycling=3 non-recycling-unsafe=3 direct-plate-to-ore=0 synthetic-safe=pass synthetic-fail-closed=pass mir-bob-log-agreement=deferred')){throw 'Route-safety data assertion is absent.'}
foreach($recipe in $expectedProducers){$expected=$expectedRows[$recipe];$structure="[mir-bob-angel-tin-route-safety] STRUCTURE recipe=$recipe role=$($expected.role) evidence=$($expected.role_evidence.evidence_kind) inputs=$(Format-Entries $expected.positive_ingredients) outputs=$(Format-Entries $expected.declared_products) $(Format-RoleEvidence $expected.role_evidence) recovery=$($expected.role_evidence.recovery_structure)";if($logText -notmatch [regex]::Escape($structure)){throw "Route-safety exact structural log is absent $recipe"};$classification="[mir-bob-angel-tin-route-safety] CLASSIFIED recipe=$recipe role=$($expected.role) classification=$($expected.classification)";if($expected.role -eq 'non-recycling'){$classification+=" reason=$($expected.reason) witness=$(Format-Witness $expected.witness)"};if($logText -notmatch [regex]::Escape($classification)){throw "Route-safety exact classification log is absent $recipe"}}
if($logText -notmatch [regex]::Escape('[more-infinite-research] Material route omitted recipe=bob-tin-plate reason=potential-return-path:bob-tin-ore')){throw 'Route-safety MIR Bob matcher agreement log is absent.'};if($logText -notmatch [regex]::Escape('[mir-bob-angel-tin-route-safety] RUNTIME PROBE diagnostic-only')){throw 'Route-safety runtime assertion is absent.'}
$result=[ordered]@{schema=1;status='passed';scope='F210 exact combined Bob plus Angel Tin route-safety diagnostic classification';target='F210';engine_version=$engineVersion;engine_sha256=$engineSha256;source=[ordered]@{commit=$sourceCommit;tree=$sourceTree;package_source_sha256=(Get-FileHash -LiteralPath $packageSource -Algorithm SHA256).Hash;package_source_roots_clean=$true};candidate_sha256=(Get-FileHash -LiteralPath $candidateZip -Algorithm SHA256).Hash;candidate_package_excludes_fixture_test_docs_mir_build_dist=$true;archive_sha256=$archiveHashes;combined_audit_dossier_sha256=(Get-FileHash -LiteralPath $combinedDossier -Algorithm SHA256).Hash;route_safety_dossier_sha256=(Get-FileHash -LiteralPath $dossier -Algorithm SHA256).Hash;fixture_hashes=[ordered]@{info=(Get-FileHash (Join-Path $fixture 'info.json') -Algorithm SHA256).Hash;dossier=(Get-FileHash $dossier -Algorithm SHA256).Hash;data_final_fixes=(Get-FileHash (Join-Path $fixture 'data-final-fixes.lua') -Algorithm SHA256).Hash;control=(Get-FileHash (Join-Path $fixture 'control.lua') -Algorithm SHA256).Hash};harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;all_declared_final_plate_producer_recipe_count=6;recycling_excluded_count=3;non_recycling_unsafe_count=3;structural_role_validation='exact-positive-ingredients-declared-products-and-role-evidence';every_step_witness_binding='dossier-fixture-log-harness';synthetic_safe_control=$true;direct_plate_to_ore_recipe_edges=@();mir_observable_agreement=$record.direct_vs_mir.mir_observable_agreement;angel_matcher_disposition=$record.direct_vs_mir.angel_matcher_disposition;log_sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash;non_claims=$expectedNonClaims}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
$result|ConvertTo-Json -Depth 12
Write-Output "Evidence: $run"
