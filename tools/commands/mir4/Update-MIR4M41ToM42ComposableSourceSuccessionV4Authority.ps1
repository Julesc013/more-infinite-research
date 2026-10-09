# MIR4-CANONICAL-EXECUTABLE-COMMAND
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,[switch]$Check,[string]$RecordedAt='2026-09-16T12:30:00+10:00')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')
$path=Join-Path $repo 'assurance/repository/mir4-m41-to-m42-composable-source-succession-v4.json'
if($Check){
  Get-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo | Out-Null
}else{
  if(Test-Path -LiteralPath $path){throw '[mir4-m41-m42-succession-v4-authority-immutable-overwrite]'}
  $record=New-MIR4M41ToM42ComposableSourceSuccessionV4 -RepoRoot $repo -RecordedAt $RecordedAt
  [IO.File]::WriteAllText($path,(ConvertTo-MIR4BootstrapCanonicalJson -Value $record)+[char]10,[Text.UTF8Encoding]::new($false))
}
