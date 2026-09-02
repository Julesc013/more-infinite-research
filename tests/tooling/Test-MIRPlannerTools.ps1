# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../.."))
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

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
  & (Join-Path $RepoRoot "tools\commands\planner\Export-MIRPlannerSnapshot.ps1") -AuditLogPaths $beforeLog -TargetProfile "2.1" -SourceCommit ("a" * 40) -OutputPath $beforeSnapshot
  & (Join-Path $RepoRoot "tools\commands\planner\Export-MIRPlannerSnapshot.ps1") -AuditLogPaths $afterLog -TargetProfile "2.0" -SourceCommit ("b" * 40) -OutputPath $afterSnapshot

  $before = Get-Content -Raw -LiteralPath $beforeSnapshot | ConvertFrom-Json
  if ($before.plan_rows.Count -ne 2 -or $before.coverage_rows.Count -ne 2 -or [string]::IsNullOrWhiteSpace($before.fingerprint_sha256)) {
    throw "Planner snapshot export did not classify and fingerprint rows."
  }

  $diffPath = Join-Path $root "diff.json"
  & (Join-Path $RepoRoot "tools\commands\planner\Compare-MIRPlannerSnapshots.ps1") -Before $beforeSnapshot -After $afterSnapshot -OutputPath $diffPath -RequireDifferentTargets | Out-Null
  $diff = Get-Content -Raw -LiteralPath $diffPath | ConvertFrom-Json
  if ($diff.added_count -ne 1 -or $diff.removed_count -ne 1 -or $diff.changed_count -ne 1) {
    throw "Planner snapshot diff counts are incorrect."
  }

  $minimumPath = Join-Path $root "minimum.json"
  & (Join-Path $RepoRoot "tools\commands\planner\Minimize-MIRPlannerSnapshot.ps1") -InputPath $beforeSnapshot -Subjects "gear" -OutputPath $minimumPath
  $minimum = Get-Content -Raw -LiteralPath $minimumPath | ConvertFrom-Json
  if ($minimum.row_count -ne 1 -or $minimum.rows[0].recipe -ne "gear") { throw "Planner snapshot minimizer selected the wrong rows." }

  $packPath = Join-Path $root "example-pack.json"
  & (Join-Path $RepoRoot "tools\commands\compatibility\New-MIRCompatibilityPack.ps1") -Id "example-pack" -ModId "example-mod" -OutputPath $packPath
  $pack = Get-Content -Raw -LiteralPath $packPath | ConvertFrom-Json
  if ($pack.schema -ne 2 -or $pack.review.required -ne $true -or $pack.claim.public -ne $false) {
    throw "CompatibilityPack scaffold is not schema-2 review-required data."
  }

  $beforeReportRoot = Join-Path $root "before-report"
  $afterReportRoot = Join-Path $root "after-report"
  New-Item -ItemType Directory -Path $beforeReportRoot, $afterReportRoot | Out-Null
  [ordered]@{ observations = @([ordered]@{ kind = "stream"; key = "alpha"; status = "generated" }) } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $beforeReportRoot "compat-observations.json") -Encoding UTF8
  [ordered]@{ observations = @([ordered]@{ kind = "stream"; key = "beta"; status = "generated" }) } |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $afterReportRoot "compat-observations.json") -Encoding UTF8
  $reportDiffPath = Join-Path $root "report-diff.json"
  & (Join-Path $RepoRoot "tools\commands\planner\Compare-MIRPlannerReports.ps1") -Before $beforeReportRoot -After $afterReportRoot -OutputPath $reportDiffPath | Out-Null
  $reportDiff = Get-Content -Raw -LiteralPath $reportDiffPath | ConvertFrom-Json
  $generatedSection = @($reportDiff.sections | Where-Object label -eq "generated streams")
  if ($generatedSection.Count -ne 1 -or $generatedSection[0].before -ne 1 -or $generatedSection[0].after -ne 1 -or
      $generatedSection[0].added -ne 1 -or $generatedSection[0].removed -ne 1) {
    throw "Planner report diff did not classify added and removed generated streams."
  }
} finally {
  $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $resolvedRoot = [IO.Path]::GetFullPath($root)
  if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedRoot) -like "mir-planner-tools-*") {
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "[ok] MIR planner export, coverage, diff, target diff, minimizer, and pack scaffold tools passed."
