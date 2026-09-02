# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/PatchLaneRehearsal.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4PatchRehearsalTestV1 {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}

$branchName = 'rehearsal/m40-01-synthetic-f210'
$branchBefore = @(& git -C $repo branch --list $branchName)
Assert-MIR4PatchRehearsalTestV1 ($branchBefore.Count -eq 0) 'mir4-patch-rehearsal-preexisting-branch'

$remoteRefs = @(
  'refs/remotes/origin/release/4.0',
  'refs/remotes/origin/main',
  'refs/remotes/origin/dev'
)
$beforeRefs = [ordered]@{}
foreach ($remoteRef in $remoteRefs) {
  $beforeRefs[$remoteRef] = [string](& git -C $repo rev-parse "$remoteRef^{commit}")
  Assert-MIR4PatchRehearsalTestV1 ($LASTEXITCODE -eq 0) 'mir4-patch-rehearsal-remote-ref'
}
$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo

$outputRoot = Join-Path $repo 'build/results/validation/mir4-patch-rehearsal'
$outputA = Join-Path $outputRoot 'rehearsal-a.json'
$outputB = Join-Path $outputRoot 'rehearsal-b.json'
& (Join-Path $repo 'tools/mir/cli/Invoke-MIR4PatchLaneRehearsal.ps1') -Command run -RepoRoot $repo -OutputPath $outputA | Out-Null
& (Join-Path $repo 'tools/mir/cli/Invoke-MIR4PatchLaneRehearsal.ps1') -Command run -RepoRoot $repo -OutputPath $outputB | Out-Null

$bytesA = [IO.File]::ReadAllBytes($outputA)
$bytesB = [IO.File]::ReadAllBytes($outputB)
Assert-MIR4PatchRehearsalTestV1 ([Linq.Enumerable]::SequenceEqual([byte[]]$bytesA, [byte[]]$bytesB)) 'mir4-patch-rehearsal-determinism'

$text = [Text.UTF8Encoding]::new($false, $true).GetString($bytesA)
$schemaPath = Join-Path $repo 'contracts/release/mir4-patch-lane-rehearsal-result-v1.schema.json'
Assert-MIR4PatchRehearsalTestV1 ($text | Test-Json -SchemaFile $schemaPath) 'mir4-patch-rehearsal-result-schema'
$record = $text | ConvertFrom-Json -Depth 100

$digest = Get-MIR4PatchRehearsalRecordDigestV1 -Record $record
Assert-MIR4PatchRehearsalTestV1 ([string]$record.record_digest -ceq $digest) 'mir4-patch-rehearsal-result-digest'
$receiptPath = Join-Path $repo 'releases/rehearsals/MIR4-M40-01-Patch-Lane-Rehearsal-2026-08-31.json'
$receiptText = [IO.File]::ReadAllText($receiptPath)
Assert-MIR4PatchRehearsalTestV1 ($receiptText | Test-Json -SchemaFile $schemaPath) 'mir4-patch-rehearsal-receipt-schema'
$receipt = $receiptText | ConvertFrom-Json -Depth 100
Assert-MIR4PatchRehearsalTestV1 ((ConvertTo-MIR4CanonicalJsonV1 -Value $receipt) -ceq (ConvertTo-MIR4CanonicalJsonV1 -Value $record)) 'mir4-patch-rehearsal-receipt-drift'
Assert-MIR4PatchRehearsalTestV1 ((@($record.target_matrix | Where-Object disposition -eq 'affected').target -join '|') -ceq 'F210') 'mir4-patch-rehearsal-affected-target'
Assert-MIR4PatchRehearsalTestV1 ((@($record.target_matrix | Where-Object disposition -eq 'unchanged').target -join '|') -ceq 'F200|F110|F100') 'mir4-patch-rehearsal-unchanged-targets'
Assert-MIR4PatchRehearsalTestV1 (-not [bool]$record.package_plan.manufacture_unchanged_targets) 'mir4-patch-rehearsal-no-unchanged-package'
Assert-MIR4PatchRehearsalTestV1 ([bool]$record.disposable_branch.created -and [bool]$record.disposable_branch.removed) 'mir4-patch-rehearsal-disposable-branch'

foreach ($property in @('merge', 'tag', 'version_allocation', 'sign', 'seal', 'publish', 'remote_branch_write')) {
  Assert-MIR4PatchRehearsalTestV1 (-not [bool]$record.firewall.$property) "mir4-patch-rehearsal-firewall-$property"
}

$tampered = $text | ConvertFrom-Json -Depth 100
$tampered.firewall.publish = $true
$tamperedText = $tampered | ConvertTo-Json -Depth 100
Assert-MIR4PatchRehearsalTestV1 (-not ($tamperedText | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) 'mir4-patch-rehearsal-publication-tamper'

& (Join-Path $repo 'tools/mir/cli/Invoke-MIR4PatchLaneRehearsal.ps1') -Command check -RepoRoot $repo -OutputPath $outputA | Out-Null

$packageAfter = Get-MIRPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4PatchRehearsalTestV1 ($packageAfter -ceq $packageBefore) 'mir4-patch-rehearsal-package-delta'
Assert-MIR4PatchRehearsalTestV1 ([string]$record.package_source_sha256 -ceq $packageAfter) 'mir4-patch-rehearsal-package-authority'
Assert-MIR4PatchRehearsalTestV1 (@(& git -C $repo branch --list $branchName).Count -eq 0) 'mir4-patch-rehearsal-branch-leak'

foreach ($remoteRef in $remoteRefs) {
  $after = [string](& git -C $repo rev-parse "$remoteRef^{commit}")
  Assert-MIR4PatchRehearsalTestV1 ($after -ceq [string]$beforeRefs[$remoteRef]) 'mir4-patch-rehearsal-remote-mutation'
}

Write-Host '[ok] MIR 4 M40-01 unpublished patch-lane rehearsal passed'
