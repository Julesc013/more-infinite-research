param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test

$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\assurance.json") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\test-catalog.json") | ConvertFrom-Json
if ([int]$config.schema -ne 1 -or [int]$catalog.schema -ne 1) { throw "Unsupported assurance manifest schema." }

$ids = @($catalog.tests | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate assurance test IDs: $($duplicates.Name -join ', ')" }

foreach ($required in @("static.full", "runtime.affected", "runtime.full", "runtime.upgrade", "runtime.exact-zip", "seal.verify")) {
  if ($ids -notcontains $required) { throw "Missing release-blocking assurance test ID: $required" }
}

foreach ($profile in $config.profiles.PSObject.Properties) {
  foreach ($testId in @($profile.Value)) {
    if ($ids -notcontains [string]$testId) { throw "Profile '$($profile.Name)' references unknown test ID '$testId'." }
  }
}

foreach ($test in @($catalog.tests)) {
  if ([string]::IsNullOrWhiteSpace([string]$test.command)) { throw "Assurance test '$($test.id)' has no command." }
  $inputs = @($test.inputs | ForEach-Object { [string]$_ })
  if ($inputs.Count -eq 0) { throw "Assurance test '$($test.id)' has no declared inputs." }
  if (@($inputs | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw "Assurance test '$($test.id)' has an empty input declaration." }
  $duplicateInputs = @($inputs | Group-Object | Where-Object Count -gt 1)
  if ($duplicateInputs.Count -gt 0) { throw "Assurance test '$($test.id)' has duplicate inputs: $($duplicateInputs.Name -join ', ')" }
}

$runtimeTests = @($catalog.tests | Where-Object { [string]$_.kind -eq "runtime" })
foreach ($test in $runtimeTests) {
  $inputs = @($test.inputs | ForEach-Object { [string]$_ })
  foreach ($requiredInput in @("candidate", "package-source", "factorio")) {
    if ($inputs -notcontains $requiredInput) { throw "Runtime test '$($test.id)' must fingerprint '$requiredInput'." }
  }
}

$affected = $catalog.tests | Where-Object { [string]$_.id -eq "runtime.affected" } | Select-Object -First 1
if ([string]$affected.command -notmatch "-ChangedSince\s+<baseline>") { throw "runtime.affected must propagate the assurance baseline." }
if ([string]$affected.command -notmatch "-CandidateZip\s+<candidate>") { throw "runtime.affected must validate the exact candidate ZIP." }

$full = $catalog.tests | Where-Object { [string]$_.id -eq "runtime.full" } | Select-Object -First 1
if ([string]$full.command -notmatch "-CandidateZip\s+<candidate>") { throw "runtime.full must validate the exact candidate ZIP." }

$gitIgnore = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".gitignore")
if ($gitIgnore -notmatch "(?m)^/artifacts/") { throw "Content-addressed assurance evidence must remain excluded from commits." }

foreach ($module in @("Core.ps1", "Hashing.ps1", "Evidence.ps1", "Release.ps1")) {
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot "scripts\MIRAssurance\$module") -PathType Leaf)) {
    throw "Missing assurance module: $module"
  }
}

Write-Host "[ok] MIR assurance manifests, stable IDs, exact-candidate runtime commands, portable hashes, and input declarations passed."
