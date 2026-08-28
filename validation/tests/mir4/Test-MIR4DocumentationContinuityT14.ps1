param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')

$before=Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
$authorityPath=Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json'
$authorityText=Get-Content -Raw -LiteralPath $authorityPath
if(-not($authorityText|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-documentation-continuity-t14-v1.schema.json'))){throw '[mir4-t14-authority-schema]'}
$authority=$authorityText|ConvertFrom-Json -Depth 100
if([string]$authority.package_source_fingerprint_before-cne'9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'-or
  [string]$authority.package_source_fingerprint_after-cne$before-or(@($authority.package_visible_delta)-join'|')-cne'README.md'-or
  -not$authority.player_executable_sources_unchanged-or-not$authority.one_emitter_preserved-or
  $authority.source_freeze_authorized-or$authority.signing_or_sealing_authorized-or$authority.promotion_authorized-or$authority.publication_authorized){
  throw '[mir4-t14-package-and-authority-boundary]'
}

& (Join-Path $RepoRoot 'tools/commands/docs/Update-MIRDocumentationIndex.ps1') -RepoRoot $RepoRoot -Check|Out-Null

$immutableTruthPath=Join-Path $RepoRoot '.mir/docs-immutable-source-truth.json'
$immutableTruthText=Get-Content -Raw -LiteralPath $immutableTruthPath
if(-not($immutableTruthText|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir-immutable-documentation-source-truth-v1.schema.json'))){throw '[mir4-t14-immutable-doc-truth-schema]'}
$immutableTruth=$immutableTruthText|ConvertFrom-Json -Depth 20
if(@($immutableTruth.records).Count-ne40-or@($immutableTruth.records.path|Sort-Object -Unique).Count-ne40){throw '[mir4-t14-immutable-doc-truth-set]'}
foreach($record in @($immutableTruth.records)){
  $releaseNote=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$record.path))
  $front=[regex]::Match($releaseNote,'\A---\r?\n(?<body>.*?)(?:\r?\n)---\r?\n',[Text.RegularExpressions.RegexOptions]::Singleline)
  if(-not$front.Success-or$front.Groups['body'].Value-match'(?m)^source_of_truth_for:'){throw "[mir4-t14-immutable-doc-byte-custody] $($record.path)"}
}

$rootDocs=@(
  'README.md','CONTRIBUTING.md','AGENTS.md','GOVERNANCE.md','SECURITY.md','PROJECT-CONTINUITY.md',
  'FORKING.md','MAINTAINER-HANDOFF.md','EXTENSION-PROTOCOL.md','RELEASE-RUNBOOK.md','SUPPORT.md'
)
foreach($path in $rootDocs){if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $path)-PathType Leaf)){throw "[mir4-t14-root-doc] $path"}}

$readme=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'README.md')
foreach($term in @('MIR 4.0 Whole-Platform Genesis','4.0.21000','4.0.20000','stable','preview','shadow','experimental','omitted','SupportBundleV1','No blanket')){
  if($readme-notmatch[regex]::Escape($term)){throw "[mir4-t14-readme-contract] $term"}
}
$agents=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'AGENTS.md')
if($agents-notmatch'dev.*origin/dev'-or$agents-notmatch'one emitter'-or$agents-notmatch'package-source parity'){throw '[mir4-t14-agent-continuity]'}
$runbook=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'RELEASE-RUNBOOK.md')
foreach($phase in @('source freeze','target build','target qualification','preview assets','independent verification','release seal','promotion','target publication','public readback','restore drill')){
  if($runbook-notmatch[regex]::Escape($phase)){throw "[mir4-t14-release-phase] $phase"}
}

$developerDocs=@(
  'README.md','first-extension.md','compatibility-cookbook.md','mep-fragment-reference.md','api-versioning.md',
  'canonicalization.md','diagnostics.md','environment-locks.md','testing-against-factorio.md',
  'publishing-an-extension.md','v0-to-v1-migration.md','inspector.md','processir.md'
)
foreach($path in $developerDocs){if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot ('docs/developer/'+$path))-PathType Leaf)){throw "[mir4-t14-developer-doc] $path"}}

$resultRoot=Join-Path $RepoRoot 'build/results/mir4-t14-documentation-continuity'
$buildBoundary=[IO.Path]::GetFullPath((Join-Path $RepoRoot 'build')).TrimEnd('\')+'\'
$resultBoundary=[IO.Path]::GetFullPath($resultRoot).TrimEnd('\')+'\'
if(-not$resultBoundary.StartsWith($buildBoundary,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-t14-output-boundary]'}
if(Test-Path -LiteralPath $resultRoot){Remove-Item -LiteralPath $resultRoot -Recurse -Force}
New-Item -ItemType Directory -Force -Path $resultRoot|Out-Null

$assets=Join-Path $resultRoot 'assets'
New-MIR4PlatformPreviewPackages -RepoRoot $RepoRoot -OutputRoot $assets|Out-Null
$archive=Join-Path $assets 'mir4-mep-v1-preview.zip'
$extract=Join-Path $resultRoot 'extract'
Expand-Archive -LiteralPath $archive -DestinationPath $extract
$portableRoot=Join-Path $extract 'mir4-mep-v1-preview'
$command=Join-Path $portableRoot 'tools/mir/cli/Invoke-MIR4Extension.ps1'
$work=Join-Path $portableRoot 'work/first'

$doctor=& $command -Command doctor -RepoRoot $portableRoot|ConvertFrom-Json
if([string]$doctor.status-cne'passed'){throw '[mir4-t14-tutorial-doctor]'}
& $command -Command init -RepoRoot $portableRoot -ExtensionId org.example.first -Template minimal -OutputRoot $work|Out-Null
$extension=Join-Path $work 'extension.json'
& $command -Command validate -RepoRoot $portableRoot -ExtensionPath $extension|Out-Null
$lock=& $command -Command lock -RepoRoot $portableRoot -ExtensionPath $extension -Target f210 -OutputRoot $work|ConvertFrom-Json
if([string]$lock.status-cne'review-required'){throw '[mir4-t14-tutorial-lock]'}
& $command -Command explain -RepoRoot $portableRoot -ExtensionPath $extension -Target f210|Out-Null
$test=& $command -Command test -RepoRoot $portableRoot -ExtensionPath $extension -Target f210|ConvertFrom-Json
if([string]$test.status-cne'passed'-or[bool]$test.player_mutation_authorized){throw '[mir4-t14-tutorial-test]'}
$package=& $command -Command package -RepoRoot $portableRoot -ExtensionPath $extension -OutputRoot (Join-Path $portableRoot 'work/package')|ConvertFrom-Json
if([string]$package.status-cne'packaged'-or-not(Test-Path -LiteralPath ([string]$package.path)-PathType Leaf)){throw '[mir4-t14-tutorial-package]'}

if((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot)-cne$before){throw '[mir4-t14-unrecorded-package-drift]'}
Write-Host '[ok] MIR 4 T14 documentation authority, MIR4-first continuity, release runbook, and clean extracted preview tutorial passed.'
