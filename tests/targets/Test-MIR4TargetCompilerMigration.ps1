param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/targets/TargetCompilerMigration.ps1')

$receipt=Invoke-MIR4TargetCompilerMigrationProjectionV1 -RepoRoot $repo -Check
if([string]$receipt.migration_id-cne'MIR4-TARGET-COMPILER-TOOLING-V1'){throw '[mir4-target-compiler-historical-migration-id]'}
if((Get-FileHash -LiteralPath (Join-Path $repo $script:MIR4TargetCompilerMigrationReceiptPath) -Algorithm SHA256).Hash-cne$script:MIR4TargetCompilerMigrationReceiptSha256){throw '[mir4-target-compiler-historical-migration-bytes]'}
try{Invoke-MIR4TargetCompilerMigrationProjectionV1 -RepoRoot $repo|Out-Null;throw '[mir4-target-compiler-historical-migration-write-enabled]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-target-compiler-migration-receipt-immutable]')){throw}}

function Invoke-MIR4TargetCompilerHistoricalCommandProbeV1 {
  param([Parameter(Mandatory)][ValidateSet('check','show')][string]$Command)
  $output=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1') -Command $Command -RepoRoot $repo 2>&1|Out-String).Trim()
  if($LASTEXITCODE-ne0){throw "[mir4-target-compiler-historical-migration-cli] $Command $output"}
  return $output|ConvertFrom-Json -Depth 100
}
$check=Invoke-MIR4TargetCompilerHistoricalCommandProbeV1 check
$show=Invoke-MIR4TargetCompilerHistoricalCommandProbeV1 show
if((ConvertTo-MIR4CanonicalJsonV1 $check)-cne(ConvertTo-MIR4CanonicalJsonV1 $show)){throw '[mir4-target-compiler-historical-migration-cli-parity]'}
$null=& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1') -Command generate -RepoRoot $repo 2>&1
if($LASTEXITCODE-eq0){throw '[mir4-target-compiler-historical-migration-cli-write-enabled]'}
$global:LASTEXITCODE=0

[pscustomobject][ordered]@{status='accepted-immutable-predecessor';migration_id=[string]$receipt.migration_id;receipt_sha256=$script:MIR4TargetCompilerMigrationReceiptSha256;package_source_sha256=[string]$receipt.package_source_sha256;release_transition_authority=$false}
