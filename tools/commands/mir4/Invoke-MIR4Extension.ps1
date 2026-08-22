param(
  [Parameter(Mandatory)][ValidateSet('init','validate','explain','test','package','migrate')][string]$Command,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$ExtensionPath='',
  [string]$OutputRoot='build/mir4/extension-builder',
  [string]$ExtensionId='org.example.extension'
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-extension-output-boundary] $output"}
if($ExtensionId-notmatch'^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'){throw '[mir4-extension-id]'}

function Get-BuilderEnvelope {
  if([string]::IsNullOrWhiteSpace($ExtensionPath)){throw "[mir4-extension-path-required] $Command"}
  $path=if([IO.Path]::IsPathRooted($ExtensionPath)){$ExtensionPath}else{Join-Path $repo $ExtensionPath}
  return (Get-Content -Raw -LiteralPath $path|ConvertFrom-Json)
}

if($Command-eq'init'){
  $record=New-MIR4ReferenceExtensionV1 -RepoRoot $repo
  $record.extension_id=$ExtensionId;$record.namespace=$ExtensionId;$record.extension_version='0.1.0-preview'
  foreach($fragment in @($record.fragments)){$fragment.id=$fragment.id.Replace('org.more-infinite-research.reference',$ExtensionId)}
  $record.fragments[5].data.extension_id='org.more-infinite-research.platform';$record.digest='';$record.digest=Get-MIR4ModuleDigest $record
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  [IO.File]::WriteAllText((Join-Path $output 'extension.json'),(ConvertTo-MIR4ModuleCanonicalJson $record)+"`n",[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{status='initialized';path=(Join-Path $output 'extension.json');maturity='developer-preview'}|ConvertTo-Json
  exit
}

$envelope=Get-BuilderEnvelope
if($Command-eq'migrate'){
  $result=ConvertFrom-MIR4MepV0ToV1 -Envelope $envelope
  New-Item -ItemType Directory -Force -Path $output|Out-Null
  [IO.File]::WriteAllText((Join-Path $output 'extension-v1.json'),(ConvertTo-MIR4ModuleCanonicalJson $result)+"`n",[Text.UTF8Encoding]::new($false))
  [pscustomobject]@{status='migrated';path=(Join-Path $output 'extension-v1.json');execution_authorized=$false}|ConvertTo-Json
  exit
}
Test-MIR4MepV1Envelope -Envelope $envelope -RepoRoot $repo|Out-Null
if($Command-eq'validate'){
  [pscustomobject]@{status='valid';extension_id=[string]$envelope.extension_id;digest=[string]$envelope.digest}|ConvertTo-Json
  exit
}
$target=[string]@($envelope.targets|Sort-Object)[-1]
$closure=Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($envelope) -Target $target
if($Command-eq'explain'){
  $transport=@((Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo).transports|Where-Object target -eq $target)[0]
  [pscustomobject][ordered]@{status='explained';extension_id=[string]$envelope.extension_id;target=$target;closure=$closure;transport=$transport;writes_allowed=$false}|ConvertTo-Json -Depth 100
  exit
}
if($Command-eq'test'){
  $run=New-MIR4ShadowExtensionCompilationV1 -RepoRoot $repo -TargetId $target -Envelope $envelope
  if([string]$run.result-ne'shadow-complete'){throw '[mir4-extension-shadow-incomplete]'}
  [pscustomobject]@{status='passed';extension_id=[string]$envelope.extension_id;target=$target;run_digest=[string]$run.digest;mutation_authorized=$false}|ConvertTo-Json
  exit
}

New-Item -ItemType Directory -Force -Path $output|Out-Null
$zipPath=Join-Path $output (([string]$envelope.extension_id)+'_'+([string]$envelope.extension_version)+'.zip')
Add-Type -AssemblyName System.IO.Compression
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
  try{
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ModuleCanonicalJson $envelope)+"`n")
    $entry=$zip.CreateEntry('extension.json',[IO.Compression.CompressionLevel]::Optimal);$entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
    $entryStream=$entry.Open();try{$entryStream.Write($bytes,0,$bytes.Length)}finally{$entryStream.Dispose()}
    $manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4ExtensionDeveloperPackageV1';extension_id=[string]$envelope.extension_id;extension_digest=[string]$envelope.digest;maturity='developer-preview';player_package=$false;public_support_claim=$false;digest=''};Add-MIR4ModuleDigest $manifest|Out-Null
    $manifestBytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ModuleCanonicalJson $manifest)+"`n")
    $manifestEntry=$zip.CreateEntry('manifest.json',[IO.Compression.CompressionLevel]::Optimal);$manifestEntry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
    $manifestStream=$manifestEntry.Open();try{$manifestStream.Write($manifestBytes,0,$manifestBytes.Length)}finally{$manifestStream.Dispose()}
  }finally{$zip.Dispose()}
}finally{$stream.Dispose()}
[pscustomobject]@{status='packaged';path=$zipPath;bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-MIR4ModuleFileSha256 $zipPath);maturity='developer-preview'}|ConvertTo-Json
