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
if (@($aliases.aliases | Where-Object {
  $_.from -eq ("scripts/" + "MIRCli/") -and $_.to -eq "tools.lib.cli" -and $_.mode -eq "read-only"
}).Count -ne 1) {
  throw "Historical CLI-support alias is missing or writable."
}
if (@($aliases.aliases | Where-Object {
  $_.from -eq ("scripts/" + "mir.ps1") -and $_.to -eq "tools.cli" -and $_.mode -eq "read-only"
}).Count -ne 1) {
  throw "Historical CLI-facade alias is missing or writable."
}
foreach ($packageAlias in @(
  @{from=("scripts/" + "Build-MIRPackage.ps1");to="tools.commands.package.build"},
  @{from=("scripts/" + "Measure-MIRPackageComposition.ps1");to="tools.commands.package.composition"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $packageAlias.from -and $_.to -eq $packageAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical package-command alias is missing or writable: $($packageAlias.from)" }
}
foreach ($workspaceAlias in @(
  @{from=("scripts/" + "Get-MIRLegacyInventory.ps1");to="tools.commands.workspace.inventory"},
  @{from=("scripts/" + "Remove-MIRStaleArtifacts.ps1");to="tools.commands.workspace.cleanup"}
)) {
  if (@($aliases.aliases | Where-Object {
    $_.from -eq $workspaceAlias.from -and $_.to -eq $workspaceAlias.to -and $_.mode -eq "read-only"
  }).Count -ne 1) { throw "Historical workspace-command alias is missing or writable: $($workspaceAlias.from)" }
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
$toolLibraryMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRToolLibraries.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($toolLibraryMigrationPreview.mode -ne "preview" -or $toolLibraryMigrationPreview.changed -ne 0 -or
    $toolLibraryMigrationPreview.libraries -ne 7) {
  throw "Tool-library migration is incomplete or not idempotent: $($toolLibraryMigrationPreview | ConvertTo-Json -Compress)"
}
$cliFacadeMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRCliFacade.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($cliFacadeMigrationPreview.mode -ne "preview" -or $cliFacadeMigrationPreview.changed -ne 0 -or
    $cliFacadeMigrationPreview.canonical -ne "tools/mir.ps1" -or $cliFacadeMigrationPreview.legacy -ne "scripts/mir.ps1") {
  throw "CLI-facade migration is incomplete or not idempotent: $($cliFacadeMigrationPreview | ConvertTo-Json -Compress)"
}
$packageCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRPackageCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($packageCommandMigrationPreview.mode -ne "preview" -or $packageCommandMigrationPreview.changed -ne 0 -or
    $packageCommandMigrationPreview.commands -ne 2) {
  throw "Package-command migration is incomplete or not idempotent: $($packageCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$workspaceCommandMigrationPreview = & pwsh -NoProfile -File (Join-Path $repo "tools/maintenance/Move-MIRWorkspaceCommands.ps1") -RepoRoot $repo | ConvertFrom-Json
if ($workspaceCommandMigrationPreview.mode -ne "preview" -or $workspaceCommandMigrationPreview.changed -ne 0 -or
    $workspaceCommandMigrationPreview.commands -ne 2) {
  throw "Workspace-command migration is incomplete or not idempotent: $($workspaceCommandMigrationPreview | ConvertTo-Json -Compress)"
}
$legacyPackageCommands = @(
  (Join-Path $repo "scripts/Build-MIRPackage.ps1"),
  (Join-Path $repo "scripts/Measure-MIRPackageComposition.ps1")
)
foreach ($wrapperPath in $legacyPackageCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 30) {
    throw "Legacy package command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyWorkspaceCommands = @(
  (Join-Path $repo "scripts/Get-MIRLegacyInventory.ps1"),
  (Join-Path $repo "scripts/Remove-MIRStaleArtifacts.ps1")
)
foreach ($wrapperPath in $legacyWorkspaceCommands) {
  $wrapperText = Get-Content -Raw -LiteralPath $wrapperPath
  if ($wrapperText -notmatch "MIR-L5-LEGACY-COMMAND-WRAPPER" -or $wrapperText.Split([char]10).Count -gt 35) {
    throw "Legacy workspace command is not a thin parameter-compatible wrapper: $wrapperPath"
  }
}
$legacyLibraryNames = @(
  ("MIR" + "Assurance"),
  ("MIR" + "Cli"),
  ("MIR" + "CompatAudit"),
  ("MIR" + "ControlPlane"),
  "localization",
  "Museum",
  "validation"
)
$legacyLibraryWrappers = @($legacyLibraryNames | ForEach-Object {
  Get-ChildItem -LiteralPath (Join-Path $repo "scripts/$_") -File
})
$canonicalLibraries = @(Get-ChildItem -LiteralPath (Join-Path $repo "tools/lib") -Recurse -File |
  Where-Object { $_.Extension -in @(".ps1", ".psm1") -and $_.FullName -notlike "*tools\lib\workspace\*" })
if ($legacyLibraryWrappers.Count -ne 42 -or $canonicalLibraries.Count -ne 42) {
  throw "Canonical tool-library/wrapper inventory drifted: canonical=$($canonicalLibraries.Count), wrappers=$($legacyLibraryWrappers.Count)."
}
foreach ($wrapper in $legacyLibraryWrappers) {
  $text = Get-Content -Raw -LiteralPath $wrapper.FullName
  if ($text -notmatch "MIR-L5-LEGACY-LIBRARY-WRAPPER" -or $text.Split([char]10).Count -gt 4) {
    throw "Legacy library entrypoint is not a thin dot-source wrapper: $($wrapper.FullName)"
  }
}

function Invoke-MIRInlineProbe {
  param([Parameter(Mandatory)][string]$Command)
  $output = (& pwsh -NoProfile -Command $Command 2>&1 | Out-String).Replace("`r`n", "`n").Trim()
  return [pscustomobject]@{exit_code=$LASTEXITCODE;output=$output}
}

$legacyControlPath = Join-Path $repo ("scripts/" + ("MIR" + "ControlPlane") + "/Core.ps1")
$canonicalControlPath = Join-Path $repo "tools/lib/control/Core.ps1"
$legacyControlProbe = Invoke-MIRInlineProbe -Command ". '$($legacyControlPath.Replace("'", "''"))'; Get-MIRCPRepoRoot"
$canonicalControlProbe = Invoke-MIRInlineProbe -Command ". '$($canonicalControlPath.Replace("'", "''"))'; Get-MIRCPRepoRoot"
if ($legacyControlProbe.exit_code -ne 0 -or $legacyControlProbe.output -cne $canonicalControlProbe.output) {
  throw "Legacy/canonical dot-source library parity failed."
}
$legacyCliSupportPath = Join-Path $repo ("scripts/" + "MIRCli/PathResolver.ps1")
$canonicalCliSupportPath = Join-Path $repo "tools/lib/cli/PathResolver.ps1"
$legacyCliSupportProbe = Invoke-MIRInlineProbe -Command ". '$($legacyCliSupportPath.Replace("'", "''"))'; Get-MIRRepoRoot -StartPath '$($repo.Replace("'", "''"))'"
$canonicalCliSupportProbe = Invoke-MIRInlineProbe -Command ". '$($canonicalCliSupportPath.Replace("'", "''"))'; Get-MIRRepoRoot -StartPath '$($repo.Replace("'", "''"))'"
if ($legacyCliSupportProbe.exit_code -ne 0 -or $legacyCliSupportProbe.output -cne $canonicalCliSupportProbe.output) {
  throw "Legacy/canonical CLI-support library parity failed."
}

$legacyMuseumPath = Join-Path $repo ("scripts/" + "Museum/MuseumCompiler.psm1")
$canonicalMuseumPath = Join-Path $repo "tools/lib/museum/MuseumCompiler.psm1"
$legacyMuseumProbe = Invoke-MIRInlineProbe -Command "Import-Module '$($legacyMuseumPath.Replace("'", "''"))' -Force; Get-MIRTextSha256 -Text 'layout-parity'"
$canonicalMuseumProbe = Invoke-MIRInlineProbe -Command "Import-Module '$($canonicalMuseumPath.Replace("'", "''"))' -Force; Get-MIRTextSha256 -Text 'layout-parity'"
if ($legacyMuseumProbe.exit_code -ne 0 -or $legacyMuseumProbe.output -cne $canonicalMuseumProbe.output) {
  throw "Legacy/canonical module import parity failed."
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
$legacyCliText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts/mir.ps1")
$publicCliText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools/mir.ps1")
if ($legacyCliText -notmatch "MIR-L5-LEGACY-CLI-WRAPPER" -or
    $legacyCliText -notmatch 'tools[/\\]mir\.ps1' -or $legacyCliText.Split([char]10).Count -gt 15) {
  throw "Legacy CLI is not a thin forwarder to the public facade."
}
if ($publicCliText -match "MIR-L5-LEGACY-CLI-WRAPPER" -or
    $publicCliText -match 'Join-Path \$repo "scripts[/\\]mir\.ps1"' -or
    -not $publicCliText.Contains("function Show-MIRHelp")) {
  throw "Public CLI does not own the command dispatcher."
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
