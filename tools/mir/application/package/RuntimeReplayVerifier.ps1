param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
  [Parameter(Mandatory)][string]$EvidenceRoot,
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$evidence = (Resolve-Path -LiteralPath $EvidenceRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $evidence 'independent-verification.json' }
elseif (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path $repo $OutputPath }
function Require-MIR4F2D([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
function Read-MIR4F2D([string]$Name) {
  $path = Join-Path $evidence $Name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-f2d-missing] $Name" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

$proof = Read-MIR4F2D 'target-proof.json'
$fresh = Read-MIR4F2D 'fresh-load-result.json'
$upgrade = Read-MIR4F2D 'upgrade-matrix.json'
$custody = Read-MIR4F2D 'custody-precleanup.json'
. (Join-Path $repo 'tools/lib/validation/FactorioVersionPolicy.ps1')
$golden = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/distribution/mir4-golden-four-target-baseline-v1.json') | ConvertFrom-Json
$baseline = @($golden.targets | Where-Object target -eq $Target)
Require-MIR4F2D ($baseline.Count -eq 1) 'mir4-f2d-baseline'
$code = $Target.Substring(1)
Require-MIR4F2D ([string]$proof.status -eq "M41-F2D-$code-PASSED-NO-CUTOVER") 'mir4-f2d-status'
Require-MIR4F2D ([string]$proof.package.content_sha256 -eq [string]$baseline[0].archive.content_sha256 -and [int]$proof.package.entry_count -eq [int]$baseline[0].archive.entry_count) 'mir4-f2d-package-identity'
Require-MIR4F2D ([string]$fresh.status -eq 'passed' -and [string]$fresh.validation_package_sha256 -eq [string]$proof.package.archive_sha256 -and [string]$fresh.validation_package_content_sha256 -eq [string]$proof.package.content_sha256) 'mir4-f2d-fresh-load'
Require-MIR4F2D ([string]$fresh.factorio_version -eq [string]$proof.engine.version -and [string]$fresh.factorio_binary_sha256 -eq [string]$proof.engine.binary_sha256) 'mir4-f2d-fresh-engine-identity'
if ($Target -ne 'f210') {
  Require-MIR4F2D (Test-MIR4FixedFactorioEngineIdentity -Target $Target -ObservedIdentity $proof.engine -RepoRoot $repo) 'mir4-f2d-fixed-engine-lock'
}
Require-MIR4F2D ([string]$upgrade.status -eq 'passed' -and [string]$upgrade.factorio.binary_sha256 -eq [string]$proof.engine.binary_sha256 -and [string]$upgrade.candidate.archive_sha256 -eq [string]$proof.package.archive_sha256 -and [string]$upgrade.baseline.archive_sha256 -eq [string]$proof.predecessor.archive_sha256) 'mir4-f2d-upgrade-identity'
$expectedArchetypes = if ($Target -eq 'f210') { @('base-default','space-age-native-owner','automatic-family-creation','base-continuations','mod-set-configuration-change') } else { @('base-default') }
Require-MIR4F2D (@(Compare-Object -ReferenceObject @($expectedArchetypes|Sort-Object) -DifferenceObject @(@($upgrade.required_archetypes)|Sort-Object)).Count -eq 0) 'mir4-f2d-archetypes'
Require-MIR4F2D (@($upgrade.rows | Where-Object { [string]$_.status -ne 'passed' -or [string]$_.expanded_root_disposition -notin @('removed','retained') }).Count -eq 0) 'mir4-f2d-upgrade-rows'
foreach ($name in @('package_cutover','old_writer_retirement','version_allocation','tagging','signing','sealing','publication')) { Require-MIR4F2D (-not [bool]$proof.transition_gates.$name) "mir4-f2d-gate-$name" }
foreach ($row in @($custody.files)) {
  $path = Join-Path $evidence ([string]$row.path)
  Require-MIR4F2D ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq [string]$row.sha256 -and (Get-Item -LiteralPath $path).Length -eq [int64]$row.bytes) "mir4-f2d-custody-$([string]$row.path)"
}
$absolutePathLeaks = @()
foreach ($file in @(Get-ChildItem -LiteralPath $evidence -File | Where-Object Extension -in @('.json','.txt','.log'))) {
  if ((Get-Content -Raw -LiteralPath $file.FullName) -match '(?i)[A-Z]:[\\/]') { $absolutePathLeaks += $file.Name }
}
Require-MIR4F2D ($absolutePathLeaks.Count -eq 0) 'mir4-f2d-absolute-path-redaction'
$result = [ordered]@{schema=1;kind='MIR4F2DIndependentVerificationV1';status='passed';target=$Target;proof_status=[string]$proof.status;package_content_sha256=[string]$proof.package.content_sha256;engine_version=[string]$proof.engine.version;engine_binary_sha256=[string]$proof.engine.binary_sha256;fresh_scenarios=@($fresh.scenarios).Count;upgrade_archetypes=@($upgrade.required_archetypes);custody_files=@($custody.files).Count;transition_gates=$proof.transition_gates}
$schema = Join-Path $repo 'spec/schemas/mir4-f2d-runtime-replay-evidence-v1.schema.json'
Require-MIR4F2D (($result | ConvertTo-Json -Depth 20) | Test-Json -SchemaFile $schema) 'mir4-f2d-independent-schema'
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }
[IO.File]::WriteAllText($resolvedOutput,(($result|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
Write-Host "[ok] independent F2D verifier: $OutputPath"
