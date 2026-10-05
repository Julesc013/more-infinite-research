param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/tmp/t12-exact-processir',
  [string]$ReferenceRoot='sdk/preview/mir4/reference/t12',
  [string]$F210Engine='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$F200Engine='D:\Programs\Factorio\2.0\bin\x64\factorio.exe',
  [string[]]$ArchiveSearchRoots=@('C:\Projects\Factorio\testmods\2.1','C:\Projects\Factorio\testmods\2.0','C:\Downloads'),
  [string[]]$CaptureId=@(),
  [ValidateRange(1,4)][int]$Repetitions=2,
  [switch]$PublishReference,
  [ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB=2048,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB=240,
  [switch]$Check
)
& (Join-Path (Resolve-Path -LiteralPath $RepoRoot).Path 'tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1') @PSBoundParameters
