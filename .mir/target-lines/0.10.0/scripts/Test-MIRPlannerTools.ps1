param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
$root = Join-Path ([IO.Path]::GetTempPath()) ("mir-planner-tools-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $root | Out-Null

try {
  $beforeLog = Join-Path $root "before.log"
  $afterLog = Join-Path $root "after.log"
  @(
    '[more-infinite-research] audit kind=stream key=alpha status=generated',
    '[more-infinite-research] audit kind=decision key=alpha recipe=gear capability=recipe-productivity decision=attach',
    '[more-infinite-research] audit kind=loop_risk key=unsafe recipe=unsafe reason=recycling_loop'
  ) | Set-Content -LiteralPath $beforeLog -Encoding UTF8
  @(
    '[more-infinite-research] audit kind=stream key=alpha status=skipped',
    '[more-infinite-research] audit kind=decision key=beta recipe=circuit capability=recipe-productivity decision=attach'
  ) | Set-Content -LiteralPath $afterLog -Encoding UTF8

  $beforeSnapshot = Join-Path $root "before.json"
  $afterSnapshot = Join-Path $root "after.json"
  & (Join-Path $RepoRoot "scripts\Export-MIRPlannerSnapshot.ps1") -AuditLogPaths $beforeLog -TargetProfile "2.1" -SourceCommit ("a" * 40) -OutputPath $beforeSnapshot
  & (Join-Path $RepoRoot "scripts\Export-MIRPlannerSnapshot.ps1") -AuditLogPaths $afterLog -TargetProfile "2.0" -SourceCommit ("b" * 40) -OutputPath $afterSnapshot

  $before = Get-Content -Raw -LiteralPath $beforeSnapshot | ConvertFrom-Json
  if ($before.plan_rows.Count -ne 2 -or $before.coverage_rows.Count -ne 2 -or [string]::IsNullOrWhiteSpace($before.fingerprint_sha256)) {
    throw "Planner snapshot export did not classify and fingerprint rows."
  }

  $diffPath = Join-Path $root "diff.json"
  & (Join-Path $RepoRoot "scripts\Compare-MIRPlannerSnapshots.ps1") -Before $beforeSnapshot -After $afterSnapshot -OutputPath $diffPath -RequireDifferentTargets | Out-Null
  $diff = Get-Content -Raw -LiteralPath $diffPath | ConvertFrom-Json
  if ($diff.added_count -ne 1 -or $diff.removed_count -ne 1 -or $diff.changed_count -ne 1) {
    throw "Planner snapshot diff counts are incorrect."
  }

  $minimumPath = Join-Path $root "minimum.json"
  & (Join-Path $RepoRoot "scripts\Minimize-MIRPlannerSnapshot.ps1") -InputPath $beforeSnapshot -Subjects "gear" -OutputPath $minimumPath
  $minimum = Get-Content -Raw -LiteralPath $minimumPath | ConvertFrom-Json
  if ($minimum.row_count -ne 1 -or $minimum.rows[0].recipe -ne "gear") { throw "Planner snapshot minimizer selected the wrong rows." }

  $packPath = Join-Path $root "example-pack.json"
  & (Join-Path $RepoRoot "scripts\New-MIRCompatibilityPack.ps1") -Id "example-pack" -ModId "example-mod" -OutputPath $packPath
  $pack = Get-Content -Raw -LiteralPath $packPath | ConvertFrom-Json
  if ($pack.schema -ne 2 -or $pack.review.required -ne $true -or $pack.claim.public -ne $false) {
    throw "CompatibilityPack scaffold is not schema-2 review-required data."
  }
} finally {
  $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $resolvedRoot = [IO.Path]::GetFullPath($root)
  if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedRoot) -like "mir-planner-tools-*") {
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "[ok] MIR planner export, coverage, diff, target diff, minimizer, and pack scaffold tools passed."
