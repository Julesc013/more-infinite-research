# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$FactorioBin='C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe',
  [string]$CandidateZip='',
  [string]$BobModsDir='C:\Projects\Factorio\testmods\2.1',
  [string]$OutputRoot='build/tests/mir42-a06-bob-aluminium-final-state'
)
& (Join-Path $PSScriptRoot 'Test-MIRA06AluminiumFinalState.ps1') -Profile bob -RepoRoot $RepoRoot -FactorioBin $FactorioBin -CandidateZip $CandidateZip -ModsDir $BobModsDir -OutputRoot $OutputRoot