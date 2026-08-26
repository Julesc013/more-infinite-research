param(
  [Parameter(Mandatory)][ValidateSet('init','validate','explain','test','package','migrate','doctor','lock','diff','ci-init','discover')][string]$Command,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$ExtensionPath='',
  [string]$OutputRoot='build/mir4/extension-builder',
  [string]$ExtensionId='org.example.extension',
  [ValidateSet('minimal','all-fragments','unavailable')][string]$Template='minimal',
  [string]$BasePath='',
  [string]$CandidatePath='',
  [string]$DiscoveryPath='',
  [ValidatePattern('^f[0-9]{3}$')][string]$Target=''
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/MepDiscovery.ps1')
$output=if([IO.Path]::IsPathRooted($OutputRoot)){[IO.Path]::GetFullPath($OutputRoot)}else{[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))}
if($null-eq[IO.Directory]::GetParent($output)){throw "[mir4-extension-output-root] $output"}
if($ExtensionId-notmatch'^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'){throw '[mir4-extension-id]'}

function Read-BuilderEnvelope {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Role)
  if([string]::IsNullOrWhiteSpace($Path)){throw "[mir4-extension-path-required] $Role"}
  $resolved=if([IO.Path]::IsPathRooted($Path)){$Path}else{Join-Path $repo $Path}
  if(-not(Test-Path -LiteralPath $resolved -PathType Leaf)){throw "[mir4-extension-path-missing] $($Role):$resolved"}
  return (Get-Content -Raw -LiteralPath $resolved|ConvertFrom-Json -Depth 100)
}

function Write-BuilderJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent)|Out-Null
  [IO.File]::WriteAllText($Path,(ConvertTo-MIR4ModuleCanonicalJson $Value)+[char]10,[Text.UTF8Encoding]::new($false))
}

if($Command-eq'init'){
  $record=New-MIR4ExtensionTemplateV1 -RepoRoot $repo -ExtensionId $ExtensionId -Template $Template
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  $path=Join-Path $output 'extension.json'
  Write-BuilderJson -Path $path -Value $record
  [pscustomobject]@{status='initialized';path=$path;template=$Template;maturity='developer-preview';player_mutation_authorized=$false}|ConvertTo-Json
  return
}

if($Command-eq'doctor'){
  $envelope=if([string]::IsNullOrWhiteSpace($ExtensionPath)){$null}else{Read-BuilderEnvelope -Path $ExtensionPath -Role $Command}
  $result=Get-MIR4ExtensionDoctorV1 -RepoRoot $repo -Envelope $envelope
  $result|ConvertTo-Json -Depth 100
  if([string]$result.status-cne'passed'){throw '[mir4-extension-doctor-failed]'}
  return
}

if($Command-eq'diff'){
  $base=Read-BuilderEnvelope -Path $BasePath -Role 'diff-base'
  $candidate=Read-BuilderEnvelope -Path $CandidatePath -Role 'diff-candidate'
  $result=New-MIR4ExtensionDiffV1 -RepoRoot $repo -Base $base -Candidate $candidate
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  $path=Join-Path $output 'extension.diff.json'
  Write-BuilderJson -Path $path -Value $result
  [pscustomobject]@{status=[string]$result.status;path=$path;change_count=[int]$result.change_count;digest=[string]$result.digest;player_mutation_authorized=$false}|ConvertTo-Json
  return
}

if($Command-eq'ci-init'){
  $result=Write-MIR4ExtensionCiScaffoldV1 -OutputRoot $output -ExtensionPath $(if([string]::IsNullOrWhiteSpace($ExtensionPath)){'extension.json'}else{$ExtensionPath})
  $result|ConvertTo-Json -Depth 100
  return
}

if($Command-eq'discover'){
  $snapshot=Read-BuilderEnvelope -Path $DiscoveryPath -Role 'discover-snapshot'
  $result=New-MIR4F210MepDiscoveryV1 -RepoRoot $repo -Snapshot $snapshot
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  $path=Join-Path $output 'f210-mep-discovery.json'
  Write-BuilderJson -Path $path -Value $result
  [pscustomobject]@{
    status=[string]$result.result;path=$path;matching_records=[int]$result.counts.matching_records
    accepted_records=[int]$result.counts.accepted_records;quarantined_records=[int]$result.counts.quarantined_records
    digest=[string]$result.digest;player_mutation_authorized=$false;prototype_write_authorized=$false
  }|ConvertTo-Json
  return
}

$envelope=Read-BuilderEnvelope -Path $ExtensionPath -Role $Command
if($Command-eq'migrate'){
  $result=ConvertFrom-MIR4MepV0ToV1 -Envelope $envelope
  Test-MIR4MepV1Envelope -Envelope $result -RepoRoot $repo|Out-Null
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  $path=Join-Path $output 'extension-v1.json'
  Write-BuilderJson -Path $path -Value $result
  [pscustomobject]@{status='migrated';path=$path;execution_authorized=$false;player_mutation_authorized=$false}|ConvertTo-Json
  return
}

Test-MIR4MepV1Envelope -Envelope $envelope -RepoRoot $repo|Out-Null
if($Command-eq'validate'){
  [pscustomobject]@{status='valid';extension_id=[string]$envelope.extension_id;digest=[string]$envelope.digest;player_mutation_authorized=$false}|ConvertTo-Json
  return
}
if($Command-eq'lock'){
  $result=New-MIR4ExtensionLockV1 -RepoRoot $repo -Envelope $envelope -Target $Target
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  $path=Join-Path $output 'extension.lock.json'
  Write-BuilderJson -Path $path -Value $result
  [pscustomobject]@{status=[string]$result.status;path=$path;target=[string]$result.target;digest=[string]$result.digest;player_mutation_authorized=$false}|ConvertTo-Json
  return
}
if($Command-eq'explain'){
  $plan=New-MIR4ExtensionShadowPlanV1 -RepoRoot $repo -Envelope $envelope -Target $Target
  [pscustomobject][ordered]@{status='explained';extension_id=[string]$envelope.extension_id;target=[string]$plan.target;plan=$plan;writes_allowed=$false;player_mutation_authorized=$false}|ConvertTo-Json -Depth 100
  return
}
if($Command-eq'test'){
  $run=New-MIR4ExtensionShadowPlanV1 -RepoRoot $repo -Envelope $envelope -Target $Target
  if([string]$run.result-notin@('shadow-complete','unavailable')){throw '[mir4-extension-shadow-incomplete]'}
  [pscustomobject]@{status='passed';extension_id=[string]$envelope.extension_id;target=[string]$run.target;result=[string]$run.result;run_digest=[string]$run.digest;player_mutation_authorized=$false;prototype_write_authorized=$false}|ConvertTo-Json
  return
}

New-Item -ItemType Directory -Force -Path $output|Out-Null
$zipPath=Join-Path $output (([string]$envelope.extension_id)+'_'+([string]$envelope.extension_version)+'.zip')
Add-Type -AssemblyName System.IO.Compression
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ModuleCanonicalJson $envelope)+[char]10)
    $entry=$zip.CreateEntry('extension.json',[IO.Compression.CompressionLevel]::Optimal);$entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
    $entryStream=$entry.Open();try{$entryStream.Write($bytes,0,$bytes.Length)}finally{$entryStream.Dispose()}
    $manifest=[pscustomobject][ordered]@{
      schema=1;kind='MIR4ExtensionDeveloperPackageV1';extension_id=[string]$envelope.extension_id;extension_digest=[string]$envelope.digest
      maturity='developer-preview';player_package=$false;player_mutation_authorized=$false;prototype_write_authorized=$false
      public_support_claim=$false;release_authority=$false;digest=''
    }
    Add-MIR4ModuleDigest $manifest|Out-Null
    $manifestBytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ModuleCanonicalJson $manifest)+[char]10)
    $manifestEntry=$zip.CreateEntry('manifest.json',[IO.Compression.CompressionLevel]::Optimal);$manifestEntry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
    $manifestStream=$manifestEntry.Open();try{$manifestStream.Write($manifestBytes,0,$manifestBytes.Length)}finally{$manifestStream.Dispose()}
  }finally{$zip.Dispose()}
}finally{$stream.Dispose()}
[pscustomobject]@{status='packaged';path=$zipPath;bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-MIR4ModuleFileSha256 $zipPath);maturity='developer-preview';player_mutation_authorized=$false}|ConvertTo-Json
