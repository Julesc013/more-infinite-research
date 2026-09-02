# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
function Assert-MIR4F210Channel([bool]$Condition, [string]$Code) {
  if (-not $Condition) { throw "[$Code]" }
}

$authorityPath = Join-Path $RepoRoot 'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json'
$schemaPath = Join-Path $RepoRoot 'spec/schemas/mir4-factorio-2.1-experimental-channel-v1.schema.json'
$authorityText = Get-Content -Raw -LiteralPath $authorityPath
Assert-MIR4F210Channel ($authorityText | Test-Json -SchemaFile $schemaPath) 'mir4-f210-channel-schema'
$authority = $authorityText | ConvertFrom-Json
Assert-MIR4F210Channel (-not [bool]$authority.selection.patch_pinned) 'mir4-f210-channel-not-pinned'
Assert-MIR4F210Channel (@($authority.change_review.required_tasks).Count -eq 12) 'mir4-f210-channel-review-task-count'
Assert-MIR4F210Channel (@($authority.current_review.review_tasks | Where-Object status -ne 'complete').Count -eq 0) 'mir4-f210-channel-current-review-complete'

. (Join-Path $RepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
$profile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/profiles/factorio-2.1.json') | ConvertFrom-Json
Assert-MIR4F210Channel ([string]$profile.qualification_factorio_version_mode -eq 'latest-installed-experimental') 'mir4-f210-channel-profile-mode'
Assert-MIR4F210Channel ([string]$profile.qualification_factorio_version_role -eq 'historical-active-campaign-compatibility-only') 'mir4-f210-channel-historical-field-role'
$resolved = Resolve-MIR4FactorioQualificationProfile -Profile $profile -RepoRoot $RepoRoot
Assert-MIR4F210Channel ([string]$resolved.qualification_factorio_version -eq [string]$authority.current_review.version) 'mir4-f210-channel-static-resolution'
Assert-MIR4F210Channel (Test-MIR4Factorio21SelectedVersion -Version '2.1.999' -Authority $authority) 'mir4-f210-channel-future-patch-admitted'
Assert-MIR4F210Channel (-not (Test-MIR4Factorio21SelectedVersion -Version '2.2.0' -Authority $authority)) 'mir4-f210-channel-other-line-rejected'

$temporaryChangelog = [IO.Path]::GetTempFileName()
try {
  [IO.File]::WriteAllText($temporaryChangelog, @"
Version: 2.1.18
  Modding:
    - Added Prototype::future_surface.
  Scripting:
    - Added LuaFuture::read.
Version: 2.1.17
  Bugfixes:
    - Historical boundary.
"@, [Text.UTF8Encoding]::new($false))
  $delta = @(Get-MIR4Factorio21ChangelogDelta -Path $temporaryChangelog -ReviewedVersion '2.1.17')
  Assert-MIR4F210Channel ($delta.Count -eq 2 -and @($delta | Where-Object opportunity_review).Count -eq 2) 'mir4-f210-channel-delta-opportunities'
} finally {
  Remove-Item -LiteralPath $temporaryChangelog -Force -ErrorAction SilentlyContinue
}

$workflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.github/workflows/assurance-scheduled.yml')
Assert-MIR4F210Channel ($workflow.Contains('factorio-2.1-channel inspect') -and $workflow.Contains('factorio-2.1-review.json')) 'mir4-f210-channel-scheduled-task-packet'
$programme = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json') | ConvertFrom-Json
Assert-MIR4F210Channel (@($programme.engine_channels | Where-Object target -eq 'f210').Count -eq 1) 'mir4-f210-channel-programme-obligation'
$runbook = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'RELEASE-RUNBOOK.md')
Assert-MIR4F210Channel ($runbook.Contains('latest official Steam experimental 2.1.x') -and $runbook.Contains('invalidates cross-patch evidence reuse')) 'mir4-f210-channel-runbook'

Write-Host '[ok] MIR 4 F210 moving experimental-channel policy'
