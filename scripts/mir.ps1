param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$repo = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "MIRCli\Console.ps1")
. (Join-Path $scriptRoot "MIRCli\PathResolver.ps1")
. (Join-Path $scriptRoot "MIRCli\LocalModIndex.ps1")
. (Join-Path $scriptRoot "MIRCli\Reports.ps1")

function Show-MIRHelp {
  Write-Host @"
MIR developer CLI

Usage:
  .\scripts\mir.ps1 docs check
  .\scripts\mir.ps1 architecture check
  .\scripts\mir.ps1 manifests check
  .\scripts\mir.ps1 release gate [--profile <name>] [--no-git-pull]
  .\scripts\mir.ps1 release docs-only
  .\scripts\mir.ps1 release docs-refresh
  .\scripts\mir.ps1 overnight local [--profile <name>]
  .\scripts\mir.ps1 audit local [--profile <name>]
  .\scripts\mir.ps1 audit top25 --space-age
  .\scripts\mir.ps1 package build
  .\scripts\mir.ps1 storage audit [--all-worktrees] [--older-than-days <days>]
  .\scripts\mir.ps1 storage clean [--all-worktrees] [--older-than-days <days>] --apply
  .\scripts\mir.ps1 technology quality-assessment --catalog <path> --candidate <id> --profile <path> [--metrics <path>] --output <path>
  .\scripts\mir.ps1 technology review-dossier --catalog <path> --candidate <id> [--assessment <path>] --output <path>
  .\scripts\mir.ps1 technology promotion-gate --catalog <path> --assessment <path> --approval <path> --promotion <path> --profile <path> [--migration <path>] --output <path>
  .\scripts\mir.ps1 assurance <doctor|inventory|impact|domains|plan|fingerprint|build|run-one|verify|gate|qualify|seal|check-seal|locale|balance|backport|explain>
  .\scripts\mir.ps1 verify <plan|fingerprint|explain|run-one|run|gate|qualify>
  .\scripts\mir.ps1 report latest
  .\scripts\mir.ps1 report missing-deps --run <path>
  .\scripts\mir.ps1 report observations --run <path>
  .\scripts\mir.ps1 legacy inventory [--output <path>] [--check]
  .\scripts\mir.ps1 profile stub <group-id> --grouped-failures <path>
  .\scripts\mir.ps1 run -Profile <profile-name-or-path>
  .\scripts\mir.ps1 local-index build --mods <path>

Common overrides:
  --factorio <path>   Factorio binary path
  --factorio-line <2.0|2.1>
  --candidate <path>  Exact MIR candidate ZIP for candidate-bound runtime work
  --mods <path>       Local mod zip/library directory
  --output <path>     Output artifact directory
  --timeout <seconds> Per-scenario timeout
  --link-mode <mode>  Copy, Hardlink, or Symlink local zips into scenario mod dirs
  --skip-strict-gate  Reuse an already completed strict gate in a composed assurance run
  --skip-clean-git-status  Leave source authority to the composed assurance and sealing gates
"@
}

function Get-MIRArgValue {
  param(
    [string[]]$Items,
    [string]$Name,
    [string]$Default = ""
  )
  for ($i = 0; $i -lt $Items.Count; $i++) {
    if ($Items[$i] -eq $Name -and $i + 1 -lt $Items.Count) { return $Items[$i + 1] }
  }
  return $Default
}

function Test-MIRArgSwitch {
  param([string[]]$Items, [string]$Name)
  return $Items -contains $Name
}

function Get-MIRCommandProfile {
  param(
    [string[]]$Items,
    [string]$Default
  )
  $profile = Get-MIRArgValue -Items $Items -Name "--profile"
  if ([string]::IsNullOrWhiteSpace($profile)) {
    $profile = Get-MIRArgValue -Items $Items -Name "-Profile"
  }
  if ([string]::IsNullOrWhiteSpace($profile)) { return $Default }
  return $profile
}

function New-MIRProfileOverrides {
  param([string[]]$Items)

  $overrides = @{}
  $factorio = Get-MIRArgValue -Items $Items -Name "--factorio"
  $factorioLine = Get-MIRArgValue -Items $Items -Name "--factorio-line"
  $mods = Get-MIRArgValue -Items $Items -Name "--mods"
  $candidate = Get-MIRArgValue -Items $Items -Name "--candidate"
  $output = Get-MIRArgValue -Items $Items -Name "--output"
  $timeout = Get-MIRArgValue -Items $Items -Name "--timeout"
  $linkMode = Get-MIRArgValue -Items $Items -Name "--link-mode"

  if (-not [string]::IsNullOrWhiteSpace($factorio)) {
    $overrides.factorio_bin = $factorio
  }
  if (-not [string]::IsNullOrWhiteSpace($factorioLine)) {
    if ($factorioLine -notin @("2.0", "2.1")) { throw "--factorio-line must be 2.0 or 2.1." }
    $overrides.factorio_line = $factorioLine
  }
  if (-not [string]::IsNullOrWhiteSpace($mods)) {
    $overrides.local_mod_dir = $mods
    $overrides.local_mod_zip_dirs = @($mods)
    $overrides.local_mod_library_dirs = @($mods)
  }
  if (-not [string]::IsNullOrWhiteSpace($candidate)) {
    $overrides.candidate_zip = $candidate
  }
  if (-not [string]::IsNullOrWhiteSpace($output)) {
    $overrides.output_root = $output
  }
  if (-not [string]::IsNullOrWhiteSpace($timeout)) {
    $overrides.scenario_timeout_seconds = [int]$timeout
  }
  if (-not [string]::IsNullOrWhiteSpace($linkMode)) {
    if ($linkMode -notin @("Copy", "Hardlink", "Symlink")) { throw "--link-mode must be Copy, Hardlink, or Symlink." }
    $overrides.link_mode = $linkMode
  }
  if (Test-MIRArgSwitch -Items $Items -Name "--no-git-pull") {
    $overrides.no_git_pull = $true
  }
  if (Test-MIRArgSwitch -Items $Items -Name "--skip-strict-gate") {
    $overrides.skip_strict_gate = $true
  }
  if (Test-MIRArgSwitch -Items $Items -Name "--skip-build") {
    $overrides.skip_build = $true
  }
  if (Test-MIRArgSwitch -Items $Items -Name "--skip-clean-git-status") {
    $overrides.skip_clean_git_status = $true
  }

  return $overrides
}

function Get-MIRLatestRunRoot {
  $artifactRoot = Join-Path $repo "artifacts"
  if (-not (Test-Path -LiteralPath $artifactRoot)) { throw "No artifacts directory exists." }
  $run = Get-ChildItem -LiteralPath $artifactRoot -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $run) { throw "No artifact run directories found." }
  return $run.FullName
}

function Resolve-MIRProfilePath {
  param([string]$Profile)
  if ([string]::IsNullOrWhiteSpace($Profile)) { throw "Profile is required." }
  if (Test-Path -LiteralPath $Profile) { return (Resolve-Path -LiteralPath $Profile).Path }

  $candidate = Join-Path $repo ("fixtures\run-profiles\{0}.json" -f $Profile)
  if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }

  throw "Run profile not found: $Profile"
}

function Get-MIRProfileProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Get-MIRDefaultLocalModDir {
  $profilePath = Resolve-MIRProfilePath -Profile "local-audit-2.1"
  $profileData = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
  $dirs = Get-MIRProfileProperty -Object $profileData -Name "local_mod_zip_dirs" -Default @()
  $first = @($dirs | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
  if ($first.Count -gt 0) { return $first[0] }
  return ".\tmp"
}

function Test-MIRProfileFlag {
  param($Object, [string]$Name)
  $value = Get-MIRProfileProperty -Object $Object -Name $Name -Default $false
  return [bool]$value
}

function Get-MIRProfileOrOverride {
  param(
    $Object,
    [hashtable]$Overrides,
    [string]$Name,
    $Default = $null
  )
  if ($Overrides -and $Overrides.ContainsKey($Name)) { return $Overrides[$Name] }
  return Get-MIRProfileProperty -Object $Object -Name $Name -Default $Default
}

function Test-MIRProfileOrOverrideFlag {
  param(
    $Object,
    [hashtable]$Overrides,
    [string]$Name
  )
  if ($Overrides -and $Overrides.ContainsKey($Name)) { return [bool]$Overrides[$Name] }
  return Test-MIRProfileFlag -Object $Object -Name $Name
}

function Invoke-MIRRunProfile {
  param(
    [string]$Profile,
    [hashtable]$Overrides = @{}
  )

  $profilePath = Resolve-MIRProfilePath -Profile $Profile
  $profileData = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
  $kind = [string](Get-MIRProfileProperty -Object $profileData -Name "kind" -Default "")
  if ([string]::IsNullOrWhiteSpace($kind)) { $kind = "extended" }

  switch ($kind) {
    "release-targeted" {
      $params = @{}
      $factorioBin = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "factorio_bin"
      $factorioLine = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "factorio_line"
      $localModDir = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "local_mod_dir"
      $outputRoot = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "output_root"
      $candidateZip = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "candidate_zip"
      $repairSmokeModNames = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "repair_smoke_mod_names"
      $representativeScenarioName = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "representative_scenario_name"
      $manualScenariosPath = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "manual_scenarios_path"
      $auditFactorioVersions = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "audit_factorio_versions"
      $timeout = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "scenario_timeout_seconds"
      if ($factorioBin) { $params.FactorioBin = Resolve-MIRFactorioBin -Path ([string]$factorioBin) }
      if ($factorioLine) { $params.FactorioLine = [string]$factorioLine }
      if ($localModDir) { $params.LocalModDir = [string]$localModDir }
      if ($outputRoot) { $params.OutputRoot = [string]$outputRoot }
      if ($candidateZip) { $params.CandidateZip = [string]$candidateZip }
      if ($repairSmokeModNames) { $params.RepairSmokeModNames = @($repairSmokeModNames | ForEach-Object { [string]$_ }) }
      if ($representativeScenarioName) { $params.RepresentativeScenarioName = [string]$representativeScenarioName }
      if ($manualScenariosPath) { $params.ManualScenariosPath = [string]$manualScenariosPath }
      if ($auditFactorioVersions) { $params.AuditFactorioVersions = @($auditFactorioVersions | ForEach-Object { [string]$_ }) }
      if ($timeout) { $params.ScenarioTimeoutSeconds = [int]$timeout }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "no_git_pull") { $params.NoGitPull = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "skip_strict_gate") { $params.SkipStrictGate = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "skip_repair_smokes") { $params.SkipRepairSmokes = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "skip_representative_scenario") { $params.SkipRepresentativeScenario = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "skip_build") { $params.SkipBuild = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "skip_clean_git_status") { $params.SkipCleanGitStatus = $true }
      & (Join-Path $scriptRoot "Invoke-MIRReleaseTargetedGate.ps1") @params
    }
    "overnight-local" {
      $params = @{}
      $factorioBin = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "factorio_bin"
      $factorioLine = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "factorio_line"
      $localModDir = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "local_mod_dir"
      $localModLibraryDirs = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "local_mod_library_dirs"
      $outputRoot = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "output_root"
      $timeout = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "scenario_timeout_seconds"
      $pairwiseLimit = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "generated_local_pairwise_limit"
      $linkMode = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "link_mode"
      if ($factorioBin) { $params.FactorioBin = Resolve-MIRFactorioBin -Path ([string]$factorioBin) }
      if ($factorioLine) { $params.FactorioLine = [string]$factorioLine }
      if ($localModDir) { $params.LocalModDir = [string]$localModDir }
      if ($localModLibraryDirs) { $params.LocalModLibraryDirs = @($localModLibraryDirs | ForEach-Object { [string]$_ }) }
      if ($outputRoot) { $params.OutputRoot = [string]$outputRoot }
      if ($timeout) { $params.ScenarioTimeoutSeconds = [int]$timeout }
      if ($pairwiseLimit) { $params.GeneratedLocalPairwiseLimit = [int]$pairwiseLimit }
      if ($linkMode) { $params.LinkMode = [string]$linkMode }
      & (Join-Path $scriptRoot "Start-MIROvernightLocalSweep.ps1") @params
    }
    default {
      $tiers = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "tiers" -Default @("Static")
      $params = @{
        Tier = @($tiers | ForEach-Object { [string]$_ })
      }
      $factorioBin = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "factorio_bin"
      $factorioLine = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "factorio_line"
      $outputRoot = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "output_root"
      $manualScenariosPath = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "manual_scenarios_path"
      $localModZipDirs = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "local_mod_zip_dirs"
      $localModLibraryDirs = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "local_mod_library_dirs"
      $scenarioNames = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "scenario_names"
      $localModNames = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "local_mod_names"
      $timeout = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "scenario_timeout_seconds"
      $pairwiseLimit = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "generated_local_pairwise_limit"
      $linkMode = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "link_mode"
      if ($factorioBin) { $params.FactorioBin = Resolve-MIRFactorioBin -Path ([string]$factorioBin) }
      if ($factorioLine) { $params.FactorioLine = [string]$factorioLine }
      if ($outputRoot) { $params.OutputRoot = [string]$outputRoot }
      if ($manualScenariosPath) { $params.ManualScenariosPath = [string]$manualScenariosPath }
      if ($localModZipDirs) { $params.LocalModZipDirs = @($localModZipDirs | ForEach-Object { [string]$_ }) }
      if ($localModLibraryDirs) { $params.LocalModLibraryDirs = @($localModLibraryDirs | ForEach-Object { [string]$_ }) }
      if ($scenarioNames) { $params.ScenarioNames = @($scenarioNames | ForEach-Object { [string]$_ }) }
      if ($localModNames) { $params.LocalModNames = @($localModNames | ForEach-Object { [string]$_ }) }
      if ($timeout) { $params.ScenarioTimeoutSeconds = [int]$timeout }
      if ($linkMode) { $params.LinkMode = [string]$linkMode }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "collect_all") { $params.CollectAll = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "offline") { $params.Offline = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "fail_fast") { $params.FailFast = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "fail_on_audit_failures") { $params.FailOnAuditFailures = $true }
      if (Test-MIRProfileOrOverrideFlag -Object $profileData -Overrides $Overrides -Name "include_generated_local_pairwise") { $params.IncludeGeneratedLocalPairwise = $true }
      if ($pairwiseLimit) { $params.GeneratedLocalPairwiseLimit = [int]$pairwiseLimit }
      & (Join-Path $scriptRoot "Invoke-MIRExtendedTests.ps1") @params
    }
  }
}

function Get-MIRGitStatusPaths {
  $lines = @(& git -C $repo status --porcelain)
  if ($LASTEXITCODE -ne 0) { throw "git status failed." }

  $paths = @()
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $pathText = $line.Substring(3)
    if ($pathText -match " -> ") {
      $paths += @($pathText -split " -> ")
    } else {
      $paths += $pathText
    }
  }

  return @($paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
}

function Test-MIRDocsOnlyReleasePath {
  param([Parameter(Mandatory)][string]$Path)

  $normalized = $Path.Replace("\", "/")
  return (
    $normalized -match "^docs/" -or
    $normalized -match "^dist/[^/]+\.zip$" -or
    $normalized -in @(
      "README.md",
      "changelog.txt",
      "CONTRIBUTING.md",
      "LICENSE",
      "todo.md"
    )
  )
}

function Assert-MIRDocsOnlyReleaseStatus {
  param([Parameter(Mandatory)][string]$Stage)

  $paths = @(Get-MIRGitStatusPaths)
  $bad = @($paths | Where-Object { -not (Test-MIRDocsOnlyReleasePath -Path $_) })
  if ($bad.Count -gt 0) {
    throw "Docs-only release check found non-doc/package changes during ${Stage}: $($bad -join ', '). Run the full release gate instead."
  }

  if ($paths.Count -eq 0) {
    Write-MIRInfo "$Stage git status: clean"
  } else {
    Write-MIRInfo "$Stage allowed changes: $($paths -join ', ')"
  }
}

function Invoke-MIRDocsOnlyReleaseCheck {
  Assert-MIRDocsOnlyReleaseStatus -Stage "before docs-only validation"

  Write-MIRStep "building release package"
  & (Join-Path $scriptRoot "Build-MIRPackage.ps1")
  if ($LASTEXITCODE -ne 0) { throw "Build-MIRPackage.ps1 failed." }

  Write-MIRStep "running static/package validation"
  & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -StaticOnly
  if ($LASTEXITCODE -ne 0) { throw "Invoke-MIRValidation.ps1 -StaticOnly failed." }

  Write-MIRStep "checking whitespace"
  & git -C $repo diff --check
  if ($LASTEXITCODE -ne 0) { throw "git diff --check failed." }

  Assert-MIRDocsOnlyReleaseStatus -Stage "after docs-only validation"
  Write-MIRSuccess "docs-only release validation passed"
}

if ($Args.Count -eq 0 -or $Args[0] -eq "help" -or $Args -contains "-h" -or $Args -contains "--help") {
  Show-MIRHelp
  exit 0
}

$area = $Args[0]
$verb = if ($Args.Count -gt 1) { $Args[1] } else { "" }

switch ($area) {
  "verify" {
    $verifyCommand = switch ($verb) {
      "plan" { "plan" }
      "fingerprint" { "fingerprint" }
      "explain" { "explain" }
      "run-one" { "run-one" }
      "run" { "verify" }
      "gate" { "gate" }
      "qualify" { "qualify" }
      default { throw "Unknown verify command: $verb" }
    }
    [string[]]$verifyArgs = @($verifyCommand)
    if ($Args.Count -gt 2) { $verifyArgs += @($Args[2..($Args.Count - 1)]) }
    & (Join-Path $scriptRoot "Invoke-MIRAssurance.ps1") @verifyArgs
  }
  "assurance" {
    [string[]]$assuranceArgs = if ($Args.Count -gt 1) { @($Args[1..($Args.Count - 1)]) } else { @("help") }
    & (Join-Path $scriptRoot "Invoke-MIRAssurance.ps1") @assuranceArgs
  }
  "docs" {
    if ($verb -ne "check") { throw "Unknown docs command: $verb" }
    & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -DocsOnly
  }
  "architecture" {
    if ($verb -ne "check") { throw "Unknown architecture command: $verb" }
    & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -ArchitectureOnly
  }
  "manifests" {
    if ($verb -ne "check") { throw "Unknown manifests command: $verb" }
    & (Join-Path $scriptRoot "Invoke-MIRValidation.ps1") -ManifestsOnly
  }
  "technology" {
    $catalog = Get-MIRArgValue -Items $Args -Name "--catalog"
    $candidateId = Get-MIRArgValue -Items $Args -Name "--candidate"
    $output = Get-MIRArgValue -Items $Args -Name "--output"
    if ([string]::IsNullOrWhiteSpace($catalog) -or [string]::IsNullOrWhiteSpace($output)) {
      throw "technology commands require --catalog and --output."
    }
    switch ($verb) {
      "quality-assessment" {
        $profilePath = Get-MIRArgValue -Items $Args -Name "--profile"
        if ([string]::IsNullOrWhiteSpace($candidateId) -or [string]::IsNullOrWhiteSpace($profilePath)) {
          throw "technology quality-assessment requires --candidate and --profile."
        }
        $params = @{CatalogPath=$catalog; CandidateId=$candidateId; ProfilePath=$profilePath; OutputPath=$output}
        $metrics = Get-MIRArgValue -Items $Args -Name "--metrics"
        if ($metrics) { $params.MetricsPath = $metrics }
        & (Join-Path $scriptRoot "New-MIRTechnologyQualityAssessment.ps1") @params
      }
      "review-dossier" {
        if ([string]::IsNullOrWhiteSpace($candidateId)) { throw "technology review-dossier requires --candidate." }
        $params = @{CatalogPath=$catalog; CandidateId=$candidateId; OutputPath=$output}
        $assessment = Get-MIRArgValue -Items $Args -Name "--assessment"
        if ($assessment) { $params.AssessmentPath = $assessment }
        & (Join-Path $scriptRoot "New-MIRTechnologyReviewDossier.ps1") @params
      }
      "promotion-gate" {
        $assessment = Get-MIRArgValue -Items $Args -Name "--assessment"
        $approval = Get-MIRArgValue -Items $Args -Name "--approval"
        $promotion = Get-MIRArgValue -Items $Args -Name "--promotion"
        $profilePath = Get-MIRArgValue -Items $Args -Name "--profile"
        foreach ($value in @($assessment, $approval, $promotion, $profilePath)) {
          if ([string]::IsNullOrWhiteSpace($value)) { throw "technology promotion-gate requires --assessment, --approval, --promotion, and --profile." }
        }
        $params = @{
          CatalogPath=$catalog; AssessmentPath=$assessment; ApprovalPath=$approval
          PromotionPath=$promotion; ProfilePath=$profilePath; OutputPath=$output
        }
        $migration = Get-MIRArgValue -Items $Args -Name "--migration"
        if ($migration) { $params.MigrationPath = $migration }
        & (Join-Path $scriptRoot "Test-MIRTechnologyPromotionAdmission.ps1") @params
      }
      default { throw "Unknown technology command: $verb" }
    }
  }
  "release" {
    switch ($verb) {
      "gate" {
        $profile = Get-MIRCommandProfile -Items $Args -Default "release-targeted"
        Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
      }
      "docs-only" {
        Invoke-MIRDocsOnlyReleaseCheck
      }
      "docs-refresh" {
        Invoke-MIRDocsOnlyReleaseCheck
      }
      default { throw "Unknown release command: $verb" }
    }
  }
  "overnight" {
    if ($verb -ne "local") { throw "Unknown overnight command: $verb" }
    $profile = Get-MIRCommandProfile -Items $Args -Default "overnight-local-2.1"
    Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
  }
  "audit" {
    switch ($verb) {
      "local" {
        $profile = Get-MIRCommandProfile -Items $Args -Default "local-audit-2.1"
        Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
      }
      "top25" {
        $includeSpaceAge = Test-MIRArgSwitch -Items $Args -Name "--space-age"
        $tier = if ($includeSpaceAge) { "Top25SpaceAge" } else { "Top25Base" }
        & (Join-Path $scriptRoot "Invoke-MIRExtendedTests.ps1") -Tier $tier -CollectAll
      }
      default { throw "Unknown audit command: $verb" }
    }
  }
  "package" {
    if ($verb -ne "build") { throw "Unknown package command: $verb" }
    & (Join-Path $scriptRoot "Build-MIRPackage.ps1")
  }
  "storage" {
    if ($verb -notin @("audit", "clean")) { throw "Unknown storage command: $verb" }
    $olderThanText = Get-MIRArgValue -Items $Args -Name "--older-than-days" -Default "7"
    [int]$olderThanDays = 0
    if (-not [int]::TryParse($olderThanText, [ref]$olderThanDays) -or $olderThanDays -lt 0) {
      throw "--older-than-days must be a non-negative integer."
    }
    $params = @{
      RepoRoot = $repo.Path
      OlderThanDays = $olderThanDays
      AllWorktrees = (Test-MIRArgSwitch -Items $Args -Name "--all-worktrees")
    }
    if ($verb -eq "clean" -and (Test-MIRArgSwitch -Items $Args -Name "--apply")) { $params.Apply = $true }
    & (Join-Path $scriptRoot "Remove-MIRStaleArtifacts.ps1") @params
  }
  "report" {
    switch ($verb) {
      "latest" {
        & (Join-Path $scriptRoot "Show-MIROvernightSummary.ps1") -OutputRoot (Get-MIRLatestRunRoot)
      }
      "missing-deps" {
        $run = Get-MIRArgValue -Items $Args -Name "--run" -Default (Get-MIRLatestRunRoot)
        Get-ChildItem -LiteralPath $run -Recurse -Filter missing-dependencies.csv -File |
          ForEach-Object { Import-Csv -LiteralPath $_.FullName } |
          Group-Object mod |
          Sort-Object Count -Descending |
          Select-Object @{Name='mod';Expression={$_.Name}},Count |
          Format-Table -AutoSize
      }
      "observations" {
        $run = Get-MIRArgValue -Items $Args -Name "--run" -Default (Get-MIRLatestRunRoot)
        Get-ChildItem -LiteralPath $run -Recurse -Filter compat-observations.csv -File |
          ForEach-Object { Import-Csv -LiteralPath $_.FullName } |
          Group-Object kind |
          Sort-Object Count -Descending |
          Select-Object @{Name='kind';Expression={$_.Name}},Count |
          Format-Table -AutoSize
      }
      default { throw "Unknown report command: $verb" }
    }
  }
  "legacy" {
    if ($verb -ne "inventory") { throw "Unknown legacy command: $verb" }
    $output = Get-MIRArgValue -Items $Args -Name "--output" -Default (Join-Path $repo "artifacts\legacy-inventory")
    $params = @{ OutputRoot = $output }
    if (Test-MIRArgSwitch -Items $Args -Name "--check") {
      $params.CheckThresholds = $true
    }
    & (Join-Path $scriptRoot "Get-MIRLegacyInventory.ps1") @params
  }
  "profile" {
    if ($verb -ne "stub") { throw "Unknown profile command: $verb" }
    if ($Args.Count -lt 3) { throw "profile stub requires a group id." }
    $groupId = $Args[2]
    $groupedFailures = Get-MIRArgValue -Items $Args -Name "--grouped-failures"
    if ([string]::IsNullOrWhiteSpace($groupedFailures)) { throw "--grouped-failures is required." }
    & (Join-Path $scriptRoot "New-MIRCompatProfileStub.ps1") -GroupedFailures $groupedFailures -GroupId $groupId
  }
  "run" {
    $profile = Get-MIRArgValue -Items $Args -Name "-Profile"
    if ([string]::IsNullOrWhiteSpace($profile)) { $profile = Get-MIRArgValue -Items $Args -Name "--profile" }
    Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
  }
  "local-index" {
    if ($verb -ne "build") { throw "Unknown local-index command: $verb" }
    $mods = Get-MIRArgValue -Items $Args -Name "--mods" -Default (Get-MIRDefaultLocalModDir)
    $out = Get-MIRArgValue -Items $Args -Name "--out" -Default (Join-Path $repo "build\cache\local-mod-index\local-mod-index.2.1.json")
    New-MIRLocalModIndex -Dirs @($mods) -OutputPath $out | Out-Null
    Write-MIRSuccess "wrote $out"
  }
  default {
    throw "Unknown command area: $area"
  }
}
