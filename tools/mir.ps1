param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$scriptRoot = Join-Path $repo "scripts"
. (Join-Path $repo "tools\lib\cli\Console.ps1")
. (Join-Path $repo "tools\lib\cli\PathResolver.ps1")
. (Join-Path $repo "tools\lib\cli\LocalModIndex.ps1")
. (Join-Path $repo "tools\lib\cli\Reports.ps1")
. (Join-Path $repo "tools\mir\domain\targets\TargetKey.ps1")

function Show-MIRHelp {
  Write-Host @"
MIR developer CLI

Usage:
  .\tools\mir.ps1 layout check [--strict] [--output <path>]
  .\tools\mir.ps1 layout inventory [--output <path>]
  .\tools\mir.ps1 path resolve <logical-id>
  .\tools\mir.ps1 path resolve --path <historical-path>
  .\tools\mir.ps1 docs check
  .\tools\mir.ps1 architecture check
  .\tools\mir.ps1 manifests check
  .\tools\mir.ps1 mir4 capture-terminal-baselines [--check] [--build-bundles]
  .\tools\mir.ps1 mir4 import-terminal-baselines [--output <path>] [--check]
  .\tools\mir.ps1 mir4 check [--update] [--build-bundles]
  .\tools\mir.ps1 mir4 build-local-beta [--target <all|F210|F200|F110|F100>] [--output <path>] [--repetitions <n>]
  .\tools\mir.ps1 mir4 check-local-beta [--target <all|F210|F200|F110|F100>] [--output <path>]
  .\tools\mir.ps1 mir4 build-local-playtest [--target <all|F200|F110|F100>] [--repetitions <n>]
  .\tools\mir.ps1 mir4 check-local-playtest [--target <all|F200|F110|F100>]
  .\tools\mir.ps1 mir4 build-historical-private [--target <all|F018|F017|F016|F015|F014|F013>]
  .\tools\mir.ps1 mir4 check-historical-private [--target <all|F018|F017|F016|F015|F014|F013>]
  .\tools\mir.ps1 mir4 build-m4c01-player-set
  .\tools\mir.ps1 mir4 check-m4c01-player-set
  .\tools\mir.ps1 mir4 runtime-historical-private --target <F017|F016|F015|F014|F013> [--factorio-bin <path>] [--candidate <path>] [--evidence <path>]
  .\tools\mir.ps1 mir4 api <check|conformance>
  .\tools\mir.ps1 mir4 sdk <generate|check>
  .\tools\mir.ps1 mir4 platform <generate|check|conformance|package>
  .\tools\mir.ps1 mir4 platform compile --target <FNNN> --extension <path> --output <path>
  .\tools\mir.ps1 mir4 environment-evidence <lock|diff|bundle|minimize|verify|reference> [--input <path>] [--other <path>] [--output <path>]
  .\tools\mir.ps1 mir4 assurance-scale <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 release-governance <check|initialize> [--output <path>]
  .\tools\mir.ps1 mir4 repository <generate|check|inventory|initialize> [--output <path>]
  .\tools\mir.ps1 mir4 canonicalization-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 diagnostics-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 target-key-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 whole-platform-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 technology-acceptance-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 target-compiler-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 semantic-compiler-policy-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 runtime-continuity-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 module-sdk-mep-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 processir-exact-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 inspector-compatibility-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 assurance-offline-custody-migration <check|show> [--output <path>]
  .\tools\mir.ps1 mir4 historical-tooling-migration <generate|check|show> [--output <path>]
  .\tools\mir.ps1 mir4 historical-succession <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 targets <contracts|laws|build|check> [--target <all|FNNN>] [--output <path>]
  .\tools\mir.ps1 mir4 semantic <export|check|laws> [--output <path>]
  .\tools\mir.ps1 mir4 runtime-continuity <export|check|laws> [--candidate <path>] [--output <path>]
  .\tools\mir.ps1 mir4 module-ecosystem <export|check> [--candidate <path>] [--output <path>]
  .\tools\mir.ps1 mir4 processir-synthesis <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 exact-processir <export|check> [--capture <id>]... [--repetitions <1-4>] [--output <path>] [--reference <path>] [--publish-reference]
  .\tools\mir.ps1 mir4 release-canaries <export|check> [--capture-root <path>] [--upgrade-root <path>] [--output <path>] [--reference <path>] [--publish-reference]
  .\tools\mir.ps1 mir4 inspector-compatibility <export|check> [--output <path>]
  .\tools\mir.ps1 mir4 whole-platform <generate|check|matrix|target-key> [--target <FNNN>]
  .\tools\mir.ps1 mir4 acceptance queue --catalog <path> --target <FNNN> --ecosystem <id> --output <path>
  .\tools\mir.ps1 mir4 extension <init|validate|explain|test|package|migrate|doctor|lock|diff|ci-init|discover> [--extension <path>] [--discovery <snapshot.json>] [--output <path>] [--id <reverse.dns.id>] [--template <minimal|all-fragments|unavailable>] [--target <FNNN>] [--base <path>] [--candidate <path>]
  .\tools\mir.ps1 mir4 handoff-m4c01 [--output <path>]
  .\tools\mir.ps1 release doctor [--json] [--dry-run] [--explain] [--output <path>]
  .\tools\mir.ps1 playtest prepare --target <F210|F200> [--candidate <path>] [--predecessor <path>] [--factorio <path>] [--settings <path>] [--save <path>] [--output <path>] [--dry-run] [--json]
  .\tools\mir.ps1 playtest capture --session <path> [--capture <path>]... [--observations <path>] [--dry-run] [--json]
  .\tools\mir.ps1 playtest finalize --session <path> --decision <ACCEPTED|CHANGES-REQUESTED|REJECTED> --reviewer <name> [--notes <text>] [--dry-run] [--json]
  .\tools\mir.ps1 rulesets audit [--json] [--output <path>]
  .\tools\mir.ps1 release gate [--profile <name>] [--no-git-pull]
  .\tools\mir.ps1 release docs-only
  .\tools\mir.ps1 release docs-refresh
  .\tools\mir.ps1 overnight local [--profile <name>]
  .\tools\mir.ps1 audit local [--profile <name>]
  .\tools\mir.ps1 audit top25 --space-age
  .\tools\mir.ps1 package build
  .\tools\mir.ps1 backport validate [--manifest <path>] [--allow-pending-tags]
  .\tools\mir.ps1 backport materialize --source <tag> --baseline <tag> --target <line> --manifest <path> --worktree <path> [--receipt <path>]
  .\tools\mir.ps1 storage audit [--all-worktrees] [--older-than-days <days>]
  .\tools\mir.ps1 storage clean [--all-worktrees] [--older-than-days <days>] --apply
  .\tools\mir.ps1 technology quality-assessment --catalog <path> --candidate <id> --profile <path> [--metrics <path>] --output <path>
  .\tools\mir.ps1 technology review-dossier --catalog <path> --candidate <id> [--assessment <path>] --output <path>
  .\tools\mir.ps1 technology promotion-gate --catalog <path> --assessment <path> --approval <path> --promotion <path> --profile <path> [--migration <path>] --output <path>
  .\tools\mir.ps1 assurance <doctor|inventory|impact|domains|plan|fingerprint|build|run-one|verify|gate|qualify|seal|check-seal|locale|balance|backport|explain>
  .\tools\mir.ps1 verify <plan|fingerprint|explain|run-one|run|import-workers|gate|qualify>
  .\tools\mir.ps1 report latest
  .\tools\mir.ps1 report missing-deps --run <path>
  .\tools\mir.ps1 report observations --run <path>
  .\tools\mir.ps1 legacy inventory [--output <path>] [--check]
  .\tools\mir.ps1 profile stub <group-id> --grouped-failures <path>
  .\tools\mir.ps1 run -Profile <profile-name-or-path>
  .\tools\mir.ps1 local-index build --mods <path>

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

function Get-MIRArgValues {
  param([string[]]$Items,[string]$Name)
  $values = @()
  for ($i = 0; $i -lt $Items.Count; $i++) {
    if ($Items[$i] -eq $Name -and $i + 1 -lt $Items.Count) { $values += [string]$Items[$i + 1] }
  }
  return @($values)
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
  $candidateSource = Get-MIRArgValue -Items $Items -Name "--candidate-source"
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
  if (-not [string]::IsNullOrWhiteSpace($candidateSource)) {
    $overrides.candidate_source_commit = $candidateSource
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
  $runRoots = @(
    (Join-Path $repo "build\results\runs"),
    (Join-Path $repo "artifacts")
  )
  $run = @($runRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Directory
  }) |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $run) { throw "No canonical or legacy artifact run directories found." }
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
      $candidateSourceCommit = Get-MIRProfileOrOverride -Object $profileData -Overrides $Overrides -Name "candidate_source_commit"
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
      if ($candidateSourceCommit) { $params.CandidateSourceCommit = [string]$candidateSourceCommit }
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
  & (Join-Path $repo "tools/commands/package/Build-MIRPackage.ps1")
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
  "layout" {
    if ($verb -notin @("check", "inventory")) { throw "Unknown layout command: $verb" }
    $output = Get-MIRArgValue -Items $Args -Name "--output"
    $params = @{
      RepoRoot = $repo.Path
      Strict = (Test-MIRArgSwitch -Items $Args -Name "--strict")
      InventoryOnly = ($verb -eq "inventory")
    }
    if (-not [string]::IsNullOrWhiteSpace($output)) { $params.OutputPath = $output }
    & (Join-Path $repo "tools/commands/workspace/Invoke-MIRLayoutCheck.ps1") @params
  }
  "path" {
    if ($verb -ne "resolve") { throw "Unknown path command: $verb" }
    $id = Get-MIRArgValue -Items $Args -Name "--id"
    $path = Get-MIRArgValue -Items $Args -Name "--path"
    if ([string]::IsNullOrWhiteSpace($id) -and [string]::IsNullOrWhiteSpace($path) -and $Args.Count -gt 2) {
      $id = $Args[2]
    }
    $params = @{RepoRoot=$repo.Path}
    if (-not [string]::IsNullOrWhiteSpace($id)) { $params.Id = $id }
    if (-not [string]::IsNullOrWhiteSpace($path)) { $params.Path = $path }
    & (Join-Path $repo "tools/commands/workspace/Resolve-MIRRepoPath.ps1") @params
  }
  "verify" {
    $verifyCommand = switch ($verb) {
      "plan" { "plan" }
      "fingerprint" { "fingerprint" }
      "explain" { "explain" }
      "run-one" { "run-one" }
      "run" { "verify" }
      "import-workers" { "import-workers" }
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
  "mir4" {
    switch ($verb) {
      "capture-terminal-baselines" {
        $params = @{
          RepoRoot = $repo.Path
          Check = (Test-MIRArgSwitch -Items $Args -Name "--check")
          BuildBundles = (Test-MIRArgSwitch -Items $Args -Name "--build-bundles")
        }
        & (Join-Path $repo "tools/commands/release/New-MIR3Dot9TerminalBaselines.ps1") @params
      }
      "import-terminal-baselines" {
        $output = Get-MIRArgValue -Items $Args -Name "--output"
        $params = @{ RepoRoot = $repo.Path; Check = (Test-MIRArgSwitch -Items $Args -Name "--check") }
        if (-not [string]::IsNullOrWhiteSpace($output)) { $params.OutputPath = $output }
        & (Join-Path $repo "tools/commands/release/Import-MIR3TerminalBaselines.ps1") @params
      }
      "check" {
        & (Join-Path $repo "tools/commands/release/Test-MIR4R0Bootstrap.ps1") `
          -RepoRoot $repo.Path `
          -Update:(Test-MIRArgSwitch -Items $Args -Name "--update") `
          -BuildBundles:(Test-MIRArgSwitch -Items $Args -Name "--build-bundles")
      }
      { $_ -in @("build-local-beta", "check-local-beta") } {
        $targetInput = Get-MIRArgValue -Items $Args -Name "--target" -Default "F210"
        $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
        $output = Get-MIRArgValue -Items $Args -Name "--output" -Default "build/mir4/emergency-lane"
        $repetitionsText = Get-MIRArgValue -Items $Args -Name "--repetitions" -Default "3"
        $repetitions = 0
        if (-not [int]::TryParse($repetitionsText, [ref]$repetitions) -or $repetitions -ne 3) {
          throw "--repetitions must be exactly 3 for the A/B/C bootstrap profile."
        }
        & (Join-Path $repo "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1") `
          -RepoRoot $repo.Path `
          -Target $target `
          -Lane emergency `
          -OutputRoot $output `
          -Repetitions $repetitions `
          -Check:($verb -eq "check-local-beta")
      }
      { $_ -in @("build-local-playtest", "check-local-playtest") } {
        $targetInput = Get-MIRArgValue -Items $Args -Name "--target" -Default "all"
        $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
        if ($target -notin @('all', 'f200', 'f110', 'f100')) {
          throw "--target must be one of all, F200, F110, or F100 for the private local-playtest lane."
        }
        $explicitOutput = Get-MIRArgValue -Items $Args -Name "--output"
        if (-not [string]::IsNullOrWhiteSpace($explicitOutput) -and
            [string]$explicitOutput -cne 'build/mir4/local-playtest-shadow') {
          throw "The private local-playtest lane has the fixed output root build/mir4/local-playtest-shadow."
        }
        $repetitionsText = Get-MIRArgValue -Items $Args -Name "--repetitions" -Default "3"
        $repetitions = 0
        if (-not [int]::TryParse($repetitionsText, [ref]$repetitions) -or $repetitions -ne 3) {
          throw "--repetitions must be exactly 3 for the A/B/C bootstrap profile."
        }
        & (Join-Path $repo "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1") `
          -RepoRoot $repo.Path `
          -Target $target `
          -Lane local-playtest-shadow `
          -OutputRoot 'build/mir4/local-playtest-shadow' `
          -Repetitions $repetitions `
          -Check:($verb -eq "check-local-playtest")
      }
      { $_ -in @("build-historical-private", "check-historical-private") } {
        $targetInput = Get-MIRArgValue -Items $Args -Name "--target" -Default "all"
        $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
        if ($target -notin @('all','f018','f017','f016','f015','f014','f013')) {
          throw "--target must be one of all, F018, F017, F016, F015, F014, or F013."
        }
        & (Join-Path $repo "tools/commands/release/New-MIR4HistoricalPrivateCandidate.ps1") `
          -RepoRoot $repo.Path -Target $target -Repetitions 3 -Check:($verb -eq "check-historical-private")
      }
      { $_ -in @("build-m4c01-player-set", "check-m4c01-player-set") } {
        & (Join-Path $repo "tools/commands/release/New-MIR4M4C01PlayerCandidateSet.ps1") `
          -RepoRoot $repo.Path -Check:($verb -eq "check-m4c01-player-set")
      }
      "runtime-historical-private" {
        $target = ConvertTo-MIR4LegacyTargetKey -Target (Get-MIRArgValue -Items $Args -Name "--target")
        if ($target -notin @('f017','f016','f015','f014','f013')) {
          throw "--target must be one of F017, F016, F015, F014, or F013. F018 requires an explicitly admitted exact engine."
        }
        $runtimeArguments = @{ RepoRoot = $repo.Path; Target = $target }
        $factorioBin = Get-MIRArgValue -Items $Args -Name "--factorio-bin"
        $candidate = Get-MIRArgValue -Items $Args -Name "--candidate"
        $evidence = Get-MIRArgValue -Items $Args -Name "--evidence"
        if (-not [string]::IsNullOrWhiteSpace($factorioBin)) { $runtimeArguments.FactorioBin = $factorioBin }
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $runtimeArguments.CandidateZip = $candidate }
        if (-not [string]::IsNullOrWhiteSpace($evidence)) { $runtimeArguments.EvidenceRoot = $evidence }
        & (Join-Path $repo "validation/tests/runtime/Test-MIR4HistoricalPrivateRuntime.ps1") @runtimeArguments
      }
      { $_ -in @("api", "sdk") } {
        if ($Args.Count -lt 3) { throw "mir4 $verb requires a subcommand." }
        $subcommand = [string]$Args[2]
        $allowed = if ($verb -eq "api") { @("check", "conformance") } else { @("generate", "check") }
        if ($subcommand -notin $allowed) { throw "Unknown mir4 $verb command: $subcommand" }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ExperimentalApi.ps1") -Command "$verb-$subcommand" -RepoRoot $repo.Path
      }
      "platform" {
        if ($Args.Count -lt 3) { throw "mir4 platform requires a subcommand." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('generate','check','conformance','package','compile')) {
          throw "Unknown mir4 platform command: $subcommand"
        }
        $platformArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        if ($subcommand -eq 'compile') {
          $platformArguments.Target = ConvertTo-MIR4LegacyTargetKey -Target (Get-MIRArgValue -Items $Args -Name '--target')
          $platformArguments.ExtensionPath = Get-MIRArgValue -Items $Args -Name '--extension'
          $platformArguments.OutputPath = Get-MIRArgValue -Items $Args -Name '--output'
        }
        & (Join-Path $repo "tools/commands/mir4/Invoke-MIR4PlatformPreview.ps1") @platformArguments
      }
      "environment-evidence" {
        if ($Args.Count -lt 3) { throw "mir4 environment-evidence requires lock, diff, bundle, minimize, verify, or reference." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('lock','diff','bundle','minimize','verify','reference')) { throw "Unknown mir4 environment-evidence command: $subcommand" }
        $environmentArguments = @{Mode=$subcommand;RepoRoot=$repo.Path}
        $inputValue = Get-MIRArgValue -Items $Args -Name '--input'
        $otherValue = Get-MIRArgValue -Items $Args -Name '--other'
        $outputValue = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($inputValue)) { $environmentArguments.InputPath = $inputValue }
        if (-not [string]::IsNullOrWhiteSpace($otherValue)) { $environmentArguments.OtherPath = $otherValue }
        if (-not [string]::IsNullOrWhiteSpace($outputValue)) { $environmentArguments.OutputPath = $outputValue }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4EnvironmentEvidence.ps1") @environmentArguments
      }
      "assurance-scale" {
        if ($Args.Count -lt 3) { throw "mir4 assurance-scale requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 assurance-scale command: $subcommand" }
        $assuranceArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $assuranceArguments.OutputRoot = $output }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4AssuranceScaleRecords.ps1") @assuranceArguments
      }
      "release-governance" {
        if ($Args.Count -lt 3) { throw "mir4 release-governance requires check or initialize." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','initialize')) { throw "Unknown mir4 release-governance command: $subcommand" }
        $governanceArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $governanceArguments.OutputPath = $output }
        & (Join-Path $repo "tools/commands/mir4/Invoke-MIR4ReleaseGovernance.ps1") @governanceArguments
      }
      "repository" {
        if ($Args.Count -lt 3) { throw "mir4 repository requires generate, check, inventory, or initialize." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('generate','check','inventory','initialize')) { throw "Unknown mir4 repository command: $subcommand" }
        $repositoryArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $repositoryArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1") @repositoryArguments
      }
      "canonicalization-migration" {
        if ($Args.Count -lt 3) { throw "mir4 canonicalization-migration requires generate, check, or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('generate','check','show')) { throw "Unknown mir4 canonicalization-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1") @migrationArguments
      }
      "diagnostics-migration" {
        if ($Args.Count -lt 3) { throw "mir4 diagnostics-migration requires generate, check, or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('generate','check','show')) { throw "Unknown mir4 diagnostics-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4DiagnosticsMigration.ps1") @migrationArguments
      }
      "target-key-migration" {
        if ($Args.Count -lt 3) { throw "mir4 target-key-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 target-key-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4TargetKeyMigration.ps1") @migrationArguments
      }
      "whole-platform-migration" {
        if ($Args.Count -lt 3) { throw "mir4 whole-platform-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 whole-platform-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4WholePlatformMigration.ps1") @migrationArguments
      }
      "technology-acceptance-migration" {
        if ($Args.Count -lt 3) { throw "mir4 technology-acceptance-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 technology-acceptance-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1") @migrationArguments
      }
      "target-compiler-migration" {
        if ($Args.Count -lt 3) { throw "mir4 target-compiler-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 target-compiler-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1") @migrationArguments
      }
      "semantic-compiler-policy-migration" {
        if ($Args.Count -lt 3) { throw "mir4 semantic-compiler-policy-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 semantic-compiler-policy-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1") @migrationArguments
      }
      "runtime-continuity-migration" {
        if ($Args.Count -lt 3) { throw "mir4 runtime-continuity-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 runtime-continuity-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4RuntimeContinuityMigration.ps1") @migrationArguments
      }
      "module-sdk-mep-migration" {
        if ($Args.Count -lt 3) { throw "mir4 module-sdk-mep-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 module-sdk-mep-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ModuleSdkMepMigration.ps1") @migrationArguments
      }
      "processir-exact-migration" {
        if ($Args.Count -lt 3) { throw "mir4 processir-exact-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 processir-exact-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ProcessIRExactMigration.ps1") @migrationArguments
      }
      "inspector-compatibility-migration" {
        if ($Args.Count -lt 3) { throw "mir4 inspector-compatibility-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 inspector-compatibility-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4InspectorCompatibilityMigration.ps1") @migrationArguments
      }
      "assurance-offline-custody-migration" {
        if ($Args.Count -lt 3) { throw "mir4 assurance-offline-custody-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 assurance-offline-custody-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4AssuranceOfflineCustodyMigration.ps1") @migrationArguments
      }
      "historical-tooling-migration" {
        if ($Args.Count -lt 3) { throw "mir4 historical-tooling-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 historical-tooling-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1") @migrationArguments
      }
      "release-tooling-migration" {
        if ($Args.Count -lt 3) { throw "mir4 release-tooling-migration requires check or show." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('check','show')) { throw "Unknown mir4 release-tooling-migration command: $subcommand" }
        $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1") @migrationArguments
      }
      "historical-succession" {
        if ($Args.Count -lt 3) { throw "mir4 historical-succession requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 historical-succession command: $subcommand" }
        $historicalArguments = @{ RepoRoot=$repo.Path; Check=($subcommand -eq 'check') }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $historicalArguments.OutputRoot = $output }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1") @historicalArguments
      }
      "targets" {
        if ($Args.Count -lt 3) { throw "mir4 targets requires contracts, laws, build, or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('contracts','laws','build','check')) { throw "Unknown mir4 targets command: $subcommand" }
        if ($subcommand -in @('contracts','laws')) {
          . (Join-Path $repo "tools/lib/mir4/PlatformPreview.ps1")
          $record = if ($subcommand -eq 'contracts') { New-MIR4TargetContractSet -RepoRoot $repo.Path } else { Test-MIR4TargetProviderLaws -RepoRoot $repo.Path }
          $record | ConvertTo-Json -Depth 100
        } else {
          $targetInput = Get-MIRArgValue -Items $Args -Name '--target' -Default 'all'
          $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
          $targetArguments = @{RepoRoot=$repo.Path;Target=$target;Check=($subcommand -eq 'check')}
          $output = Get-MIRArgValue -Items $Args -Name '--output'
          if (-not [string]::IsNullOrWhiteSpace($output)) { $targetArguments.OutputRoot = $output }
          & (Join-Path $repo "tools/commands/mir4/New-MIR4TargetProductSet.ps1") @targetArguments
        }
      }
      "semantic" {
        if ($Args.Count -lt 3) { throw "mir4 semantic requires export, check, or laws." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check','laws')) { throw "Unknown mir4 semantic command: $subcommand" }
        if ($subcommand -eq 'laws') {
          . (Join-Path $repo "tools/lib/mir4/PlatformPreview.ps1")
          Test-MIR4SemanticMergeLaws -RepoRoot $repo.Path | ConvertTo-Json -Depth 100
        } else {
          $semanticArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
          $output = Get-MIRArgValue -Items $Args -Name '--output'
          if (-not [string]::IsNullOrWhiteSpace($output)) { $semanticArguments.OutputRoot = $output }
          & (Join-Path $repo "tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1") @semanticArguments
        }
      }
      "runtime-continuity" {
        if ($Args.Count -lt 3) { throw "mir4 runtime-continuity requires export, check, or laws." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check','laws')) { throw "Unknown mir4 runtime-continuity command: $subcommand" }
        if ($subcommand -eq 'laws') {
          . (Join-Path $repo "tools/lib/mir4/PlatformPreview.ps1")
          $runtime = New-MIR4RuntimeStateMatrix -RepoRoot $repo.Path -Providers $null -SourceIdentity $null
          $migration = New-MIR4MigrationGraphMatrix -RepoRoot $repo.Path -Providers $null -SourceIdentity $null
          [ordered]@{runtime=$runtime.registration_plan.law_results;migration=$migration.law_results;passed=([bool]$runtime.registration_plan.law_results.all_passed -and [bool]$migration.law_results.all_passed)} | ConvertTo-Json -Depth 20
        } else {
          $runtimeArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
          $output = Get-MIRArgValue -Items $Args -Name '--output'
          $candidate = Get-MIRArgValue -Items $Args -Name '--candidate'
          if (-not [string]::IsNullOrWhiteSpace($output)) { $runtimeArguments.OutputRoot = $output }
          if (-not [string]::IsNullOrWhiteSpace($candidate)) { $runtimeArguments.CandidateZip = $candidate }
          & (Join-Path $repo "tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1") @runtimeArguments
        }
      }
      "module-ecosystem" {
        if ($Args.Count -lt 3) { throw "mir4 module-ecosystem requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 module-ecosystem command: $subcommand" }
        $moduleArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        $candidate = Get-MIRArgValue -Items $Args -Name '--candidate'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $moduleArguments.OutputRoot = $output }
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $moduleArguments.CandidateZip = $candidate }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4ModuleEcosystemRecords.ps1") @moduleArguments
      }
      "processir-synthesis" {
        if ($Args.Count -lt 3) { throw "mir4 processir-synthesis requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 processir-synthesis command: $subcommand" }
        $processArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $processArguments.OutputRoot = $output }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1") @processArguments
      }
      "exact-processir" {
        if ($Args.Count -lt 3) { throw "mir4 exact-processir requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 exact-processir command: $subcommand" }
        $exactArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
        $captures = @(Get-MIRArgValues -Items $Args -Name '--capture')
        if ($captures.Count) { $exactArguments.CaptureId = $captures }
        $repetitionsText = Get-MIRArgValue -Items $Args -Name '--repetitions' -Default '2'
        $repetitions = 0
        if (-not [int]::TryParse($repetitionsText,[ref]$repetitions) -or $repetitions -lt 1 -or $repetitions -gt 4) { throw "--repetitions must be an integer from 1 through 4." }
        $exactArguments.Repetitions = $repetitions
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        $reference = Get-MIRArgValue -Items $Args -Name '--reference'
        if (-not [string]::IsNullOrWhiteSpace($output)) {
          if ($subcommand -eq 'check') { $exactArguments.ReferenceRoot = $output } else { $exactArguments.OutputRoot = $output }
        }
        if (-not [string]::IsNullOrWhiteSpace($reference)) { $exactArguments.ReferenceRoot = $reference }
        if (Test-MIRArgSwitch -Items $Args -Name '--publish-reference') {
          if ($subcommand -eq 'check') { throw "--publish-reference is valid only for exact-processir export." }
          $exactArguments.PublishReference = $true
        }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1") @exactArguments
      }
      "release-canaries" {
        if ($Args.Count -lt 3) { throw "mir4 release-canaries requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 release-canaries command: $subcommand" }
        $canaryArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
        foreach($binding in @(
          @{arg='--capture-root';parameter='CaptureRoot'},
          @{arg='--upgrade-root';parameter='UpgradeRoot'},
          @{arg='--output';parameter=$(if($subcommand -eq 'check'){'ReferenceRoot'}else{'OutputRoot'})},
          @{arg='--reference';parameter='ReferenceRoot'}
        )){
          $value=Get-MIRArgValue -Items $Args -Name $binding.arg
          if(-not[string]::IsNullOrWhiteSpace($value)){$canaryArguments[$binding.parameter]=$value}
        }
        if(Test-MIRArgSwitch -Items $Args -Name '--publish-reference'){
          if($subcommand -eq 'check'){throw "--publish-reference is valid only for release-canaries export."}
          $canaryArguments.PublishReference=$true
        }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4CompatibilityCanaryRecords.ps1") @canaryArguments
      }
      "inspector-compatibility" {
        if ($Args.Count -lt 3) { throw "mir4 inspector-compatibility requires export or check." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('export','check')) { throw "Unknown mir4 inspector-compatibility command: $subcommand" }
        $inspectorArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $inspectorArguments.OutputRoot = $output }
        & (Join-Path $repo "tools/mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1") @inspectorArguments
      }
      "whole-platform" {
        if ($Args.Count -lt 3) { throw "mir4 whole-platform requires generate, check, matrix, or target-key." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('generate','check','matrix','target-key')) { throw "Unknown mir4 whole-platform command: $subcommand" }
        $wholeArguments = @{Command=$subcommand;RepoRoot=$repo.Path}
        if ($subcommand -eq 'target-key') {
          $wholeArguments.Target = Get-MIRArgValue -Items $Args -Name '--target'
        }
        & (Join-Path $repo "tools/commands/mir4/Invoke-MIR4WholePlatform.ps1") @wholeArguments
      }
      "acceptance" {
        if ($Args.Count -lt 3 -or [string]$Args[2] -cne 'queue') { throw "mir4 acceptance requires queue." }
        $catalog = Get-MIRArgValue -Items $Args -Name '--catalog'
        $target = Get-MIRArgValue -Items $Args -Name '--target'
        $ecosystem = Get-MIRArgValue -Items $Args -Name '--ecosystem'
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        foreach ($required in @(@{name='--catalog';value=$catalog},@{name='--target';value=$target},@{name='--ecosystem';value=$ecosystem},@{name='--output';value=$output})) {
          if ([string]::IsNullOrWhiteSpace([string]$required.value)) { throw "mir4 acceptance queue requires $($required.name)." }
        }
        & (Join-Path $repo "tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1") -RepoRoot $repo.Path -CatalogPath $catalog -Target $target -Ecosystem $ecosystem -OutputPath $output
      }
      "extension" {
        if ($Args.Count -lt 3) { throw "mir4 extension requires init, validate, explain, test, package, migrate, doctor, lock, diff, ci-init, or discover." }
        $subcommand = [string]$Args[2]
        if ($subcommand -notin @('init','validate','explain','test','package','migrate','doctor','lock','diff','ci-init','discover')) { throw "Unknown mir4 extension command: $subcommand" }
        $builderArguments = @{Command=$subcommand;RepoRoot=$repo.Path}
        $extension = Get-MIRArgValue -Items $Args -Name '--extension'
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        $id = Get-MIRArgValue -Items $Args -Name '--id'
        $template = Get-MIRArgValue -Items $Args -Name '--template'
        $target = Get-MIRArgValue -Items $Args -Name '--target'
        $base = Get-MIRArgValue -Items $Args -Name '--base'
        $candidate = Get-MIRArgValue -Items $Args -Name '--candidate'
        $discovery = Get-MIRArgValue -Items $Args -Name '--discovery'
        if (-not [string]::IsNullOrWhiteSpace($extension)) { $builderArguments.ExtensionPath = $extension }
        if (-not [string]::IsNullOrWhiteSpace($output)) { $builderArguments.OutputRoot = $output }
        if (-not [string]::IsNullOrWhiteSpace($id)) { $builderArguments.ExtensionId = $id }
        if (-not [string]::IsNullOrWhiteSpace($template)) { $builderArguments.Template = $template }
        if (-not [string]::IsNullOrWhiteSpace($target)) { $builderArguments.Target = $target.ToLowerInvariant() }
        if (-not [string]::IsNullOrWhiteSpace($base)) { $builderArguments.BasePath = $base }
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $builderArguments.CandidatePath = $candidate }
        if (-not [string]::IsNullOrWhiteSpace($discovery)) { $builderArguments.DiscoveryPath = $discovery }
        & (Join-Path $repo "tools/mir/cli/Invoke-MIR4Extension.ps1") @builderArguments
      }
      "handoff-m4c01" {
        $output = Get-MIRArgValue -Items $Args -Name "--output" -Default "build/mir4/m4c01-handoff"
        & (Join-Path $repo "tools/commands/mir4/Export-MIR4M4C01Handoff.ps1") -RepoRoot $repo.Path -OutputRoot $output
      }
      default { throw "Unknown mir4 command: $verb" }
    }
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
        & (Join-Path $repoRoot "tools/commands/technology/New-MIRTechnologyQualityAssessment.ps1") @params
      }
      "review-dossier" {
        if ([string]::IsNullOrWhiteSpace($candidateId)) { throw "technology review-dossier requires --candidate." }
        $params = @{CatalogPath=$catalog; CandidateId=$candidateId; OutputPath=$output}
        $assessment = Get-MIRArgValue -Items $Args -Name "--assessment"
        if ($assessment) { $params.AssessmentPath = $assessment }
        & (Join-Path $repoRoot "tools/commands/technology/New-MIRTechnologyReviewDossier.ps1") @params
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
      "doctor" {
        $parameters = @{
          Command='release-doctor';RepoRoot=$repo.Path
          Json=(Test-MIRArgSwitch -Items $Args -Name '--json')
          DryRun=(Test-MIRArgSwitch -Items $Args -Name '--dry-run')
          Explain=(Test-MIRArgSwitch -Items $Args -Name '--explain')
        }
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $parameters.OutputPath = $output }
        & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1') @parameters
      }
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
  "playtest" {
    if ($verb -notin @('prepare','capture','finalize')) { throw "Unknown playtest command: $verb" }
    $parameters = @{
      Command=("playtest-" + $verb);RepoRoot=$repo.Path
      Json=(Test-MIRArgSwitch -Items $Args -Name '--json')
      DryRun=(Test-MIRArgSwitch -Items $Args -Name '--dry-run')
    }
    if ($verb -eq 'prepare') {
      $target = (Get-MIRArgValue -Items $Args -Name '--target' -Default 'F210').ToUpperInvariant()
      if ($target -notin @('F210','F200')) { throw 'playtest prepare --target must be F210 or F200.' }
      $parameters.Target = $target
      foreach ($binding in @(
        @{option='--candidate';parameter='CandidatePath'},
        @{option='--predecessor';parameter='PredecessorPath'},
        @{option='--factorio';parameter='FactorioBin'},
        @{option='--settings';parameter='SettingsPath'},
        @{option='--save';parameter='SavePath'},
        @{option='--output';parameter='SessionOutputRoot'}
      )) {
        $value = Get-MIRArgValue -Items $Args -Name $binding.option
        if (-not [string]::IsNullOrWhiteSpace($value)) { $parameters[$binding.parameter] = $value }
      }
    } else {
      $session = Get-MIRArgValue -Items $Args -Name '--session'
      if ([string]::IsNullOrWhiteSpace($session)) { throw "playtest $verb requires --session." }
      $parameters.SessionRoot = $session
      if ($verb -eq 'capture') {
        $parameters.CapturePath = @(Get-MIRArgValues -Items $Args -Name '--capture')
        $observations = Get-MIRArgValue -Items $Args -Name '--observations'
        if (-not [string]::IsNullOrWhiteSpace($observations)) { $parameters.ObservationsPath = $observations }
      } else {
        $decision = (Get-MIRArgValue -Items $Args -Name '--decision').ToUpperInvariant()
        $reviewer = Get-MIRArgValue -Items $Args -Name '--reviewer'
        if ($decision -notin @('ACCEPTED','CHANGES-REQUESTED','REJECTED') -or [string]::IsNullOrWhiteSpace($reviewer)) {
          throw 'playtest finalize requires an explicit --decision and --reviewer.'
        }
        $parameters.Decision = $decision
        $parameters.Reviewer = $reviewer
        $parameters.Notes = Get-MIRArgValue -Items $Args -Name '--notes'
      }
    }
    & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1') @parameters
  }
  "rulesets" {
    if ($verb -ne 'audit') { throw "Unknown rulesets command: $verb" }
    $parameters = @{Command='rulesets-audit';RepoRoot=$repo.Path;Json=(Test-MIRArgSwitch -Items $Args -Name '--json')}
    $output = Get-MIRArgValue -Items $Args -Name '--output'
    if (-not [string]::IsNullOrWhiteSpace($output)) { $parameters.OutputPath = $output }
    & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1') @parameters
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
    & (Join-Path $repo "tools/commands/package/Build-MIRPackage.ps1")
  }
  "backport" {
    $manifest = Get-MIRArgValue -Items $Args -Name "--manifest" -Default ".mir/releases/backports/2.5.0.json"
    switch ($verb) {
      "validate" {
        $params = @{RepoRoot=$repo.Path; ManifestPath=$manifest}
        if (Test-MIRArgSwitch -Items $Args -Name "--allow-pending-tags") { $params.AllowPendingTags = $true }
        & (Join-Path $scriptRoot "Test-MIRBackportManifest.ps1") @params
      }
      "materialize" {
        $worktree = Get-MIRArgValue -Items $Args -Name "--worktree"
        if ([string]::IsNullOrWhiteSpace($worktree)) { throw "backport materialize requires --worktree." }
        $params = @{RepoRoot=$repo.Path; ManifestPath=$manifest; Worktree=$worktree}
        foreach ($binding in @(
          @{Option="--source"; Parameter="Source"},
          @{Option="--baseline"; Parameter="Baseline"},
          @{Option="--target"; Parameter="Target"}
        )) {
          $value = Get-MIRArgValue -Items $Args -Name $binding.Option
          if ($value) { $params[$binding.Parameter] = $value }
        }
        $receipt = Get-MIRArgValue -Items $Args -Name "--receipt"
        if ($receipt) { $params.ReceiptPath = $receipt }
        if (Test-MIRArgSwitch -Items $Args -Name "--keep-worktree") { $params.KeepWorktree = $true }
        & (Join-Path $scriptRoot "Materialize-MIRBackport.ps1") @params
      }
      default { throw "Unknown backport command: $verb" }
    }
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
    & (Join-Path $repo "tools/commands/workspace/Remove-MIRStaleArtifacts.ps1") @params
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
    $output = Get-MIRArgValue -Items $Args -Name "--output" -Default (Join-Path $repo "build\results\legacy-inventory")
    $params = @{ OutputRoot = $output }
    if (Test-MIRArgSwitch -Items $Args -Name "--check") {
      $params.CheckThresholds = $true
    }
    & (Join-Path $repo "tools/commands/workspace/Get-MIRLegacyInventory.ps1") @params
  }
  "profile" {
    if ($verb -ne "stub") { throw "Unknown profile command: $verb" }
    if ($Args.Count -lt 3) { throw "profile stub requires a group id." }
    $groupId = $Args[2]
    $groupedFailures = Get-MIRArgValue -Items $Args -Name "--grouped-failures"
    if ([string]::IsNullOrWhiteSpace($groupedFailures)) { throw "--grouped-failures is required." }
    & (Join-Path $repo "tools/commands/compatibility/New-MIRCompatProfileStub.ps1") -GroupedFailures $groupedFailures -GroupId $groupId
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
