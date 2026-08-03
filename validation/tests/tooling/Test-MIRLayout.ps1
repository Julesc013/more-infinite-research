$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
. (Join-Path $repo "tools/lib/workspace/RepoPaths.ps1")

$paths = Read-MIRRepoPathCatalog -RepoRoot $repo
$aliases = Read-MIRRepoAliasCatalog -RepoRoot $repo -PathCatalog $paths
if ($paths.paths.PSObject.Properties["releases.deltas"].Value -ne ".mir/releases/deltas") {
  throw "Release delta path ID changed."
}
if (@($aliases.aliases | Where-Object from -eq "approved-delta/").Count -ne 1) {
  throw "Historical approved-delta alias is missing."
}
$legacySchemaAlias = "verification/" + "schema/"
if (@($aliases.aliases | Where-Object {
  $_.from -eq $legacySchemaAlias -and $_.to -eq "spec.schemas" -and $_.mode -eq "read-only"
}).Count -ne 1) {
  throw "Historical verification schema alias is missing or writable."
}

$canonical = Resolve-MIRRepoPath -RepoRoot $repo -Id "releases.deltas"
if ($canonical.alias -or $canonical.relative_path -ne ".mir/releases/deltas") {
  throw "Canonical release delta resolution failed."
}
$legacy = Resolve-MIRRepoPath -RepoRoot $repo -Path "approved-delta/3.2.1-to-3.2.2.json"
if (-not $legacy.alias -or $legacy.mode -ne "historical-read-only" -or
    $legacy.relative_path -ne ".mir/releases/deltas/3.2.1-to-3.2.2.json") {
  throw "Historical release delta resolution failed."
}
$legacyCompatibilityRoot = "fixtures/" + "compat-matrix"
$legacyScenarioPath = "$legacyCompatibilityRoot/expected-scenarios.json"
$legacyScenario = Resolve-MIRRepoPath -RepoRoot $repo -Path $legacyScenarioPath
if (-not $legacyScenario.alias -or $legacyScenario.mode -ne "read-only" -or
    $legacyScenario.id -ne "validation.scenarios.runtime" -or
    $legacyScenario.relative_path -ne "validation/scenarios/runtime.json") {
  throw "Exact-file scenario alias resolution failed."
}
$legacyBaselineRoot = ".mir/control-plane/" + "baselines"
$legacyBaseline = Resolve-MIRRepoPath -RepoRoot $repo -Path "$legacyBaselineRoot/3.2.2-v5-replay.json"
if (-not $legacyBaseline.alias -or $legacyBaseline.relative_path -ne "validation/baselines/control/3.2.2-v5-replay.json") {
  throw "Reviewed baseline alias resolution failed."
}

foreach ($bad in @("../outside", "C:/absolute", 'docs\bad', "$legacyScenarioPath/child")) {
  $rejected = $false
  try { $null = Resolve-MIRRepoPath -RepoRoot $repo -Path $bad }
  catch { $rejected = $true }
  if (-not $rejected) { throw "Unsafe durable path was accepted: $bad" }
}

$manifest = New-MIRLayoutManifest -RepoRoot $repo
if ($manifest.summary.unclassified -ne 0 -or $manifest.summary.case_collisions -ne 0 -or $manifest.summary.links -ne 0) {
  throw "Layout manifest contains unsafe or unclassified paths: $($manifest.summary | ConvertTo-Json -Compress)"
}
if ($manifest.summary.legacy -eq 0) { throw "Migration baseline unexpectedly contains no legacy paths." }

$migrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIROutputRoots.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($migrationPreview.mode -ne "preview" -or $migrationPreview.changed -ne 0) {
  throw "Output-root migration is not idempotent: $($migrationPreview | ConvertTo-Json -Compress)"
}
$schemaMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRSchemaRoot.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($schemaMigrationPreview.mode -ne "preview" -or $schemaMigrationPreview.changed -ne 0) {
  throw "Schema-root migration is not idempotent: $($schemaMigrationPreview | ConvertTo-Json -Compress)"
}
$testMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRTestRoot.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($testMigrationPreview.mode -ne "preview" -or $testMigrationPreview.changed -ne 0 -or $testMigrationPreview.tests -ne 65) {
  throw "Test-root migration is incomplete or not idempotent: $($testMigrationPreview | ConvertTo-Json -Compress)"
}
$definitionMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRValidationDefinitions.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($definitionMigrationPreview.mode -ne "preview" -or $definitionMigrationPreview.changed -ne 0 -or
    $definitionMigrationPreview.definitions -ne 11) {
  throw "Validation-definition migration is incomplete or not idempotent: $($definitionMigrationPreview | ConvertTo-Json -Compress)"
}
foreach ($legacyDefinitionRoot in @($legacyCompatibilityRoot, $legacyBaselineRoot)) {
  $legacyFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo $legacyDefinitionRoot) -File -ErrorAction SilentlyContinue)
  if ($legacyFiles.Count -ne 0) { throw "Legacy definition files remain under $legacyDefinitionRoot." }
}
$legacyTestWrappers = @(Get-ChildItem -LiteralPath (Join-Path $repo "scripts") -Filter "Test-MIR*.ps1" -File)
$canonicalMovedTests = @(Get-ChildItem -LiteralPath (Join-Path $repo "validation/tests") -Filter "Test-MIR*.ps1" -Recurse -File |
  Where-Object Name -ne "Test-MIRLayout.ps1")
if ($legacyTestWrappers.Count -ne 65 -or $canonicalMovedTests.Count -ne 65) {
  throw "Canonical test/wrapper inventory drifted: canonical=$($canonicalMovedTests.Count), wrappers=$($legacyTestWrappers.Count)."
}
foreach ($wrapper in $legacyTestWrappers) {
  $text = Get-Content -Raw -LiteralPath $wrapper.FullName
  if ($text -notmatch "MIR-L4-LEGACY-TEST-WRAPPER" -or $text.Split([char]10).Count -gt 30) {
    throw "Legacy test entrypoint is not a thin forwarding wrapper: $($wrapper.Name)"
  }
}
$legacySchemaGlob = ("verification/" + "schema/**")
$legacySchemaFiles = @(& git -C $repo ls-files $legacySchemaGlob)
if ($LASTEXITCODE -ne 0 -or $legacySchemaFiles.Count -ne 0) {
  throw "Legacy physical verification schema files remain tracked."
}

foreach ($workflow in @(Get-ChildItem -LiteralPath (Join-Path $repo ".github/workflows") -File)) {
  $lines = @(Get-Content -LiteralPath $workflow.FullName)
  for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -notmatch "uses:\s*actions/upload-artifact@") { continue }
    $usesIndent = ([regex]::Match($lines[$index], "^\s*").Value).Length
    $stepStart = $index
    if ($lines[$index] -notmatch "^\s*-\s+uses:") {
      for ($candidate = $index - 1; $candidate -ge 0; $candidate--) {
        $match = [regex]::Match($lines[$candidate], "^(?<indent>\s*)-\s+")
        if ($match.Success -and $match.Groups["indent"].Value.Length -lt $usesIndent) {
          $stepStart = $candidate
          break
        }
      }
    }
    $stepIndent = ([regex]::Match($lines[$stepStart], "^\s*").Value).Length
    $stepEnd = $lines.Count
    for ($candidate = $stepStart + 1; $candidate -lt $lines.Count; $candidate++) {
      $match = [regex]::Match($lines[$candidate], "^(?<indent>\s*)-\s+")
      if ($match.Success -and $match.Groups["indent"].Value.Length -eq $stepIndent) {
        $stepEnd = $candidate
        break
      }
    }
    $block = $lines[$stepStart..($stepEnd - 1)] -join "`n"
    if ($block -match "\.work/" -and
        $block -notmatch "(?m)^\s+include-hidden-files:\s*true\s*$") {
      throw "Hidden output upload lacks include-hidden-files opt-in: $($workflow.Name):$($index + 1)"
    }
  }
}

function Invoke-MIRCliProbe {
  param([Parameter(Mandatory)][string]$Entrypoint, [Parameter(Mandatory)][string[]]$Arguments)
  $output = (& pwsh -NoProfile -File $Entrypoint @Arguments 2>&1 | Out-String).Replace("`r`n", "`n").Trim()
  return [pscustomobject]@{exit_code=$LASTEXITCODE;output=$output}
}

$legacySchemaTestPath = "scripts/" + "Test-MIRVerificationSchemas.ps1"
$legacyTest = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo $legacySchemaTestPath) -Arguments @("-RepoRoot", $repo)
$canonicalTest = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "validation/tests/tooling/Test-MIRVerificationSchemas.ps1") -Arguments @("-RepoRoot", $repo)
if ($legacyTest.exit_code -ne $canonicalTest.exit_code -or $legacyTest.output -cne $canonicalTest.output) {
  throw "Legacy/canonical test entrypoint parity failed."
}

foreach ($arguments in @(
  [string[]]@("help"),
  [string[]]@("path", "resolve", "releases.deltas"),
  [string[]]@("path", "resolve", "--path", "approved-delta/3.2.1-to-3.2.2.json")
)) {
  $legacyCli = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "scripts/mir.ps1") -Arguments $arguments
  $stableCli = Invoke-MIRCliProbe -Entrypoint (Join-Path $repo "tools/mir.ps1") -Arguments $arguments
  if ($legacyCli.exit_code -ne $stableCli.exit_code -or $legacyCli.output -cne $stableCli.output) {
    throw "Stable CLI parity failed for: $($arguments -join ' ')"
  }
}

Write-Host "[ok] repository paths, canonical tests, legacy wrappers, output roots, hidden artifact uploads, historical aliases, ownership inventory, layout safety, and CLI facade parity agree."
