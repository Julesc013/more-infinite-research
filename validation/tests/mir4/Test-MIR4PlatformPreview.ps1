$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path $repo 'tools\lib\mir4\PlatformPreview.ps1')
Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check|Out-Null
Test-MIR4PlatformConformance -RepoRoot $repo|Out-Null
if((ConvertTo-MIR4PlatformCanonicalJson ([ordered]@{empty=@()})) -cne '{"empty":[]}'){throw '[mir4-platform-canonical-empty-array]'}
$lineEndingProbeRoot=Join-Path $repo 'build/results/mir4-platform-line-ending-probe'
New-Item -ItemType Directory -Force -Path $lineEndingProbeRoot|Out-Null
$lfProbe=Join-Path $lineEndingProbeRoot 'lf.txt'
$crlfProbe=Join-Path $lineEndingProbeRoot 'crlf.txt'
[IO.File]::WriteAllBytes($lfProbe,[Text.UTF8Encoding]::new($false).GetBytes("alpha`nbeta`n"))
[IO.File]::WriteAllBytes($crlfProbe,[Text.UTF8Encoding]::new($false).GetBytes("alpha`r`nbeta`r`n"))
if((Get-MIR4PlatformInputSha256 $lfProbe)-cne(Get-MIR4PlatformInputSha256 $crlfProbe)){throw '[mir4-platform-input-line-ending-invariance]'}
$lfAuthority=New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'line-ending-probe' -Path 'build/results/mir4-platform-line-ending-probe/lf.txt' -Status 'probe' -Maturity 'test'
$crlfAuthority=New-MIR4SemanticAuthorityRef -RepoRoot $repo -Role 'line-ending-probe' -Path 'build/results/mir4-platform-line-ending-probe/crlf.txt' -Status 'probe' -Maturity 'test'
if([string]$lfAuthority.sha256-cne[string]$crlfAuthority.sha256){throw '[mir4-semantic-authority-line-ending-invariance]'}

$platform=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec\platform\mir4-preview-v0\platform.json')|ConvertFrom-Json
if(@($platform.components).Count -lt 23){throw '[mir4-platform-components] Expected the complete hybrid component inventory.'}
if(@($platform.mep_fragments).Count -ne 8){throw '[mir4-platform-mep] Expected exactly eight bounded V0 fragment kinds.'}
if(@($platform.non_interference).Count -ne 8){throw '[mir4-platform-non-interference] Expected all eight non-interference rules.'}

$providers=(Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk\preview\mir4\reference\target-providers.json')|ConvertFrom-Json).providers
if(@($providers).Count -ne 17){throw '[mir4-platform-targets] Expected all 17 governed target providers.'}
foreach($target in @('f210','f200','f110','f100','f018','f017','f016','f015','f014','f013')){if($target -notin @($providers.id)){throw "[mir4-platform-target] Missing $target"}}
$affected=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/affected-target-plan.json')|ConvertFrom-Json
if(@($affected.targets).Count -ne 17 -or @($affected.targets|Where-Object authoritative).Count){throw '[mir4-platform-affected-target-plan]'}
$affectedF210=$affected.targets|Where-Object target -eq 'f210'
$affectedF018=$affected.targets|Where-Object target -eq 'f018'
if([string]$affectedF210.plan -cne 'build-and-qualify-mandatory'){throw '[mir4-platform-affected-target-f210]'}
if([string]$affectedF018.plan -cne 'blocked-missing-exact-engine'){throw '[mir4-platform-affected-target-f018]'}
if(@($affected.targets|Where-Object{$_.target -in @('f012','f011','f010','f009','f008','f007','f006') -and $_.plan -ne 'omitted-by-target'}).Count){throw '[mir4-platform-affected-target-museum]'}

$extension=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference-extension/extension.json')|ConvertFrom-Json
$shadowA=New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId f210 -Envelope $extension
$shadowB=New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId f210 -Envelope $extension
if($shadowA.digest-cne$shadowB.digest-or$shadowA.authoritative_output-or$shadowA.mutation_capability-or$shadowA.public_support_claim){throw '[mir4-platform-shadow-compile-noninterference]'}
if(@($shadowA.contributions).Count -ne @($extension.fragments).Count -or @($shadowA.contributions|Where-Object{$_.policy.safety.status -ne 'accepted-for-policy-evaluation'}).Count){throw '[mir4-platform-shadow-compile-incomplete]'}
$missing=$extension|ConvertTo-Json -Depth 100|ConvertFrom-Json
($missing.fragments|Where-Object kind -eq 'CapabilityRequirement').data.all_of=@('query.read','unavailable.capability')
$missing.digest=Get-MIR4PlatformDigest $missing
$missingRun=New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId f210 -Envelope $missing
if($missingRun.result -cne 'review-required' -or -not @($missingRun.diagnostics|Where-Object code -eq 'mir4-shadow-capability-unavailable')){throw '[mir4-platform-shadow-capability-diagnostic]'}
try{New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId f013 -Envelope $extension|Out-Null;throw '[mir4-platform-shadow-undeclared-target-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-shadow-target-not-declared]')){throw}}
$shadowOutput='build/results/mir4-shadow/reference-f210.json'
$written=Invoke-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId f210 -ExtensionPath 'sdk/preview/mir4/reference-extension/extension.json' -OutputPath $shadowOutput
if($written.digest -cne $shadowA.digest){throw '[mir4-platform-shadow-write-determinism]'}
try{Invoke-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId f210 -ExtensionPath 'sdk/preview/mir4/reference-extension/extension.json' -OutputPath 'docs/forbidden-shadow-output.json'|Out-Null;throw '[mir4-platform-shadow-output-escape-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-shadow-output-boundary]')){throw}}
$opportunities=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/opportunity-catalogue.json')|ConvertFrom-Json
if([string]$opportunities.kind-cne'MIR4SynthesisMaturityMatrixV1'-or@($opportunities.constructors).Count-ne 10-or@($opportunities.terminal_dispositions).Count-ne 5-or@($opportunities.candidates).Count-lt 12){throw '[mir4-platform-opportunity-catalogue]'}
if(@($opportunities.candidates|Where-Object{$_.mutation_authorized-or$_.planner_admission-or$_.operation_object}).Count-or$opportunities.automatic_player_mutation){throw '[mir4-platform-opportunity-authority]'}
$processParity=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/process-ir-parity-result.json')|ConvertFrom-Json
$effectRegistry=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/effect-channel-registry-v1.json')|ConvertFrom-Json
if(-not$processParity.passed-or-not$processParity.bilateral_gate.passed-or[string]$processParity.exact_target_status-cne'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'-or-not$processParity.exact_target_evidence.deterministic-or$processParity.exact_target_evidence.authoritative){throw '[mir4-platform-processir-parity]'}
if(@($effectRegistry.channels).Count-ne 6-or-not$effectRegistry.opaque_preserved-or$effectRegistry.player_mutation_authorized){throw '[mir4-platform-effect-registry]'}
$runtimeInventory=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/runtime-state-inventory.json')|ConvertFrom-Json
if([string]$runtimeInventory.kind-cne'MIR4RuntimeStateMatrixV1'-or@($runtimeInventory.runtime_feature_specs).Count-ne 7-or@($runtimeInventory.state_specs).Count-ne 5-or@($runtimeInventory.registration_plan.groups).Count-ne 9-or@($runtimeInventory.targets).Count-ne 17-or-not$runtimeInventory.registration_plan.law_results.all_passed){throw '[mir4-platform-runtime-state-inventory]'}
$runtimeF210=@($runtimeInventory.targets|Where-Object { $_.target -eq 'f210' })[0]
$runtimeF110=@($runtimeInventory.targets|Where-Object { $_.target -eq 'f110' })[0]
if($runtimeF210.backend-cne'storage'-or$runtimeF110.backend-cne'global'-or@($runtimeF110.feature_dispositions|Where-Object { $_.disposition -ne 'compiled-out' }).Count-ne 0){throw '[mir4-platform-runtime-target-backends]'}
$migration=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/migration-graph-matrix.json')|ConvertFrom-Json
if([string]$migration.kind-cne'MIR4MigrationGraphMatrixV1'-or@($migration.edges).Count-ne 10-or@($migration.edge_kinds).Count-ne 8-or-not$migration.law_results.all_passed-or$migration.complete_for_public_release){throw '[mir4-platform-migration-graph]'}
$continuity=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/continuity-bundle-template.json')|ConvertFrom-Json
if([string]$continuity.kind-cne'MIR4ContinuityBundleV1'-or$continuity.target_count-ne 17-or-not$continuity.redaction_manifest.complete-or$continuity.package_visible-or$continuity.public_release_proof){throw '[mir4-platform-continuity-bundle]'}
$inspector=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/inspector/index.html')
if($inspector.Contains('innerHTML') -or -not $inspector.Contains('textContent') -or -not $inspector.Contains('mir4-inspector-invalid-json')){throw '[mir4-platform-inspector-safe-rendering]'}

$dag=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec\platform\mir4-preview-v0\release-dag.json')|ConvertFrom-Json
Test-MIR4ReleaseDag -Dag $dag|Out-Null
$cycle=$dag|ConvertTo-Json -Depth 20|ConvertFrom-Json
($cycle.nodes|Where-Object id -eq 'authority').depends_on=@('public-readback')
try{Test-MIR4ReleaseDag -Dag $cycle|Out-Null;throw '[mir4-release-dag-cycle-accepted]'}catch{if(-not $_.Exception.Message.StartsWith('[mir4-release-dag-cycle]')){throw}}
$boundary=$dag|ConvertTo-Json -Depth 20|ConvertFrom-Json
($boundary.nodes|Where-Object id -eq 'publish-github').authorization='candidate-programme'
try{Test-MIR4ReleaseDag -Dag $boundary|Out-Null;throw '[mir4-release-dag-boundary-accepted]'}catch{if(-not $_.Exception.Message.StartsWith('[mir4-release-dag-production-boundary]')){throw}}

$query=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk\preview\mir4\reference\query-snapshot-f210.json')|ConvertFrom-Json
. (Join-Path $repo 'tools\lib\mir4\ExperimentalApiSdk.ps1')
Test-MIR4ApiRecord -Record $query -RepoRoot $repo|Out-Null

$previewA=New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot 'build/results/mir4-preview-determinism/A'
$previewB=New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot 'build/results/mir4-preview-determinism/B'
if($previewA.digest -cne $previewB.digest -or (ConvertTo-MIR4PlatformCanonicalJson $previewA.assets) -cne (ConvertTo-MIR4PlatformCanonicalJson $previewB.assets)){throw '[mir4-platform-preview-nondeterministic]'}
if([string]$previewA.kind-cne'MIR4PreviewAssetSetV1'-or[string]$previewA.candidate_state-cne'pre-freeze-unallocated'){throw '[mir4-platform-preview-v1-authority]'}
if(@($previewA.assets|Where-Object name -match 'v0').Count){throw '[mir4-platform-preview-v0-asset]'}
$expectedAssets=@('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip')
if((@($previewA.assets.name|Sort-Object)-join'|')-cne(@($expectedAssets|Sort-Object)-join'|')){throw '[mir4-platform-preview-asset-contract]'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($asset in @($previewA.assets)){
  $assetPath=Join-Path $repo ('build/results/mir4-preview-determinism/A/'+[string]$asset.name)
  $zip=[IO.Compression.ZipFile]::OpenRead($assetPath)
  try{
    $root=[IO.Path]::GetFileNameWithoutExtension([string]$asset.name)
    $manifestEntry=$zip.GetEntry("$root/manifest.json")
    $sbomEntry=$zip.GetEntry("$root/sbom.spdx.json")
    $provenanceEntry=$zip.GetEntry("$root/provenance.json")
    if(-not$manifestEntry-or-not$sbomEntry-or-not$provenanceEntry){throw "[mir4-platform-preview-metadata] $($asset.name)"}
    $reader=[IO.StreamReader]::new($manifestEntry.Open())
    try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json -Depth 100}finally{$reader.Dispose()}
    if([string]$manifest.kind-cne'MIR4PreviewAssetManifestV1'-or
       [string]$manifest.source.commit-cnotmatch'^[0-9a-f]{40}$'-or
       [string]$manifest.source.tree-cnotmatch'^[0-9a-f]{40}$'-or
       [string]$manifest.contract_set.digest-cnotmatch'^sha256:[0-9a-f]{64}$'-or
       @($manifest.contract_set.files).Count-lt1-or
       [string]$manifest.conformance.status-cne'passed-before-packaging'-or
       @($manifest.license_inventory|Where-Object spdx_id -eq 'MPL-2.0').Count-ne1-or
       @($manifest.generated_source_map).Count-lt1-or
       @($manifest.embedded_metadata).Count-ne2-or
       [bool]$manifest.production_candidate-or[bool]$manifest.publication_authorized){
      throw "[mir4-platform-preview-manifest-completeness] $($asset.name)"
    }
    $sbomReader=[IO.StreamReader]::new($sbomEntry.Open())
    try{$sbom=$sbomReader.ReadToEnd()|ConvertFrom-Json -Depth 100}finally{$sbomReader.Dispose()}
    if([string]$sbom.spdxVersion-cne'SPDX-2.3'-or[string]$sbom.packages[0].licenseDeclared-cne'MPL-2.0'-or
       @($sbom.files).Count-ne@($manifest.files).Count){throw "[mir4-platform-preview-sbom] $($asset.name)"}
    $provenanceReader=[IO.StreamReader]::new($provenanceEntry.Open())
    try{$provenance=$provenanceReader.ReadToEnd()|ConvertFrom-Json -Depth 100}finally{$provenanceReader.Dispose()}
    if([string]$provenance.kind-cne'MIR4PreviewProvenanceV1'-or[bool]$provenance.publication_authorized-or
       @($provenance.materials).Count-ne@($manifest.files).Count-or
       [string]$provenance.contract_set_digest-cne[string]$manifest.contract_set.digest){throw "[mir4-platform-preview-provenance] $($asset.name)"}
    foreach($file in @($manifest.files)){
      $payload=$zip.GetEntry("$root/$([string]$file.path)")
      if(-not$payload){throw "[mir4-platform-preview-manifest-path] $($asset.name):$($file.path)"}
      $payloadStream=$payload.Open()
      try{
        $memory=[IO.MemoryStream]::new()
        try{$payloadStream.CopyTo($memory);$payloadHash=Get-MIR4PlatformBytesSha256 $memory.ToArray()}finally{$memory.Dispose()}
      }finally{$payloadStream.Dispose()}
      if($payloadHash-cne[string]$file.sha256){throw "[mir4-platform-preview-manifest-hash] $($asset.name):$($file.path)"}
    }
  }finally{$zip.Dispose()}
}
$portableRoot=Join-Path $repo ('build/results/mir4-sdk-portability/'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $portableRoot|Out-Null
Expand-Archive -LiteralPath (Join-Path $repo 'build/results/mir4-preview-determinism/A/mir4-api-sdk-v1-preview.zip') -DestinationPath $portableRoot
$apiRoot=Join-Path $portableRoot 'mir4-api-sdk-v1-preview/sdk/preview/mir4/api-v1'
foreach($relative in @('powershell/MIR4.Api.V1.psm1','python/mir4_api_v1.py','typescript/index.ts','json-schema/mir4-api-v1-response.schema.json')){
  if(-not(Test-Path -LiteralPath (Join-Path $apiRoot $relative)-PathType Leaf)){throw "[mir4-platform-sdk-portable-binding] $relative"}
}
Import-Module (Join-Path $apiRoot 'powershell/MIR4.Api.V1.psm1') -Force

Write-Host 'MIR 4 platform preview validation passed.'
