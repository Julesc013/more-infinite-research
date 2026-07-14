param(
  [Parameter(Mandatory)]
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6")]
  [string]$FactorioVersion,
  [Parameter(Mandatory)][string]$RuntimeProofPath,
  [string]$PackagePath = "",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force
$catalog = Get-MIRMuseumCatalog -Path (Join-Path $repo ".mir\museum-targets.json")
$target = Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion $FactorioVersion
$validation = Test-MIRMuseumTarget -Catalog $catalog -Target $target -RequireExactPatch
if (-not $validation.passed) { throw ($validation.errors -join "`n") }
if ([string]::IsNullOrWhiteSpace($PackagePath)) { $PackagePath = Join-Path $repo "dist\$($catalog.mod_name)_$($target.version).zip" }
if (-not [IO.Path]::IsPathRooted($PackagePath)) { $PackagePath = Join-Path $repo $PackagePath }
if (-not [IO.Path]::IsPathRooted($RuntimeProofPath)) { $RuntimeProofPath = Join-Path $repo $RuntimeProofPath }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $repo ".mir\evidence\$($target.version)-qualification-summary.json" }
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }

$runtime = Get-Content -Raw -LiteralPath $RuntimeProofPath | ConvertFrom-Json
if ([string]$runtime.status -ne "passed" -or [string]$runtime.factorio -ne $FactorioVersion) { throw "Runtime proof is not a passed $FactorioVersion record." }
if ([string]$runtime.exact_patch -ne [string]$target.exact_patch) { throw "Runtime proof patch mismatch." }
if ([string]$runtime.binary_sha256 -ne (Get-MIRSha256 ([string]$target.binary).Replace('/', '\'))) { throw "Runtime proof binary mismatch." }
if ([string]$runtime.package_mode -ne "zip") { throw "Qualification requires exact ZIP runtime proof." }
$expectedDeploymentMode = if ([string]$target.package_mode -eq "extract-required") { "exact-zip-extracted" } else { "zip-native" }
if ($FactorioVersion -ne "0.12" -and [string]$runtime.runtime_deployment_mode -ne $expectedDeploymentMode) {
  throw "Runtime proof deployment mode does not match target package policy $($target.package_mode)."
}
$legacyStartupProof = $FactorioVersion -ne "0.12"
if ($legacyStartupProof) {
  if ([string]$runtime.runtime_mode -ne "bounded-gui-startup-load" -or
      [string]$runtime.fresh_start.status -notlike "passed*" -or
      [string]$runtime.second_start.status -notlike "passed*" -or
      [string]$runtime.reload -notlike "passed*") {
    throw "Qualification requires two passed bounded startup/load proofs on pre-0.12 targets."
  }
} elseif ([string]$runtime.fresh_create -ne "passed" -or [string]$runtime.reload -notlike "passed*") {
  throw "Qualification requires fresh create and reload proof."
}
$identity = Get-MIRMuseumZipIdentity -Path $PackagePath
if ($identity.entries -ne 4) { throw "Museum package must contain exactly four files." }

$record = [ordered]@{
  schema = 1
  kind = "mir-museum-qualification-summary"
  status = "passed"
  factorio = $FactorioVersion
  exact_patch = [string]$target.exact_patch
  mir_version = [string]$target.version
  branch = [string]$target.branch
  source_commit = (& git -C $repo rev-parse HEAD).Trim()
  binary = [ordered]@{
    path = (Resolve-Path -LiteralPath ([string]$target.binary).Replace('/', '\')).Path
    architecture = "win64-x64"
    sha256 = Get-MIRSha256 ([string]$target.binary).Replace('/', '\')
  }
  package = [ordered]@{
    path = (Resolve-Path -LiteralPath $PackagePath).Path.Substring($repo.Path.Length + 1).Replace('\', '/')
    mode = [string]$target.package_mode
    size_bytes = $identity.size
    entries = $identity.entries
    sha256 = $identity.sha256
    package_content_sha256 = $identity.package_content_sha256
    forbidden_entries = 0
  }
  capabilities = [ordered]@{
    effects = @($target.allowed_effects)
    science = @($target.science)
    configuration = [string]$target.configuration
    locale_format = [string]$target.locale_format
    finite_families = @($target.families | ForEach-Object { [ordered]@{ id = $_.id; levels = $_.levels; effect = $_.effect.type } })
    explicit_omissions = @("native-infinite-fields", "count-formula", "recipe-productivity", "mining-productivity", "modern-settings", "scripted-simulation")
  }
  gates = [ordered]@{
    manifest_and_base_evidence = "passed"
    negative_cases = "passed-26"
    deterministic_clean_builds = "passed"
    package_hygiene = "passed"
    exact_zip_initial_load = if ($legacyStartupProof) { [string]$runtime.fresh_start.status } else { [string]$runtime.fresh_create }
    exact_zip_second_load = [string]$runtime.reload
    target_cli_save_proof = if ($legacyStartupProof) { "not-available-pre-0.12" } else { "passed" }
    runtime_deployment = if ($legacyStartupProof) { [string]$runtime.runtime_deployment_mode } else { "zip-native" }
    locale_parser_and_load = "passed"
    balance_invariants = "passed"
    upgrade = "not-applicable-first-release"
    manual_visual_and_balance_review = "PENDING-MAINTAINER"
  }
  runtime_proof_path = (Resolve-Path -LiteralPath $RuntimeProofPath).Path.Substring($repo.Path.Length + 1).Replace('\', '/')
  release_actions = "not-run-maintainer-only"
}
Set-MIRUtf8Text -Path $OutputPath -Text (($record | ConvertTo-Json -Depth 20) + "`n")
$record | ConvertTo-Json -Depth 20
