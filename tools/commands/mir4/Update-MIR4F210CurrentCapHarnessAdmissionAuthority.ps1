[CmdletBinding()]
param([string]$RepoRoot='', [string]$RecordedAt='', [switch]$Check)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path}
. (Join-Path $RepoRoot 'tools/mir/application/release/F210QualificationPolicy.ps1')
$path=Join-Path $RepoRoot $script:MIR4F210CapHarnessV4Path
if(Test-Path -LiteralPath $path){
  $record=Get-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $RepoRoot
  if($RecordedAt -and ([DateTimeOffset]::Parse($RecordedAt).ToString('o')-cne[string]$record.recorded_at)){throw '[mir4-f210-cap-v4-existing-timestamp-immutable]'}
  return [pscustomobject]@{status='current';path=$script:MIR4F210CapHarnessV4Path;recorded_at=$record.recorded_at}
}
if($Check){throw '[mir4-f210-cap-v4-missing]'}
if(-not$RecordedAt){$RecordedAt=[DateTimeOffset]::UtcNow.ToString('o')}else{$RecordedAt=[DateTimeOffset]::Parse($RecordedAt).ToString('o')}
$record=New-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $RepoRoot -RecordedAt $RecordedAt
[IO.File]::WriteAllText($path,((ConvertTo-MIR4BootstrapCanonicalJson -Value $record)+"`n"),[Text.UTF8Encoding]::new($false))
$null=Get-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $RepoRoot
[pscustomobject]@{status='generated';path=$script:MIR4F210CapHarnessV4Path;recorded_at=$record.recorded_at}
