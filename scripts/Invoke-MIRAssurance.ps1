param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configPath = Join-Path $repo ".mir\assurance.json"
$catalogPath = Join-Path $repo ".mir\test-catalog.json"
$impactPath = Join-Path $repo ".mir\test-impact.yml"
$targetsPath = Join-Path $repo ".mir\targets.json"
$scenarioRegistryPath = Join-Path $repo "fixtures\compat-matrix\expected-scenarios.json"
$artifactRoot = Join-Path $repo "artifacts\assurance"
$evidenceRoot = Join-Path $artifactRoot "evidence"
$buildRoot = Join-Path $artifactRoot "builds"
$evidenceSchema = 2
$buildReceiptSchema = 2
$assuranceRunnerVersion = "2"

. (Join-Path $PSScriptRoot "MIRAssurance\Core.ps1")
. (Join-Path $PSScriptRoot "MIRAssurance\Evidence.ps1")
. (Join-Path $PSScriptRoot "MIRAssurance\Release.ps1")

function Get-MIRAssuranceFactorioVersion {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  $version = [string]$item.VersionInfo.FileVersion
  if ([string]::IsNullOrWhiteSpace($version)) { $version = [string]$item.VersionInfo.ProductVersion }
  if ([string]::IsNullOrWhiteSpace($version)) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Path
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    [void]$start.ArgumentList.Add("--version")
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
      [void]$process.Start()
      $versionText = $process.StandardOutput.ReadToEnd() + "`n" + $process.StandardError.ReadToEnd()
      $process.WaitForExit()
      if ($process.ExitCode -eq 0 -and $versionText -match '(?m)^Version:\s+([0-9]+(?:\.[0-9]+)+)') { $version = $Matches[1] }
    } finally { $process.Dispose() }
  }
  if ([string]::IsNullOrWhiteSpace($version)) {
    $observedSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
    if ($observedSha256 -eq "B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1") { $version = "1.1.110" }
  }
  if ([string]::IsNullOrWhiteSpace($version)) { $version = "unknown" }
  return $version.Trim()
}

function Show-MIRAssuranceHelp {
  Write-Host @"
MIR assurance

Commands:
  doctor | inventory | impact | plan | build | verify | qualify
  seal | check-seal | locale | balance | backport | explain | self-test

Common options:
  --target <line> --candidate <zip> --baseline <ref-or-seal>
  --profile <name> --factorio <path> --prior <zip> --seal <path>
  --output <json> --json --rerun <test-id> --no-reuse

Reuse is enabled by default. Passing evidence is reused only when the exact per-test
fingerprint still matches. Failed or blocked lanes execute again; --rerun forces one
lane and --no-reuse forces every selected lane.
"@
}

$context = Get-MIRAssuranceContext
$command = if ($Args.Count -gt 0) { [string]$Args[0] } else { "help" }
switch ($command) {
  "help" { Show-MIRAssuranceHelp }
  "doctor" {
    $gitVersion = (& git --version).Trim()
    $factorioExists = $context.factorio -and (Test-Path -LiteralPath $context.factorio -PathType Leaf)
    $factorioVersion = if ($factorioExists) { Get-MIRAssuranceFactorioVersion -Path $context.factorio } else { "not-provided" }
    $factorioMatchesTarget = if ($factorioExists) { $factorioVersion -match ("^" + [regex]::Escape([string]$context.target) + "\.") } else { $true }
    if (-not $factorioMatchesTarget) { throw "Factorio binary version '$factorioVersion' does not match target '$($context.target)'." }
    $result = [ordered]@{
      schema=2
      status="passed"
      powershell=$PSVersionTable.PSVersion.ToString()
      git=$gitVersion
      repo=$repo
      target=$context.target
      info_version=[string]$context.info.version
      config_exists=(Test-Path -LiteralPath $configPath -PathType Leaf)
      catalog_exists=(Test-Path -LiteralPath $catalogPath -PathType Leaf)
      factorio=if ($factorioExists) { $context.factorio } else { "not-provided" }
      factorio_version=$factorioVersion
      factorio_matches_target=$factorioMatchesTarget
      prior_release=if ($context.prior_release -and (Test-Path -LiteralPath $context.prior_release -PathType Leaf)) { $context.prior_release } else { "not-provided" }
      evidence_reuse_enabled=[bool]$context.reuse_enabled
      evidence_root=$evidenceRoot
    }
    Write-MIRAssuranceJson -Value $result
  }
  "inventory" {
    $zips = @(Get-ChildItem -LiteralPath (Join-Path $repo "dist") -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
      [ordered]@{path=(Get-MIRAssuranceRepoRelativePath -Path $_.FullName); size_bytes=$_.Length; sha256=(Get-MIRAssuranceSha256 -Path $_.FullName)}
    })
    $result = [ordered]@{
      schema=2
      head=(& git -C $repo rev-parse HEAD).Trim()
      branch=([string](& git -C $repo branch --show-current)).Trim()
      tags=@(& git -C $repo tag --list --sort=refname)
      worktree_status=@(& git -C $repo status --short)
      distributions=$zips
      evidence_capsules=@(Get-ChildItem -LiteralPath $evidenceRoot -Recurse -Filter passed.json -File -ErrorAction SilentlyContinue).Count
      build_receipts=@(Get-ChildItem -LiteralPath $buildRoot -Filter *.json -File -ErrorAction SilentlyContinue).Count
    }
    Write-MIRAssuranceJson -Value $result
  }
  "impact" { Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context).classification }
  "plan" { Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context) -DefaultPath "artifacts/assurance/plan.json" }
  "explain" { Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context) }
  "build" { Write-MIRAssuranceJson -Value (Invoke-MIRAssuranceBuild -Context $context) }
  "verify" {
    $plan = Get-MIRAssurancePlan -Context $context
    $results = Invoke-MIRAssurancePlan -Plan $plan -Context $context
    $counts = Get-MIRAssuranceResultCounts -Results $results
    $status = if ($counts.failed -eq 0) { "passed" } else { "failed" }
    $summary = [ordered]@{
      schema=2
      status=$status
      target=$context.target
      candidate=$context.candidate
      plan=$plan
      counts=$counts
      evidence=$results
      completed_at=(Get-Date).ToUniversalTime().ToString("o")
    }
    Write-MIRAssuranceJson -Value $summary -DefaultPath "artifacts/assurance/verify-summary.json"
    if ($status -ne "passed") { throw "Assurance verification failed." }
  }
  "qualify" {
    $build = Invoke-MIRAssuranceBuild -Context $context
    $profile = Get-MIRAssuranceOption -Name "--profile" -Default "full"
    if (-not (Get-MIRAssuranceOption -Name "--profile")) { $script:Args += @("--profile", $profile) }
    $plan = Get-MIRAssurancePlan -Context $context
    $results = Invoke-MIRAssurancePlan -Plan $plan -Context $context
    $counts = Get-MIRAssuranceResultCounts -Results $results
    $status = if ($counts.failed -eq 0) { "passed" } else { "failed" }
    $summary = [ordered]@{
      schema=2
      status=$status
      state=if ($status -eq "passed") { "RUNTIME-QUALIFIED" } else { "BUILT" }
      release_status="NOT RELEASED"
      target=$context.target
      version=[string]$context.info.version
      source_commit=(& git -C $repo rev-parse HEAD).Trim()
      build=$build
      plan=$plan
      counts=$counts
      evidence=$results
      completed_at=(Get-Date).ToUniversalTime().ToString("o")
    }
    Write-MIRAssuranceJson -Value $summary -DefaultPath "artifacts/assurance/qualification-summary.json"
    if ($status -ne "passed") { throw "Assurance qualification failed." }
  }
  "seal" { Invoke-MIRAssuranceSeal -Context $context }
  "check-seal" { Invoke-MIRAssuranceCheckSeal -Context $context }
  "locale" {
    & (Join-Path $repo "scripts\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
    if ($LASTEXITCODE -ne 0) { throw "Locale assurance failed." }
  }
  "balance" {
    if ([string]$context.info.factorio_version -in @("2.0", "2.1")) {
      & (Join-Path $repo "scripts\Test-MIRNativeOwnerCostModels.ps1") -RepoRoot $repo
    } else {
      & (Join-Path $repo "scripts\Test-MIRResearchCostModels.ps1") -RepoRoot $repo
    }
    if ($LASTEXITCODE -ne 0) { throw "Target balance contract validation failed." }
    $snapshot = [ordered]@{
      schema=1
      target=[string]$context.info.factorio_version
      version=[string]$context.info.version
      streams_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo ".mir\streams.yml"))
      generated_stream_manifest_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "prototypes\mir\streams\generated_stream_manifest.json"))
      settings_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo ".mir\settings.yml"))
      planner_costs_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "prototypes\mir\planner\costs.lua"))
      native_owner_cost_models_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo ".mir\native-owner-cost-models.json"))
      native_owner_contract_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "prototypes\mir\domain\native_owner\contract.lua"))
      native_owner_formula_adapter_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "prototypes\mir\domain\native_owner\cost_model.lua"))
      native_owner_binding_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "prototypes\mir\planner\native_owner_binding.lua"))
    }
    $snapshot.fingerprint = Get-MIRAssuranceTextHash -Text (($snapshot.Values | ForEach-Object { [string]$_ }) -join "`n")
    Write-MIRAssuranceJson -Value $snapshot -DefaultPath "artifacts/assurance/balance-snapshot.json"
  }
  "backport" {
    if (-not (Get-MIRAssuranceOption -Name "--profile")) { $script:Args += @("--profile", "backport") }
    Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context) -DefaultPath "artifacts/assurance/backport-plan.json"
  }
  "self-test" { Invoke-MIRAssuranceSelfTest -Context $context }
  default { throw "Unknown assurance command: $command" }
}
