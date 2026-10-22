# Private same-version replay capture. Published archive custody is restored
# even when native admission or data loading fails. This is not a release tool.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$PublishedArchive,
  [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$PublishedSha256,
  [Parameter(Mandatory)][string]$ReplayArchive,
  [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ReplaySha256,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidateRange(128,8192)][int]$ExpectedPeakMemoryMiB=384
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Assert-Replay([bool]$Condition,[string]$Message){if(-not $Condition){throw "[mir5-replay-capture] $Message"}}
function Get-ReplaySha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$library=(Resolve-Path -LiteralPath $ArchiveLibrary).Path
$published=(Resolve-Path -LiteralPath $PublishedArchive).Path
$replay=(Resolve-Path -LiteralPath $ReplayArchive).Path
$destination=Join-Path $library ([IO.Path]::GetFileName($published))
Assert-Replay ($published -cne $destination -and $replay -cne $destination) 'custody sources must be outside the live library entry'
Assert-Replay ([IO.Path]::GetFileName($replay) -ceq [IO.Path]::GetFileName($published)) 'replay must retain published filename'
Assert-Replay ((Get-ReplaySha $published) -ceq $PublishedSha256.ToUpperInvariant()) 'published source hash differs'
Assert-Replay ((Get-ReplaySha $replay) -ceq $ReplaySha256.ToUpperInvariant()) 'replay source hash differs'
Assert-Replay ((Get-ReplaySha $destination) -ceq $PublishedSha256.ToUpperInvariant()) 'library is not the accepted published input'
Assert-Replay (-not(Test-Path -LiteralPath $OutputRoot)) 'preserve existing output'
& (Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -MaxScanSeconds 1 -MaxEntriesPerRoot 100 | Out-Host

function Set-ReplayLibraryArchive([string]$Source,[string]$ExpectedCurrent,[string]$ExpectedReplacement){
  Assert-Replay (@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count -eq 0) 'Factorio must be idle before archive replacement'
  $lock=[IO.File]::Open((Join-Path $library '.mir-library.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    Assert-Replay (-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'active selection prevents archive replacement'
    Assert-Replay ((Get-ReplaySha $destination) -ceq $ExpectedCurrent.ToUpperInvariant()) 'live archive changed; preserve it for review'
    Assert-Replay ((Get-ReplaySha $Source) -ceq $ExpectedReplacement.ToUpperInvariant()) 'custody source changed'
    [IO.File]::Copy($Source,$destination,$true)
    Assert-Replay ((Get-ReplaySha $destination) -ceq $ExpectedReplacement.ToUpperInvariant()) 'replacement hash differs'
  }finally{$lock.Dispose()}
}
$swapped=$false
try{
  Set-ReplayLibraryArchive $replay $PublishedSha256 $ReplaySha256
  $swapped=$true
  & (Join-Path $PSScriptRoot 'Invoke-PrototypeCapture.ps1') -ArchiveLibrary $library -FactorioBin $FactorioBin -ProfilePath $ProfilePath -OutputRoot $OutputRoot -MIRArchive $destination -ExpectedMIRArchiveSha256 $ReplaySha256 -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB 512 -AdmissionWaitSeconds 60
}finally{
  if($swapped){Set-ReplayLibraryArchive $published $ReplaySha256 $PublishedSha256}
  Assert-Replay ((Get-ReplaySha $published) -ceq $PublishedSha256.ToUpperInvariant()) 'published custody changed'
  Assert-Replay ((Get-ReplaySha $replay) -ceq $ReplaySha256.ToUpperInvariant()) 'replay custody changed'
  Assert-Replay ((Get-ReplaySha $destination) -ceq $PublishedSha256.ToUpperInvariant()) 'published library restoration failed'
}
