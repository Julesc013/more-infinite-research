# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$CombinedModsDir='C:\Projects\Factorio\testmods\2.1',
  [string]$OutputRoot='build/tests/mir42-a06-bob-angel-aluminium-final-state'
)
& (Join-Path $PSScriptRoot 'Test-MIRA06AluminiumFinalState.ps1') -Profile combined -RepoRoot $RepoRoot -FactorioBin $FactorioBin -CandidateZip $CandidateZip -ModsDir $CombinedModsDir -OutputRoot $OutputRoot