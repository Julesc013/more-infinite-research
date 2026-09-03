$repoInfo = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
if ($ScenarioWorker -and -not [string]::IsNullOrWhiteSpace($CandidateZip)) {
  $candidateMetadataPath = if ([IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip } else { Join-Path $repo $CandidateZip }
  if (-not (Test-Path -LiteralPath $candidateMetadataPath -PathType Leaf)) {
    throw "Scenario worker candidate package not found: $CandidateZip"
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $candidateArchive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $candidateMetadataPath).Path)
  try {
    $candidateInfoEntries = @($candidateArchive.Entries | Where-Object {
      -not $_.FullName.EndsWith('/') -and $_.FullName -match '^[^/]+/info\.json$'
    })
    if ($candidateInfoEntries.Count -ne 1) {
      throw "Scenario worker candidate must contain exactly one package-root info.json."
    }
    $candidateInfoReader = [IO.StreamReader]::new($candidateInfoEntries[0].Open(), [Text.UTF8Encoding]::new($false), $true)
    try {
      $candidateInfo = $candidateInfoReader.ReadToEnd() | ConvertFrom-Json
    } finally {
      $candidateInfoReader.Dispose()
    }
  } finally {
    $candidateArchive.Dispose()
  }
  if ([string]$candidateInfo.name -ne [string]$repoInfo.name -or
      [string]$candidateInfo.factorio_version -notin @('2.1', '2.0', '1.1', '1.0')) {
    throw "Scenario worker candidate metadata does not identify a supported MIR target."
  }
  # Runtime evidence must describe the exact candidate target rather than the
  # controller checkout's current product line.
  $repoInfo = $candidateInfo
}
$expectedScenariosPath = Join-Path $repo "validation\scenarios\runtime.json"
if ($List) {
  $listed = Import-MIRScenarioRegistry -Path $expectedScenariosPath -TargetProfile $repoInfo.factorio_version
  $listed.records | Select-Object name, kind, group, surface, @{Name="tags";Expression={$_.tags -join ","}} | Format-Table -AutoSize
  $validationRunnerCompleted = $true
  return
}
if ($Tier -in @("pure", "static")) { $StaticOnly = $true }
if ($Tier -eq "smoke" -and $Tag -notcontains "smoke") { $Tag += "smoke" }
$targetProfile = Get-MIRTargetProfile -RepoRoot $repo -FactorioVersion $repoInfo.factorio_version
$isFactorio017Line = $repoInfo.factorio_version -eq "0.17"
$isFactorio018Line = $repoInfo.factorio_version -eq "0.18"
$isFactorio10Line = $repoInfo.factorio_version -eq "1.0"
$isFactorio11Line = $repoInfo.factorio_version -eq "1.1"
$isReducedLegacyLine = [bool]$targetProfile.reduced_legacy
$isLegacyFactorio20 = [bool]$targetProfile.legacy_factorio_2_0
$isFactorio21Line = $repoInfo.factorio_version -eq "2.1"
$script:ValidationPackageZipPath = $null

function Invoke-RepoCheck {
  param([string]$Description, [scriptblock]$Script)
  if ($ScenarioWorker) { return }
  Write-Host "[check] $Description"
  & $Script
}

function Find-RepositoryText {
  param(
    [string]$Path,
    [string]$Pattern
  )

  $files = Get-ChildItem -LiteralPath $Path -Recurse -File
  if (-not $files) { return @() }
  return @($files | Select-String -Pattern $Pattern)
}

function Get-RepoRelativePath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  return [System.IO.Path]::GetRelativePath($repo.Path, $resolved).Replace("\", "/")
}

function Get-MIRCombinedSourceText {
  param([Parameter(Mandatory)][string[]]$RelativePaths)

  $chunks = @()
  foreach ($relative in $RelativePaths) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path) {
      $chunks += Get-Content -Raw -LiteralPath $path
    }
  }

  return ($chunks -join "`n")
}

function Get-MIRSettingsSourceText {
  return Get-MIRCombinedSourceText -RelativePaths @(
    "settings.lua",
    "prototypes/mir/stage/settings.lua",
    "prototypes/mir/settings/catalog.lua",
    "prototypes/mir/settings/effect_contracts.lua",
    "prototypes/mir/settings/effect_scaling.lua",
    "prototypes/mir/settings/pipeline_extent.lua",
    "prototypes/mir/settings/prototype_limits.lua",
    "prototypes/mir/settings/stage_builder.lua",
    "prototypes/mir/domain/streams/descriptor.lua"
  )
}

function Get-MIRDataFinalFixesSourceText {
  return Get-MIRCombinedSourceText -RelativePaths @(
    "data-final-fixes.lua",
    "prototypes/mir/stage/data_final_fixes.lua",
    "prototypes/mir/stage/data_final_fixes_steps.lua",
    "prototypes/mir/pipeline/commands.lua"
  )
}

function Get-DocumentationFiles {
  $files = @()
  $readmePath = Join-Path $repo "README.md"
  if (Test-Path -LiteralPath $readmePath) {
    $files += Get-Item -LiteralPath $readmePath
  }
  $todoPath = Join-Path $repo "todo.md"
  if (Test-Path -LiteralPath $todoPath) {
    $files += Get-Item -LiteralPath $todoPath
  }

  $docsPath = Join-Path $repo "docs"
  if (Test-Path -LiteralPath $docsPath) {
    $files += @(
      Get-ChildItem -LiteralPath $docsPath -Recurse -File |
        Where-Object { $_.Extension -in @(".md", ".txt") }
    )
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-PolicyTextFiles {
  $files = @()
  foreach ($relative in @("README.md", "changelog.txt")) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path) {
      $files += Get-Item -LiteralPath $path
    }
  }
  $files += Get-DocumentationFiles
  return @($files | Sort-Object FullName -Unique)
}

if ($DocsOnly -or $ManifestsOnly) {
  Invoke-RepoCheck "docs and governance manifests are linted" {
    & (Join-Path $repo "tests\tooling\Test-MIRGovernance.ps1") -RepoRoot $repo
  }
  $validationRunnerCompleted = $true
  return
}

if ($ArchitectureOnly) {
  Invoke-RepoCheck "docs and governance manifests are linted" {
    & (Join-Path $repo "tests\tooling\Test-MIRGovernance.ps1") -RepoRoot $repo
  }
  Invoke-RepoCheck "MIR architecture boundaries are linted" {
    & (Join-Path $repo "tests\architecture\Test-MIRArchitecture.ps1") -RepoRoot $repo
  }
  Invoke-RepoCheck "settings visibility policy is linted" {
    & (Join-Path $repo "tests\compiler\Test-MIRSettingsVisibility.ps1") -RepoRoot $repo
  }
  Invoke-RepoCheck "legacy inventory thresholds pass" {
    & (Join-Path $repo "tools\commands\workspace\Get-MIRLegacyInventory.ps1") -RepoRoot $repo -CheckThresholds
  }
  $validationRunnerCompleted = $true
  return
}
