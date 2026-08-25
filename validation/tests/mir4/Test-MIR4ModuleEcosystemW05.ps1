param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$CandidateZip='build/mir4/m4c02-target-products/packages/more-infinite-research_4.0.21000.zip'
)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $PSScriptRoot 'MIR4ReceiptTestSupport.ps1')
$hostedReceiptOnly=Test-MIR4HostedReceiptOnly
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authority=Get-MIR4ModuleEcosystemAuthority -RepoRoot $RepoRoot
if(@($authority.fragment_kinds).Count-ne 12-or@($authority.api_surfaces).Count-ne 9-or@($authority.transports).Count-ne 17-or@($authority.builder_commands).Count-ne 10){throw '[mir4-w05-authority-counts]'}
if($authority.semantic_authority-or$authority.prototype_write_authorized-or$authority.runtime_state_mutation_authorized-or$authority.migration_execution_authorized-or$authority.safety_kernel_override_authorized-or$authority.public_support_authorized-or$authority.signing_or_sealing_authorized-or$authority.publication_authorized){throw '[mir4-w05-authority-boundary]'}

$reference=New-MIR4ReferenceExtensionV1 -RepoRoot $RepoRoot
Test-MIR4MepV1Envelope -Envelope $reference -RepoRoot $RepoRoot|Out-Null
if(@($reference.fragments).Count-ne 12-or@($reference.fragments.kind|Sort-Object -Unique).Count-ne 12){throw '[mir4-w05-fragment-coverage]'}
$forbidden=$reference|ConvertTo-Json -Depth 100|ConvertFrom-Json;$forbidden.fragments[0].data|Add-Member -NotePropertyName nested -NotePropertyValue ([pscustomobject]@{safety_kernel_override=$true})
try{Test-MIR4MepV1Envelope -Envelope $forbidden -RepoRoot $RepoRoot|Out-Null;throw '[mir4-w05-forbidden-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-v1-forbidden-field]')){throw}}

$v0=New-MIR4ReferenceExtension
$migrated=ConvertFrom-MIR4MepV0ToV1 -Envelope $v0
Test-MIR4MepV1Envelope -Envelope $migrated -RepoRoot $RepoRoot|Out-Null
if([string]$migrated.extension_version-cne'0.0.0-migrated'-or@($migrated.fragments).Count-ne 8){throw '[mir4-w05-migration-helper]'}

$addon=$reference|ConvertTo-Json -Depth 100|ConvertFrom-Json
$addon.extension_id='org.example.addon';$addon.namespace='org.example.addon';$addon.extension_version='1.0.0-preview'
foreach($fragment in @($addon.fragments)){$fragment.id=$fragment.id.Replace('org.more-infinite-research.reference','org.example.addon')}
$addon.fragments[5].data.extension_id='org.more-infinite-research.reference';$addon.digest='';$addon.digest=Get-MIR4ModuleDigest $addon
$closureA=Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($reference,$addon) -Target f210
$closureB=Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($addon,$reference) -Target f210
if($closureA.digest-cne$closureB.digest-or-not$closureA.complete-or($closureA.order-join'|')-cne'org.more-infinite-research.platform|org.more-infinite-research.reference|org.example.addon'){throw '[mir4-w05-closure-determinism]'}
$missing=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-mep-v1/negative/missing-dependency.json')|ConvertFrom-Json
try{Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($missing) -Target f210|Out-Null;throw '[mir4-w05-missing-dependency-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-v1-missing-dependency]')){throw}}
$cycleA=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-mep-v1/negative/cycle-a.json')|ConvertFrom-Json
$cycleB=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'fixtures/mir4-mep-v1/negative/cycle-b.json')|ConvertFrom-Json
try{Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($cycleA,$cycleB) -Target f210|Out-Null;throw '[mir4-w05-cycle-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-v1-dependency-cycle]')){throw}}
$conflict=$addon|ConvertTo-Json -Depth 100|ConvertFrom-Json;$conflict.fragments[5].data.extension_id='org.more-infinite-research.platform';$conflict.fragments[6].data.extension_ids=@('org.more-infinite-research.reference');$conflict.digest='';$conflict.digest=Get-MIR4ModuleDigest $conflict
try{Resolve-MIR4ExtensionClosureV1 -RepoRoot $RepoRoot -Extensions @($reference,$conflict) -Target f210|Out-Null;throw '[mir4-w05-conflict-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-v1-conflict]')){throw}}

$transport=New-MIR4TargetTransportPlanV1 -RepoRoot $RepoRoot
if(@($transport.targets).Count-ne 17-or[string]@($transport.targets|Where-Object target -eq f210)[0].admission-cne'blocked-by-terminal-emitter'-or[string]@($transport.targets|Where-Object target -eq f200)[0].transport-cne'versioned-namespaced-stage-local-bus'-or@($transport.targets|Where-Object{$_.target-in@('f012','f011','f010','f009','f008','f007','f006')-and$_.admission-eq'BLOCKED_WITH_EVIDENCE'}).Count-ne 7){throw '[mir4-w05-transport-truth]'}

$input=[pscustomobject]@{id='first';nested=[pscustomobject]@{value='original'}}
$page1=New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface query -Target f210 -Items @($input,[pscustomobject]@{id='second'}) -Limit 1
$page2=New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface query -Target f210 -Items @($input,[pscustomobject]@{id='second'}) -Limit 1 -Cursor $page1.page.next_cursor
$page1.items[0].nested.value='changed'
if($input.nested.value-cne'original'-or$page1.page.total-ne 2-or$page1.page.next_cursor-cne'1'-or$page2.items[0].id-cne'second'){throw '[mir4-w05-api-copy-pagination]'}
$unavailable=New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface observation -Target f012 -Availability unavailable -Reason 'No admitted observation transport.' -Evidence @('target:f012')
if($unavailable.availability.status-cne'unavailable'-or$null-ne$unavailable.page.total-or@($unavailable.items).Count-ne 0){throw '[mir4-w05-unavailable-is-not-zero]'}
$responses=@(foreach($surface in $authority.api_surfaces){New-MIR4ApiV1Response -RepoRoot $RepoRoot -Surface ([string]$surface) -Target f210 -Items @()})
if(@($responses.surface|Sort-Object -Unique).Count-ne 9-or@($responses|Where-Object{$_.package_visible-or$_.mutation_authorized-or$_.public_support_claim-or$_.page.limit-gt 128}).Count-ne 0){throw '[mir4-w05-api-surface-boundary]'}

Invoke-MIR4SdkGenerate -RepoRoot $RepoRoot -Check
foreach($path in @('spec/schemas/preview/mir4-mep-v1.schema.json','sdk/preview/mir4/mep-v1/lua/mir4_mep_v1.lua','sdk/preview/mir4/mep-v1/lua/mir4_mep_v1.luals.lua','sdk/preview/mir4/api-v1/typescript/index.ts','sdk/preview/mir4/api-v1/python/mir4_api_v1.py','sdk/preview/mir4/api-v1/powershell/MIR4.Api.V1.psm1','sdk/preview/mir4/mep-v1/migration/Convert-MIR4MepV0ToV1.ps1','sdk/preview/mir4/reference-extension-v1/extension.json','sdk/preview/mir4/mep-v1/conformance.ps1')){if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $path) -PathType Leaf)){throw "[mir4-w05-sdk-file] $path"}}
$builderRoot='build/mir4/test-w05-extension-builder'
$initRoot="$builderRoot/init";$packageRoot="$builderRoot/package";$migrationRoot="$builderRoot/migration"
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command init -RepoRoot $RepoRoot -OutputRoot $initRoot -ExtensionId org.example.builder|Out-Null
$builderExtension="$initRoot/extension.json"
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command validate -RepoRoot $RepoRoot -ExtensionPath $builderExtension|Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command explain -RepoRoot $RepoRoot -ExtensionPath $builderExtension|Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command test -RepoRoot $RepoRoot -ExtensionPath $builderExtension|Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command package -RepoRoot $RepoRoot -ExtensionPath $builderExtension -OutputRoot $packageRoot|Out-Null
$builderZip=Get-ChildItem -LiteralPath (Join-Path $RepoRoot $packageRoot) -Filter *.zip -File
if(@($builderZip).Count-ne 1){throw '[mir4-w05-builder-package]'}
$builderZipHash=(Get-FileHash -LiteralPath $builderZip.FullName -Algorithm SHA256).Hash
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command package -RepoRoot $RepoRoot -ExtensionPath $builderExtension -OutputRoot $packageRoot|Out-Null
if((Get-FileHash -LiteralPath $builderZip.FullName -Algorithm SHA256).Hash-cne$builderZipHash){throw '[mir4-w05-builder-package-determinism]'}
& (Join-Path $RepoRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command migrate -RepoRoot $RepoRoot -ExtensionPath 'sdk/preview/mir4/reference-extension/extension.json' -OutputRoot $migrationRoot|Out-Null
$migratedBuilder=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$migrationRoot/extension-v1.json")|ConvertFrom-Json
Test-MIR4MepV1Envelope -Envelope $migratedBuilder -RepoRoot $RepoRoot|Out-Null
$shadow=New-MIR4ShadowExtensionCompilationV1 -RepoRoot $RepoRoot -TargetId f210 -Envelope $reference
if($shadow.result-cne'shadow-complete'-or$shadow.authoritative_output-or$shadow.mutation_capability-or$shadow.public_support_claim-or@($shadow.contributions).Count-ne 12){throw '[mir4-w05-shadow-boundary]'}

$candidatePath=$null
if(-not[string]::IsNullOrWhiteSpace($CandidateZip)){
  $candidateInput=if([IO.Path]::IsPathRooted($CandidateZip)){$CandidateZip}else{Join-Path $RepoRoot $CandidateZip}
  if(Test-Path -LiteralPath $candidateInput -PathType Leaf){$candidatePath=$candidateInput}
  elseif(-not$hostedReceiptOnly){throw '[mir4-w05-private-candidate-required]'}
}
$output='build/mir4/test-w05-module-ecosystem'
& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4ModuleEcosystemRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -CandidateZip $candidatePath|Out-Null
& (Join-Path $RepoRoot 'tools/commands/mir4/Export-MIR4ModuleEcosystemRecords.ps1') -RepoRoot $RepoRoot -OutputRoot $output -CandidateZip $candidatePath -Check|Out-Null
$head=(& git -C $RepoRoot rev-parse HEAD).Trim();$tree=(& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
foreach($name in @('MIR4_MEP_CONFORMANCE.json','MIR4_API_SDK_GRADUATION_MATRIX.json','MIR4_REFERENCE_CONSUMER_RESULT.json')){$record=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$output/$name")|ConvertFrom-Json;if([string]$record.source_identity.commit-cne$head-or[string]$record.source_identity.tree-cne$tree-or$record.package_visible-or$record.public_support_claim){throw "[mir4-w05-export-identity] $name"}}
$consumer=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$output/MIR4_REFERENCE_CONSUMER_RESULT.json")|ConvertFrom-Json
if($consumer.production_consumer_status-cne'BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'-or$consumer.fallback.result-cne'passed'-or$consumer.graduated){throw '[mir4-w05-consumer-truth]'}
$mep=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$output/MIR4_MEP_CONFORMANCE.json")|ConvertFrom-Json
if($hostedReceiptOnly-and$null-ne$mep.candidate){throw '[mir4-w05-hosted-absent-candidate-boundary]'}
if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$packageBefore){throw '[mir4-w05-package-mutation]'}
Write-Host '[ok] MIR 4 W05 MEP V1, deterministic closure, API/SDK, builder, and synthetic consumer preview passed.'
