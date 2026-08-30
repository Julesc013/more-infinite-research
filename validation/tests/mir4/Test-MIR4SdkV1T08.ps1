param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4PackagePresentationV1 -RepoRoot $repo -PackageSourceSha256 $packageBefore|Out-Null
Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check|Out-Null
$corpusPath=Join-Path $repo 'sdk/preview/mir4/api-v1/conformance/corpus.json'
$corpusJson=Get-Content -Raw -LiteralPath $corpusPath
if(-not($corpusJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/preview/mir4-sdk-v1-conformance-corpus.schema.json'))){throw '[mir4-t08-corpus-schema]'}
$corpus=$corpusJson|ConvertFrom-Json -Depth 100
if(@($corpus.positive).Count-lt12-or@($corpus.negative).Count-lt16){throw '[mir4-t08-corpus-cardinality]'}

$bindings=[ordered]@{
  'sdk/preview/mir4/api-v1/powershell/MIR4.Api.V1.psm1'=@('ConvertFrom-MIR4ApiV1Json','Test-MIR4ApiV1Response','ConvertTo-MIR4ApiV1CanonicalJson','Get-MIR4ApiV1Digest','Get-MIR4ApiV1Capabilities','Get-MIR4ApiV1Availability','Get-MIR4ApiV1Page','Compare-MIR4ApiV1Snapshot','Format-MIR4ApiV1Diagnostic','Test-MIR4ApiV1Extension','Test-MIR4ApiV1Manifest','Test-MIR4ApiV1Archive')
  'sdk/preview/mir4/api-v1/python/mir4_api_v1.py'=@('def parse','def validate','def canonicalize','def digest','def negotiate_capabilities','def decode_availability','def bounded_page','def compare_snapshots','def render_diagnostic','def validate_extension','def verify_manifest','def verify_archive')
  'sdk/preview/mir4/api-v1/typescript/index.mjs'=@('function parse','function validate','function canonicalize','function digest','function negotiateCapabilities','function decodeAvailability','function boundedPage','function compareSnapshots','function renderDiagnostic','function validateExtension','function verifyManifest','function verifyArchive')
  'sdk/preview/mir4/api-v1/lua/mir4_api_v1.lua'=@('M.parse','M.validate','M.canonicalize','M.digest','M.negotiate_capabilities','M.decode_availability','M.bounded_page','M.compare_snapshots','M.render_diagnostic','M.validate_extension','M.verify_manifest','M.verify_archive')
}
foreach($binding in $bindings.GetEnumerator()){
  $text=Get-Content -Raw -LiteralPath (Join-Path $repo $binding.Key)
  foreach($operation in $binding.Value){if($text-notmatch[regex]::Escape($operation)){throw "[mir4-t08-operation-missing] $($binding.Key):$operation"}}
}

$localRaw=& (Join-Path $repo 'sdk/preview/mir4/conformance-v1/Invoke-MIR4SdkV1Conformance.ps1') -SdkRoot (Join-Path $repo 'sdk/preview/mir4') -RequireNode:([bool](Get-Command node -ErrorAction SilentlyContinue))
$local=$localRaw|ConvertFrom-Json -Depth 100
if([string]$local.status-cne'passed'-or-not[bool]$local.identical_accept_reject-or-not[bool]$local.identical_digests){throw '[mir4-t08-local-conformance]'}

$resultRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build/results/mir4-t08-sdk-v1'))
$buildPrefix=[IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\')+'\'
if(-not($resultRoot+'\').StartsWith($buildPrefix,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-t08-output-boundary]'}
if(Test-Path -LiteralPath $resultRoot){Remove-Item -LiteralPath $resultRoot -Recurse -Force}
$a=Join-Path $resultRoot 'A';$b=Join-Path $resultRoot 'B'
$assetsA=New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot $a
$assetsB=New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot $b
$zipA=Join-Path $a 'mir4-api-sdk-v1-preview.zip';$zipB=Join-Path $b 'mir4-api-sdk-v1-preview.zip'
if((Get-FileHash -LiteralPath $zipA -Algorithm SHA256).Hash-cne(Get-FileHash -LiteralPath $zipB -Algorithm SHA256).Hash){throw '[mir4-t08-archive-nondeterministic]'}
Import-Module (Join-Path $repo 'sdk/preview/mir4/api-v1/powershell/MIR4.Api.V1.psm1') -Force
Test-MIR4ApiV1Archive -ArchivePath $zipA|Out-Null

$extract=Join-Path $resultRoot 'extracted'
Expand-Archive -LiteralPath $zipA -DestinationPath $extract
$sdkRoot=Join-Path $extract 'mir4-api-sdk-v1-preview/sdk/preview/mir4'
$portableRaw=& (Join-Path $sdkRoot 'conformance-v1/Invoke-MIR4SdkV1Conformance.ps1') -SdkRoot $sdkRoot -RequireNode:([bool](Get-Command node -ErrorAction SilentlyContinue))
$portable=$portableRaw|ConvertFrom-Json -Depth 100
if([string]$portable.status-cne'passed'-or(@($portable.runtimes)-join'|')-cne(@($local.runtimes)-join'|')){throw '[mir4-t08-extracted-conformance]'}
foreach($path in @(
  'api-v1/typescript/index.ts','api-v1/typescript/index.mjs','api-v1/typescript/package.json',
  'api-v1/python/mir4_api_v1.py','api-v1/powershell/MIR4.Api.V1.psm1',
  'api-v1/lua/mir4_api_v1.lua','api-v1/lua/mir4_api_v1.luals.lua',
  'api-v1/conformance/corpus.json','api-v1/package-metadata.json',
  'conformance-v1/Invoke-MIR4SdkV1Conformance.ps1'
)){if(-not(Test-Path -LiteralPath (Join-Path $sdkRoot $path)-PathType Leaf)){throw "[mir4-t08-archive-file] $path"}}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$packageBefore){throw '[mir4-t08-player-package-drift]'}

Write-Host '[ok] MIR 4 T08 SDK V1 bindings, 12+/16+ corpus, cross-runtime identity, deterministic archives, extracted conformance, and package exclusion passed.'
