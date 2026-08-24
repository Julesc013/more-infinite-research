param(
  [Parameter(Mandatory)][ValidateSet('release-doctor','rulesets-audit','playtest-prepare','playtest-capture','playtest-finalize')][string]$Command,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
  [switch]$Json,
  [switch]$DryRun,
  [switch]$Explain,
  [string]$OutputPath = '',
  [ValidateSet('F210','F200')][string]$Target = 'F210',
  [string]$CandidatePath = '',
  [string]$PredecessorPath = '',
  [string]$FactorioBin = '',
  [string]$SettingsPath = '',
  [string]$SavePath = '',
  [string]$SessionOutputRoot = '',
  [string]$SessionRoot = '',
  [string[]]$CapturePath = @(),
  [string]$ObservationsPath = '',
  [ValidateSet('','ACCEPTED','CHANGES-REQUESTED','REJECTED')][string]$Decision = '',
  [string]$Reviewer = '',
  [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$result = switch ($Command) {
  'release-doctor' { Get-MIR4ReleaseDoctor -RepoRoot $RepoRoot -Explain:$Explain }
  'rulesets-audit' { Test-MIR4RulesetSnapshot -RepoRoot $RepoRoot }
  'playtest-prepare' {
    $parameters = @{
      RepoRoot=$RepoRoot;Target=$Target;CandidatePath=$CandidatePath;PredecessorPath=$PredecessorPath
      FactorioBin=$FactorioBin;SettingsPath=$SettingsPath;SavePath=$SavePath
      OutputRoot=$SessionOutputRoot;DryRun=$DryRun
    }
    New-MIR4PlaytestSession @parameters
  }
  'playtest-capture' {
    if ([string]::IsNullOrWhiteSpace($SessionRoot)) { throw 'playtest capture requires --session.' }
    Capture-MIR4PlaytestSession -RepoRoot $RepoRoot -SessionRoot $SessionRoot -CapturePath $CapturePath -ObservationsPath $ObservationsPath -DryRun:$DryRun
  }
  'playtest-finalize' {
    if ([string]::IsNullOrWhiteSpace($SessionRoot) -or [string]::IsNullOrWhiteSpace($Decision) -or [string]::IsNullOrWhiteSpace($Reviewer)) {
      throw 'playtest finalize requires --session, --decision, and --reviewer.'
    }
    Complete-MIR4PlaytestSession -RepoRoot $RepoRoot -SessionRoot $SessionRoot -Decision $Decision -Reviewer $Reviewer -Notes $Notes -DryRun:$DryRun
  }
}

$serialized = $result | ConvertTo-Json -Depth 100
if (-not [string]::IsNullOrWhiteSpace($OutputPath) -and -not $DryRun) {
  $full = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputPath)) }
  New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
  [IO.File]::WriteAllText($full,$serialized+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
if ($Json -or $Command -ne 'release-doctor') {
  $serialized
} else {
  Write-Host ("MIR4 pre-freeze: {0}; release: {1}" -f $result.prefreeze_status,$result.release_status)
  foreach ($check in @($result.checks)) { Write-Host ("[{0}] {1}: {2}" -f $check.status,$check.id,$check.detail) }
}
if ($Command -eq 'release-doctor' -and [int]$result.counts.automated_failed -gt 0) { exit 2 }
