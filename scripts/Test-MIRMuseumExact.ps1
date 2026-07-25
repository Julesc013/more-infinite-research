param(
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6", "all")]
  [string]$FactorioVersion = "all",
  [string]$InstallationRoot = "",
  [string]$RegistryPath = "",
  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force
$catalog = Get-MIRMuseumCatalog -Path (Join-Path $repo ".mir\museum-targets.json")
$selected = if ($FactorioVersion -eq "all") { @($catalog.targets) } else { @(Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion $FactorioVersion) }
if ($selected.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($InstallationRoot)) {
  throw "-InstallationRoot identifies one installation; use a registry or MIR_MUSEUM_ROOT when validating all museum targets."
}

$results = @()
foreach ($target in $selected) {
  $targetRoot = if ($selected.Count -eq 1) { $InstallationRoot } else { "" }
  $installation = Resolve-MIRMuseumInstallation -Target $target -RepoRoot $repo -InstallationRoot $targetRoot -RegistryPath $RegistryPath
  $package = New-MIRMuseumPackage -Catalog $catalog -Target $target -RepoRoot $repo -OutputDir "build\museum-exact\packages"
  $runtimeJson = & (Join-Path $PSScriptRoot "Test-MIRMuseumRuntime.ps1") `
    -FactorioVersion ([string]$target.factorio) `
    -PackageMode zip `
    -Reload `
    -PackagePath ([string]$package.path) `
    -InstallationRoot ([string]$installation.root) `
    -TimeoutSeconds $TimeoutSeconds | Out-String
  $runtime = $runtimeJson | ConvertFrom-Json
  if ([string]$runtime.status -ne "passed") { throw "Exact museum runtime did not pass for Factorio $($target.factorio)." }

  $results += [pscustomobject][ordered]@{
    target = [string]$target.factorio
    installation_id = [string]$target.installation_id
    binary_sha256 = [string]$runtime.binary_sha256
    base_data_sha256 = [string]$runtime.base_data_sha256
    package_sha256 = [string]$package.sha256
    package_content_sha256 = [string]$package.package_content_sha256
    runtime_status = [string]$runtime.status
  }
}

[pscustomobject][ordered]@{
  schema = 1
  kind = "mir-museum-exact-runtime-summary"
  status = "passed"
  targets = $results
} | ConvertTo-Json -Depth 20
