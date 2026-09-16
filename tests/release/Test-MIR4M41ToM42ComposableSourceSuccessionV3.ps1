# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
$writer=Join-Path $repo 'tools/commands/mir4/Update-MIR4M41ToM42ComposableSourceSuccessionV3Authority.ps1'
& $writer -RepoRoot $repo -Check | Out-Null
$result=Test-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $repo
if([string]$result.status-cne'passed-historical-mir41-to-current-mir42-progression-source-succession'-or[bool]$result.current_release_operations_authorized-or-not[bool]$result.factorio_one_exact_engine_proof_required){throw '[mir4-m41-m42-succession-v3-positive]'}
$record=Get-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $repo
$expectedBindings=[ordered]@{
  '.mir/assurance.json'=@('074DA277D4C9BCF3B1A6505047F724154807C21A44C08E43B4F89E0CF8A56F58','5116211C95BE060474B091C50971637C337EA4015B9312D99BE4C825CE56EAA2')
  '.mir/control/paths.yml'=@('EC4C705D22C218AF7E2B838035F1D974D3850BDD477DC44E947329B12F6CD85B','59138DF52AB407F67E5B4CA1D390BA46F1F5820F857052F6706B2408DC8C1BE7')
  '.mir/modules.yml'=@('506E67864097D9A9D228DEBBF157B1D113687B2A5EAC24A8433A7F02C7F6C9EA','9CB3EDA28BC47D994972D88AC5F82E2AFFFA3B7754746FC612638C6B605274E8')
  'assurance/catalog/tests.json'=@('0AAD6F171A47F7E5B69FDD325FAE4BAAE3A94C0C44616683416066D8A7C24699','C0F358186B2B770A376BD881F211EE072963A2F3360E7AD64D0C0F9C1125FF7D')
  'docs/architecture/module-boundaries.md'=@('99CBFC8FAEBDDA28AC51739BD5F69E5AB73B9ECEBEAE540354116B276560275E','8347D3E5191A1D72F222D316ABD6A08AC3408C9AF75CBA4A8B418C4F78AAD665')
  'tests/architecture/Test-MIRArchitecture.ps1'=@('60BA9050BBBAC31114C06B699708B42EBAE8680452D299D3953185FB2AB93FFB','3DD1DD2350ECB04CB92AC9B8CDBD76586E30C9012AA521A96B3A8A5647AB3C8B')
  'tests/mir4/Test-MIR4DocumentationCutoverM4105B.ps1'=@('4E538FF77E49BEA7AB3555ED7F4FC8113AFB5BD82374E5BF055F65ECB951AE47','A0F90FA14FF771510142730E7E9AFBAF33C7E54D128EB21DABCC56B2F8EEF8A0')
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'=@('57F0F8E10EDECFFE274B8E79CFED750527957133AD24AF29895B27F893273F74','8ECA00F8BD5B3D98806B3E260478C77D0D21CD90D2543DE633C88D8F1FEA6747')
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'=@('D51678A896BB76B8F26BDA7DDA0D31CEE44146C319D087F81510EFE7BDE98FC6','9EE3FB7554EB994E046B99FFD8AC4E13AB8889E52523C524A92962BB3BEBC388')
  'tests/tooling/Test-MIRAssurance.ps1'=@('01CBEFF991124FF1D2E41F02D63BF325F3F3C31F4EF5CC2660B9C22C28CE557B','4353D89895DF35CAC6CC1109A1FD4070777F26160CBDCD72E99AEEE9D7B7DBED')
  'validation/tests.yml'=@('CA25A4BCA78510C00C996B802CFE79CC2092248A591240BAD00797C6CAC1C421','B6D415F82816BC100D817A518A3FAC09A190DE1CBAA571F82A89753310F8D004')
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'=@('0E8F9490D8FDD8245597A2CB09E4ABC50BDC8371F605521C0ADA4CFBA852EEC8','5020935FC3AC85888232CC0756AE20718F9FB30B4611E009E5E3415897A962EC')
  'tools/lib/mir4/pre-freeze-release/ReleaseDoctor.ps1'=@('68B7621F6382186D5A40C1AAAB9775CF33AB380AC29B250A25468F6BECBF7089','F74A35E850047648E96D759A0E62F5E7B744FDB1248E05EB55302D808D82437D')
}
if(@($record.evolved_bindings).Count-ne$expectedBindings.Count){throw '[mir4-m41-m42-succession-v3-evolved-binding-count]'}
foreach($path in $expectedBindings.Keys){
  $binding=@($record.evolved_bindings | Where-Object { [string]$_.path -ceq $path })
  if($binding.Count-ne1-or[string]$binding[0].previous_sha256-cne$expectedBindings[$path][0]-or
     [string]$binding[0].current_sha256-cne$expectedBindings[$path][1]-or
     [string]$binding[0].hash_mode-cne'canonical-text-v1'-or
     [bool]$binding[0].package_visible-or[bool]$binding[0].release_authority){throw "[mir4-m41-m42-succession-v3-evolved-binding] $path"}
}
$inventory=Get-MIR4M41ToM42ComposableSourceSuccessionV2ToolingInventoryBinding -RepoRoot $repo
if([string]$record.current.tooling_inventory_predecessor_sha256-cne'CC28AA34B139C0B082BAF07E81829D797F4A2B303AA31A7C3A6FD3EC526F834A'-or
   (ConvertTo-MIR4BootstrapCanonicalJson -Value $record.current.tooling_inventory)-cne(ConvertTo-MIR4BootstrapCanonicalJson -Value $inventory)){throw '[mir4-m41-m42-succession-v3-tooling-inventory]'}
$tampered=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
$tampered.transition_gate.publication=$true;$tampered.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tampered
$rejected=$false;try{Test-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $repo -SuccessionRecord $tampered|Out-Null}catch{$rejected=$_.Exception.Message -match 'v3-stale'}
if(-not$rejected){throw '[mir4-m41-m42-succession-v3-negative-gate]'}
$tampered=$record|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
$tampered.evolved_bindings[0].current_sha256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';$tampered.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $tampered
$rejected=$false;try{Test-MIR4M41ToM42ComposableSourceSuccessionV3 -RepoRoot $repo -SuccessionRecord $tampered|Out-Null}catch{$rejected=$_.Exception.Message -match 'v3-(schema|stale)'}
if(-not$rejected){throw '[mir4-m41-m42-succession-v3-negative-evolved-binding]'}
[pscustomobject][ordered]@{status='passed';test_id='static.mir4-m41-to-m42-composable-source-succession-v3';exact_engine_proof_required=$true;release_authority=$false;record_sha256=[string]$record.record_sha256}|ConvertTo-Json -Compress
