param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/mir4/ExtensionDeveloperExperience.ps1')

$expectedPackage='9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'
$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
if($packageBefore-cne$expectedPackage){throw '[mir4-t09-player-package-baseline]'}
$clock=[Diagnostics.Stopwatch]::StartNew()
Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check|Out-Null

$resultRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build/results/mir4-t09-extension-developer-experience'))
$buildPrefix=[IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\')+'\'
if(-not($resultRoot+'\').StartsWith($buildPrefix,[StringComparison]::OrdinalIgnoreCase)){throw '[mir4-t09-output-boundary]'}
if(Test-Path -LiteralPath $resultRoot){Remove-Item -LiteralPath $resultRoot -Recurse -Force}
New-Item -ItemType Directory -Force -Path $resultRoot|Out-Null
$command=Join-Path $repo 'tools/commands/mir4/Invoke-MIR4Extension.ps1'

$doctor=& $command -Command doctor -RepoRoot $repo|ConvertFrom-Json -Depth 100
if([string]$doctor.status-cne'passed'-or@($doctor.commands).Count-ne10-or[bool]$doctor.player_mutation_authorized){throw '[mir4-t09-doctor]'}
$init=Join-Path $resultRoot 'init'
& $command -Command init -RepoRoot $repo -ExtensionId org.example.t09 -Template minimal -OutputRoot $init|Out-Null
$extension=Join-Path $init 'extension.json'
& $command -Command validate -RepoRoot $repo -ExtensionPath $extension|Out-Null
$lockResult=& $command -Command lock -RepoRoot $repo -ExtensionPath $extension -Target f210 -OutputRoot $init|ConvertFrom-Json
if([string]$lockResult.status-cne'review-required'){throw '[mir4-t09-f210-transport-truth]'}
$lockJson=Get-Content -Raw -LiteralPath (Join-Path $init 'extension.lock.json')
if(-not($lockJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/preview/mir4-extension-lock-v1.schema.json'))){throw '[mir4-t09-lock-schema]'}
& $command -Command explain -RepoRoot $repo -ExtensionPath $extension -Target f210|Out-Null
$testResult=& $command -Command test -RepoRoot $repo -ExtensionPath $extension -Target f210|ConvertFrom-Json
if([string]$testResult.result-cne'shadow-complete'-or[bool]$testResult.player_mutation_authorized-or[bool]$testResult.prototype_write_authorized){throw '[mir4-t09-shadow-plan]'}

$packageA=Join-Path $resultRoot 'package-a';$packageB=Join-Path $resultRoot 'package-b'
$packA=& $command -Command package -RepoRoot $repo -ExtensionPath $extension -OutputRoot $packageA|ConvertFrom-Json
$packB=& $command -Command package -RepoRoot $repo -ExtensionPath $extension -OutputRoot $packageB|ConvertFrom-Json
if([string]$packA.sha256-cne[string]$packB.sha256){throw '[mir4-t09-extension-archive-determinism]'}
Add-Type -AssemblyName System.IO.Compression
$archive=[IO.Compression.ZipFile]::OpenRead([string]$packA.path)
try{
  $entries=@($archive.Entries|ForEach-Object FullName|Sort-Object)
  if(($entries-join'|')-cne'extension.json|manifest.json'){throw '[mir4-t09-extension-archive-scope]'}
  foreach($entry in $archive.Entries){
    $reader=[IO.StreamReader]::new($entry.Open())
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
    if($text-match'callback|compiler_context|prototype_write_authorized\s*:\s*true|player_mutation_authorized\s*:\s*true'){throw '[mir4-t09-extension-archive-authority]'}
  }
}finally{$archive.Dispose()}

$ci=Join-Path $resultRoot 'ci'
& $command -Command ci-init -RepoRoot $repo -ExtensionPath extension.json -OutputRoot $ci|Out-Null
foreach($path in @('.github/workflows/mir4-extension.yml','tools/Invoke-MIR4ExtensionCI.ps1')){if(-not(Test-Path -LiteralPath (Join-Path $ci $path)-PathType Leaf)){throw "[mir4-t09-ci-file] $path"}}
$workflow=Get-Content -Raw -LiteralPath (Join-Path $ci '.github/workflows/mir4-extension.yml')
if($workflow-notmatch'actions/checkout@[0-9a-f]{40}'-or$workflow-match'curl|wget|Invoke-WebRequest'){throw '[mir4-t09-ci-offline-pin]'}

$minimalPath=Join-Path $repo 'sdk/preview/mir4/mep-v1/examples/positive/extension.json'
$unavailablePath=Join-Path $repo 'sdk/preview/mir4/mep-v1/examples/unavailable/extension.json'
$diffResult=& $command -Command diff -RepoRoot $repo -BasePath $minimalPath -CandidatePath $minimalPath -OutputRoot $resultRoot|ConvertFrom-Json
if([string]$diffResult.status-cne'identical'-or[int]$diffResult.change_count-ne0){throw '[mir4-t09-identical-diff]'}
$diffJson=Get-Content -Raw -LiteralPath (Join-Path $resultRoot 'extension.diff.json')
if(-not($diffJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/preview/mir4-extension-diff-v1.schema.json'))){throw '[mir4-t09-diff-schema]'}
$changed=& $command -Command diff -RepoRoot $repo -BasePath $minimalPath -CandidatePath $unavailablePath -OutputRoot $resultRoot|ConvertFrom-Json
if([string]$changed.status-cne'changed'-or[int]$changed.change_count-lt1){throw '[mir4-t09-changed-diff]'}

$unavailable=Get-Content -Raw -LiteralPath $unavailablePath|ConvertFrom-Json -Depth 100
$unavailableLock=New-MIR4ExtensionLockV1 -RepoRoot $repo -Envelope $unavailable -Target f012
if([string]$unavailableLock.status-cne'unavailable'){throw '[mir4-t09-explicit-unavailable]'}
$conflictA=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/mep-v1/examples/conflict/extension-a.json')|ConvertFrom-Json -Depth 100
$conflictB=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/mep-v1/examples/conflict/extension-b.json')|ConvertFrom-Json -Depth 100
Test-MIR4MepV1Envelope -Envelope $conflictA -RepoRoot $repo|Out-Null
Test-MIR4MepV1Envelope -Envelope $conflictB -RepoRoot $repo|Out-Null
try{Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($conflictA,$conflictB) -Target f210|Out-Null;throw '[mir4-t09-conflict-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-v1-conflict]')){throw}}
$migrationRoot=Join-Path $resultRoot 'migration'
& $command -Command migrate -RepoRoot $repo -ExtensionPath 'sdk/preview/mir4/mep-v1/examples/migration/extension-v0.json' -OutputRoot $migrationRoot|Out-Null
$migrated=Get-Content -Raw -LiteralPath (Join-Path $migrationRoot 'extension-v1.json')|ConvertFrom-Json -Depth 100
$expectedMigrated=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/mep-v1/examples/migration/extension-v1.json')|ConvertFrom-Json -Depth 100
if([string]$migrated.digest-cne[string]$expectedMigrated.digest){throw '[mir4-t09-migration-identity]'}

$assetsA=Join-Path $resultRoot 'assets-a';$assetsB=Join-Path $resultRoot 'assets-b'
New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot $assetsA|Out-Null
New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot $assetsB|Out-Null
$zipA=Join-Path $assetsA 'mir4-mep-v1-preview.zip';$zipB=Join-Path $assetsB 'mir4-mep-v1-preview.zip'
if((Get-FileHash -LiteralPath $zipA -Algorithm SHA256).Hash-cne(Get-FileHash -LiteralPath $zipB -Algorithm SHA256).Hash){throw '[mir4-t09-mep-archive-determinism]'}
$extract=Join-Path $resultRoot 'extracted'
Expand-Archive -LiteralPath $zipA -DestinationPath $extract
$portableRoot=Join-Path $extract 'mir4-mep-v1-preview'
$portable=& (Join-Path $portableRoot 'sdk/preview/mir4/mep-v1/conformance.ps1') -RepoRoot $portableRoot|ConvertFrom-Json
if([string]$portable.status-cne'passed'-or-not[bool]$portable.offline-or[bool]$portable.player_mutation_authorized){throw '[mir4-t09-clean-archive-conformance]'}
$portableExample=Join-Path $portableRoot 'sdk/preview/mir4/mep-v1/examples/positive/extension.json'
& (Join-Path $portableRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command doctor -RepoRoot $portableRoot -ExtensionPath $portableExample|Out-Null
& (Join-Path $portableRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command validate -RepoRoot $portableRoot -ExtensionPath $portableExample|Out-Null
& (Join-Path $portableRoot 'tools/commands/mir4/Invoke-MIR4Extension.ps1') -Command test -RepoRoot $portableRoot -ExtensionPath $portableExample -Target f210|Out-Null

$clock.Stop()
if($clock.Elapsed.TotalSeconds-ge300){throw "[mir4-t09-five-minute-path] $($clock.Elapsed.TotalSeconds)"}
if((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-cne$expectedPackage){throw '[mir4-t09-player-package-drift]'}
Write-Host "[ok] MIR 4 T09 extension DX passed in $([Math]::Round($clock.Elapsed.TotalSeconds,2)) seconds: templates, doctor/lock/diff/CI, examples, migration, deterministic archives, clean extraction, and no player authority."
