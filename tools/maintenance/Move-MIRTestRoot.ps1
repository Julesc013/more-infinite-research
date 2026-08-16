param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)

$domains = [ordered]@{
  architecture = @(
    "Test-MIRArchitecture.ps1",
    "Test-MIRModuleDependencies.ps1"
  )
  compiler = @(
    "Test-MIRCompiler.ps1",
    "Test-MIRCompilerContractCoverage.ps1",
    "Test-MIRCompilerPreviewExport.ps1",
    "Test-MIRCompilerSchemaDrift.ps1",
    "Test-MIRNativeOwnerCostModels.ps1",
    "Test-MIRResearchCostModels.ps1",
    "Test-MIRRuleSynthesis.ps1",
    "Test-MIRSettingsVisibility.ps1",
    "Test-MIRSpaceLocationTargetInventory.ps1",
    "Test-MIRTechnologyLifecycle.ps1",
    "Test-MIRTechnologyPolicy.ps1",
    "Test-MIRTechnologyPromotionAdmission.ps1"
  )
  compatibility = @(
    "Test-MIRDependencyResolver.ps1",
    "Test-MIRLocalModLibraryCatalog.ps1",
    "Test-MIRModInteractions.ps1",
    "Test-MIRScenarioManifests.ps1"
  )
  docs = @(
    "Test-MIRLocales.ps1",
    "Test-MIRMarkdownFormatting.ps1"
  )
  package = @(
    "Test-MIRArtifactCleanup.ps1",
    "Test-MIRCandidateRetention.ps1",
    "Test-MIRContextPackage.ps1",
    "Test-MIRDeterministicPackage.ps1",
    "Test-MIRPackageComposition.ps1",
    "Test-MIRPackageIdentity.ps1"
  )
  release = @(
    "Test-MIRApprovedDelta.ps1",
    "Test-MIRApprovedPatchDelta.ps1",
    "Test-MIRBackportManifest.ps1",
    "Test-MIRBackportReconstruction.ps1",
    "Test-MIRBackportSourceLock.ps1",
    "Test-MIRBranchPolicy.ps1",
    "Test-MIRCandidateFreshness.ps1",
    "Test-MIREvidenceHygiene.ps1",
    "Test-MIRManualReleaseReview.ps1",
    "Test-MIRPerformanceBudgets.ps1",
    "Test-MIRPerformanceRegression.ps1",
    "Test-MIRPublishedSnapshotIntegrity.ps1",
    "Test-MIRReleaseAuthority.ps1",
    "Test-MIRReleaseObligation.ps1",
    "Test-MIRSanitationBudgets.ps1"
  )
  runtime = @(
    "Test-MIRMuseumCompiler.ps1",
    "Test-MIRMuseumExact.ps1",
    "Test-MIRMuseumRuntime.ps1",
    "Test-MIRMuseumSeal.ps1",
    "Test-MIRUpgrade.ps1",
    "Test-MIRUpgradeMatrix.ps1"
  )
  tooling = @(
    "Test-MIRAssurance.ps1",
    "Test-MIRContextExecutionRegistry.ps1",
    "Test-MIRControlPlane.ps1",
    "Test-MIRControlPlaneExecutor.ps1",
    "Test-MIRControlPlaneRelease.ps1",
    "Test-MIRControlPlaneShadow.ps1",
    "Test-MIRControlPlaneWorkflow.ps1",
    "Test-MIREvidenceStore.ps1",
    "Test-MIRExecutionRegistry.ps1",
    "Test-MIRGoldenPlans.ps1",
    "Test-MIRGovernance.ps1",
    "Test-MIRObservationEvaluation.ps1",
    "Test-MIRPlannerTools.ps1",
    "Test-MIRPolicyLints.ps1",
    "Test-MIRPowerShellQuality.ps1",
    "Test-MIRValidationResults.ps1",
    "Test-MIRVerificationContext.ps1",
    "Test-MIRVerificationSchemas.ps1"
  )
}

$testMap = [ordered]@{}
foreach ($domain in $domains.Keys) {
  foreach ($name in $domains[$domain]) {
    if ($testMap.Contains($name)) { throw "Duplicate test migration entry: $name" }
    $testMap[$name] = $domain
  }
}

$legacyRoot = Join-Path $RepoRoot "scripts"
$actualTests = @(Get-ChildItem -LiteralPath $legacyRoot -Filter "Test-MIR*.ps1" -File | ForEach-Object Name | Sort-Object)
$declaredTests = @($testMap.Keys | Sort-Object)
$missing = @($actualTests | Where-Object { $_ -notin $declaredTests })
$stale = @($declaredTests | Where-Object {
  -not (Test-Path -LiteralPath (Join-Path $legacyRoot $_) -PathType Leaf) -and
  -not (Test-Path -LiteralPath (Join-Path $RepoRoot ("validation/tests/{0}/{1}" -f $testMap[$_], $_)) -PathType Leaf)
})
if ($missing.Count -gt 0 -or $stale.Count -gt 0) {
  throw "Test migration catalog drift. Missing mappings: $($missing -join ', '); stale mappings: $($stale -join ', ')"
}

function ConvertTo-MIRCanonicalTest {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Path
  )

  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($Text, $Path, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) {
    throw "Cannot migrate syntactically invalid test '$Path': $($errors[0].Message)"
  }

  $bootstrap = @'

# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"
'@

  if ($null -eq $ast.ParamBlock) {
    return $bootstrap.TrimStart() + [Environment]::NewLine +
      $Text.Replace('$PSScriptRoot', '$MirLegacyScriptRoot')
  }

  $start = $ast.ParamBlock.Extent.StartOffset
  $end = $ast.ParamBlock.Extent.EndOffset
  $prefix = $Text.Substring(0, $start)
  $parameterText = $Text.Substring($start, $end - $start)
  $suffix = $Text.Substring($end)

  # Defaults that formerly walked one level from scripts/ now walk three
  # levels from validation/tests/<domain>/.
  $parameterText = $parameterText.Replace('$PSScriptRoot "..\', '$PSScriptRoot "..\..\..\')
  $parameterText = $parameterText.Replace('$PSScriptRoot "../', '$PSScriptRoot "../../../')
  $parameterText = $parameterText.Replace('$PSScriptRoot ".."', '$PSScriptRoot "../../.."')
  $suffix = $suffix.Replace('$PSScriptRoot', '$MirLegacyScriptRoot')
  return $prefix + $parameterText + $bootstrap + $suffix
}

function New-MIRLegacyTestWrapper {
  param(
    [Parameter(Mandatory)][string]$OriginalText,
    [Parameter(Mandatory)][string]$OriginalPath,
    [Parameter(Mandatory)][string]$CanonicalRelativePath
  )

  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($OriginalText, $OriginalPath, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) {
    throw "Cannot wrap syntactically invalid test '$OriginalPath': $($errors[0].Message)"
  }

  $preamble = ""
  $forward = '@args'
  if ($null -ne $ast.ParamBlock) {
    $end = $ast.ParamBlock.Extent.EndOffset
    $preamble = $OriginalText.Substring(0, $end).TrimEnd() + [Environment]::NewLine
    $forward = '@PSBoundParameters'
  }

  $targetFromScripts = "../" + $CanonicalRelativePath
  return $preamble + @"

# MIR-L4-LEGACY-TEST-WRAPPER: retained for historical commands only.
$([char]36)canonicalTest = Join-Path $([char]36)PSScriptRoot "$targetFromScripts"
& $([char]36)canonicalTest $forward
"@
}

function Get-MIRActiveTextFiles {
  $roots = @(".github", ".mir", "docs", "scripts", "validation", "tools", "spec", "fixtures")
  $files = @()
  foreach ($root in $roots) {
    $absolute = Join-Path $RepoRoot $root
    if (Test-Path -LiteralPath $absolute) {
      $files += Get-ChildItem -LiteralPath $absolute -Recurse -File
    }
  }
  foreach ($name in @("AGENTS.md", "CONTRIBUTING.md", "README.md")) {
    $absolute = Join-Path $RepoRoot $name
    if (Test-Path -LiteralPath $absolute -PathType Leaf) { $files += Get-Item -LiteralPath $absolute }
  }

  return @($files | Where-Object {
    $relative = [IO.Path]::GetRelativePath($RepoRoot, $_.FullName).Replace("\", "/")
    $_.Extension -in @(".json", ".md", ".ps1", ".psm1", ".yml", ".yaml") -and
    $relative -notlike ".mir/evidence/*" -and
    $relative -notlike ".mir/target-lines/*" -and
    $relative -notlike ".mir/releases/*" -and
    $relative -notlike ".mir/candidate-closures/*" -and
    $relative -notlike ".mir/release-transitions/*" -and
    $relative -notlike "docs/archive/*" -and
    $relative -notlike "docs/releases/*" -and
    $relative -ne "tools/maintenance/Move-MIRTestRoot.ps1"
  } | Sort-Object FullName -Unique)
}

$moveCount = 0
$moved = @()
foreach ($name in $testMap.Keys) {
  $domain = $testMap[$name]
  $legacyPath = Join-Path $legacyRoot $name
  $canonicalRelative = "validation/tests/$domain/$name"
  $canonicalPath = Join-Path $RepoRoot $canonicalRelative
  $legacyText = Get-Content -Raw -LiteralPath $legacyPath
  $isWrapper = $legacyText.Contains("MIR-L4-LEGACY-TEST-WRAPPER")

  if (-not $isWrapper) {
    if (Test-Path -LiteralPath $canonicalPath -PathType Leaf) {
      throw "Refusing ambiguous migration; canonical and legacy implementations both exist for $name."
    }
    $moveCount++
    $moved += $canonicalRelative
    if ($Apply) {
      $null = New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalPath) -Force
      $canonicalText = ConvertTo-MIRCanonicalTest -Text $legacyText -Path $legacyPath
      $wrapperText = New-MIRLegacyTestWrapper -OriginalText $legacyText -OriginalPath $legacyPath -CanonicalRelativePath $canonicalRelative
      [IO.File]::WriteAllText($canonicalPath, $canonicalText, $utf8NoBom)
      [IO.File]::WriteAllText($legacyPath, $wrapperText, $utf8NoBom)
    }
  } elseif (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) {
    throw "Legacy wrapper has no canonical implementation: $name"
  }
}

$referenceFiles = @()
$replacements = [ordered]@{}
foreach ($name in $testMap.Keys) {
  $canonical = "validation/tests/$($testMap[$name])/$name"
  $replacements["scripts/$name"] = $canonical
  $replacements["scripts\$name"] = $canonical.Replace("/", "\")
}
foreach ($file in Get-MIRActiveTextFiles) {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  $updated = $text
  foreach ($from in $replacements.Keys) {
    $updated = $updated.Replace($from, $replacements[$from])
  }
  if ($updated -ne $text) {
    $referenceFiles += [IO.Path]::GetRelativePath($RepoRoot, $file.FullName).Replace("\", "/")
    if ($Apply) { [IO.File]::WriteAllText($file.FullName, $updated, $utf8NoBom) }
  }
}

[ordered]@{
  schema = 1
  migration = "mir-test-root-v1"
  mode = if ($Apply) { "apply" } else { "preview" }
  tests = $testMap.Count
  implementations = $moveCount
  reference_files = $referenceFiles.Count
  changed = $moveCount + $referenceFiles.Count
  moved = @($moved)
  rewritten = @($referenceFiles)
} | ConvertTo-Json -Depth 6
