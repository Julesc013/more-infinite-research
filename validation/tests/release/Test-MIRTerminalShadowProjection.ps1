param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$profilesPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-Shadow-ProjectionProfilesV1.json"
$matrixPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3-Terminal-Target-MatrixV1.json"
$admissionPath = Join-Path $RepoRoot ".mir/releases/terminal/MIR3TerminalProductAdmissionBundleV1.json"
$commandPath = Join-Path $RepoRoot "tools/commands/targets/Set-MIRTerminalShadowProjection.ps1"
$approvedDeltaFixturePath = Join-Path $RepoRoot "fixtures/export-approved-delta/data-final-fixes.lua"

$profiles = Get-Content -Raw -LiteralPath $profilesPath | ConvertFrom-Json -Depth 100
$matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json -Depth 100
$admission = Get-Content -Raw -LiteralPath $admissionPath | ConvertFrom-Json -Depth 100
$family = @("3.2.9", "2.5.9", "1.9.9", "1.8.9", "1.7.9", "1.6.9", "1.5.9", "1.4.9", "1.3.9")

if ([int]$profiles.schema -ne 1 -or [string]$profiles.kind -ne "MIR3TerminalShadowProjectionProfilesV1" -or
    (@($profiles.targets.release) -join "|") -ne ($family -join "|")) {
  throw "Terminal shadow projection profile family is incomplete or unordered."
}
if ([string]$profiles.portable_source.release -ne "3.2.9" -or
    (& git -C $RepoRoot rev-parse "$([string]$profiles.portable_source.authority_commit)^{commit}").Trim() -ne [string]$profiles.portable_source.authority_commit -or
    (& git -C $RepoRoot rev-parse "$([string]$profiles.portable_source.authority_commit)^{tree}").Trim() -ne [string]$profiles.portable_source.authority_tree) {
  throw "Terminal shadow portable source is not an immutable repository authority."
}
$approvedDeltaFixture = Get-Content -Raw -LiteralPath $approvedDeltaFixturePath
if ($approvedDeltaFixture -notmatch 'mods\["more-infinite-research"\]\s*==\s*"2\.5\.9"' -or
    $approvedDeltaFixture -notmatch 'terminal 2\.5\.9 route-policy projection') {
  throw "The approved-delta observer does not recognize the target-native 2.5.9 compiler-artifact boundary."
}

foreach ($row in @($profiles.targets)) {
  $matrixRow = @($matrix.targets | Where-Object release -eq ([string]$row.release))
  $admissionRow = @($admission.all_nine_dispositions | Where-Object release -eq ([string]$row.release))
  $record = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/releases/records/$([string]$row.release).json") | ConvertFrom-Json -Depth 100
  if ($matrixRow.Count -ne 1 -or $admissionRow.Count -ne 1 -or
      [string]$matrixRow[0].immutable_dot5_predecessor -ne [string]$row.baseline.release -or
      [string]$matrixRow[0].pre_dot5_public_predecessor -ne [string]$row.pre_dot5.release -or
      (@($matrixRow[0].upgrade_rows) -join "|") -ne (@($row.upgrade_rows) -join "|") -or
      [string]$record.release -ne [string]$row.release -or [string]$record.target -ne [string]$row.factorio_line -or
      [string]$record.source_release.release -ne [string]$row.baseline.release -or
      [string]$record.state -ne "planned" -or [string]$record.candidate_id -ne "not-assigned") {
    throw "Terminal target, admission, release record, and projection profile disagree for $($row.release)."
  }
  if ((@($admissionRow[0].findings) -join "|") -ne (@($row.product_findings) -join "|")) {
    throw "Terminal product finding disposition disagrees for $($row.release)."
  }
  foreach ($input in @($row.baseline, $row.pre_dot5)) {
    if ((& git -C $RepoRoot rev-parse "$([string]$input.tag)^{commit}").Trim() -ne [string]$input.commit) {
      throw "Terminal projection input tag moved: $($input.tag)"
    }
  }
  foreach ($overlay in @($row.assurance_overlays)) {
    if ((& git -C $RepoRoot rev-parse "$([string]$overlay.commit)^{commit}").Trim() -ne [string]$overlay.commit) {
      throw "Terminal assurance overlay commit is unavailable for $($row.release): $($overlay.id)"
    }
    foreach ($file in @($overlay.files)) {
      if ((& git -C $RepoRoot rev-parse "$([string]$overlay.commit):$([string]$file.path)").Trim() -ne [string]$file.blob) {
        throw "Terminal assurance overlay blob is unavailable for $($row.release): $($file.path)"
      }
    }
  }
}

$testRoot = Join-Path $RepoRoot ("build/tests/terminal-shadow-projection/" + [guid]::NewGuid().ToString("N"))
try {
  foreach ($row in @($profiles.targets)) {
    $targetRoot = Join-Path $testRoot ([string]$row.release)
    [void](New-Item -ItemType Directory -Force -Path $targetRoot)
    $infoText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):info.json") -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($infoText)) { throw "Unable to read exact predecessor metadata for $($row.release)." }
    [IO.File]::WriteAllText((Join-Path $targetRoot "info.json"), $infoText + "`n", [Text.UTF8Encoding]::new($false))

    $changelogText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):changelog.txt" 2>$null) -join "`n"
    [IO.File]::WriteAllText((Join-Path $targetRoot "changelog.txt"), $changelogText + "`n", [Text.UTF8Encoding]::new($false))

    if ([string]$row.release -eq "2.5.9") {
      [void](New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot ".mir"))
      $convergenceText = @(& git -C $RepoRoot show "$([string]$row.baseline.tag):.mir/convergence.yml") -join "`n"
      [IO.File]::WriteAllText((Join-Path $targetRoot ".mir/convergence.yml"), $convergenceText + "`n", [Text.UTF8Encoding]::new($false))
    }

    & $commandPath -Release ([string]$row.release) -TargetRoot $targetRoot -SourceRepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw "Terminal projection materialization failed for $($row.release)." }
    $firstConvergenceHash = (Get-FileHash -LiteralPath (Join-Path $targetRoot ".mir/convergence.yml") -Algorithm SHA256).Hash
    & $commandPath -Release ([string]$row.release) -TargetRoot $targetRoot -SourceRepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath (Join-Path $targetRoot ".mir/convergence.yml") -Algorithm SHA256).Hash -ne $firstConvergenceHash) {
      throw "Terminal projection materialization is not idempotent for $($row.release)."
    }
    & $commandPath -Release ([string]$row.release) -TargetRoot $targetRoot -SourceRepoRoot $RepoRoot -Check
    if ($LASTEXITCODE -ne 0) { throw "Terminal projection check failed for $($row.release)." }

    $info = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "info.json") | ConvertFrom-Json
    $record = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/records/$([string]$row.release).json") | ConvertFrom-Json -Depth 100
    $package = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/package-manifest.json") | ConvertFrom-Json -Depth 100
    $qualification = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/qualification-context.json") | ConvertFrom-Json -Depth 100
    $transition = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/releases/terminal/shadows/$([string]$row.release)/transition-plan.json") | ConvertFrom-Json -Depth 100
    $convergence = Get-Content -Raw -LiteralPath (Join-Path $targetRoot ".mir/convergence.yml")
    if ([string]$info.version -ne [string]$row.release -or [string]$info.factorio_version -ne [string]$row.factorio_line -or
        [string]$record.release -ne [string]$row.release -or [string]$package.release -ne [string]$row.release -or
        [string]$qualification.release -ne [string]$row.release -or [string]$transition.release -ne [string]$row.release -or
        $convergence -notmatch '(?m)^schema: 1$' -or
        $convergence -notmatch ('(?m)^  version: "' + [regex]::Escape([string]$row.release) + '"$') -or
        $convergence -notmatch ('(?m)^  baseline_commit: ' + [regex]::Escape([string]$row.baseline.commit) + '$')) {
      throw "Terminal projection did not align every release-local authority for $($row.release)."
    }
    foreach ($overlay in @($row.assurance_overlays)) {
      foreach ($file in @($overlay.files)) {
        $materializedBlob = (& git hash-object --no-filters -- (Join-Path $targetRoot ([string]$file.path))).Trim()
        $transitionOutput = @($row.performance_transition.output_blobs | Where-Object { [string]$_.path -eq [string]$file.path })
        $orderedOverlayOutputs = @(
          foreach ($orderedOverlay in @($row.assurance_overlays)) {
            foreach ($orderedFile in @($orderedOverlay.files)) {
              if ([string]$orderedFile.path -eq [string]$file.path) { $orderedFile }
            }
          }
        )
        $expectedBlob = if ($transitionOutput.Count -eq 1) {
          [string]$transitionOutput[0].blob
        } elseif ($orderedOverlayOutputs.Count -gt 0) {
          [string]$orderedOverlayOutputs[-1].blob
        } else {
          [string]$file.blob
        }
        if ($materializedBlob -ne $expectedBlob) { throw "Terminal projection did not materialize exact assurance overlay $($overlay.id): $($file.path)" }
      }
    }
    if ($null -ne $row.performance_transition) {
      foreach ($output in @($row.performance_transition.output_blobs)) {
        $materializedBlob = (& git hash-object --no-filters -- (Join-Path $targetRoot ([string]$output.path))).Trim()
        if ($materializedBlob -ne [string]$output.blob) { throw "Terminal projection did not materialize exact performance transition output $($row.performance_transition.id): $($output.path)" }
      }
    }
    if ([string]$row.release -eq "2.5.9") {
      $developmentAuthorities = @(
        $package.source.performance_transition.development_package,
        $qualification.performance_transition.development_package,
        $transition.immutable_inputs.performance_transition.development_package
      )
      foreach ($developmentAuthority in $developmentAuthorities) {
        if ([string]$developmentAuthority.version -ne "2.5.9" -or
            [long]$developmentAuthority.archive_bytes -ne 1057099 -or
            [int]$developmentAuthority.archive_entries -ne 301 -or
            [string]$developmentAuthority.archive_sha256 -ne "3EA775054F35BBBB6B2DE925E519CF7E06DD9B6C34D6DCC4A074191AF0E0A8B2" -or
            [string]$developmentAuthority.package_content_sha256 -ne "4D1FA997DB6F485ED9F6D295FDDF32F68A3B436BB17FDABFEE9CC4972860E59E") {
          throw "The 2.5.9 generated shadow authorities do not bind exact development bytes and entries."
        }
      }
      $targetCatalog = Get-Content -Raw -LiteralPath (Join-Path $targetRoot "validation/tests.yml") | ConvertFrom-Json -Depth 100
      $ecosystemTest = @($targetCatalog.tests | Where-Object { [string]$_.id -eq "runtime.ecosystem" })
      if ($ecosystemTest.Count -ne 1 -or
          [string]$ecosystemTest[0].command -notmatch '^\./scripts/mir\.ps1\s' -or
          [string]$ecosystemTest[0].command -notmatch '--mods\s+<mods>' -or
          @($ecosystemTest[0].inputs) -notcontains "mod-lock") {
        throw "The 2.5.9 assurance projection must forward the exact planned mod closure into its target-native ecosystem gate."
      }
      $performanceTest = @($targetCatalog.tests | Where-Object { [string]$_.id -eq "runtime.performance-regression" })
      if ($performanceTest.Count -ne 1 -or
          [string]$performanceTest[0].command -notmatch '-OutputPath\s+<test-output>(?:\s|$)' -or
          [string]$performanceTest[0].command -match '-OutputPath\s+\.mir/evidence/' -or
          @($performanceTest[0].inputs) -notcontains "mod-closure") {
        throw "The 2.5.9 assurance projection must keep performance evidence content-addressed and bind the exact mod closure."
      }
    }
  }

  $tamperedRoot = Join-Path $testRoot "2.5.9"
  $tamperedPath = Join-Path $tamperedRoot ".mir/convergence.yml"
  $tampered = (Get-Content -Raw -LiteralPath $tamperedPath).Replace('  version: "2.5.9"', '  version: "2.5.5"')
  [IO.File]::WriteAllText($tamperedPath, $tampered, [Text.UTF8Encoding]::new($false))
  $rejected = $false
  try { & $commandPath -Release "2.5.9" -TargetRoot $tamperedRoot -SourceRepoRoot $RepoRoot -Check } catch { $rejected = $true }
  if (-not $rejected) { throw "Terminal projection check accepted stale 2.5.5 convergence identity in a 2.5.9 shadow." }
} finally {
  if (Test-Path -LiteralPath $testRoot -PathType Container) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host "[ok] exact predecessor inputs and the portable terminal source produce consistent release authority for all nine shadows."
