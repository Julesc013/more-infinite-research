param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/diagnostics/DiagnosticsMigration.ps1')

function Assert-MIR4DiagnosticsV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " $Detail" }
    throw "[$Code]$suffix"
  }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$registryPath = 'spec/api/mir4-v1/diagnostics.json'
Assert-MIR4DiagnosticsV1 ([IO.File]::ReadAllText((Join-Path $repo $registryPath)) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/preview/mir4-diagnostic-registry-v1.schema.json')) 'mir4-diagnostics-registry-schema'
$registry = Get-MIR4DiagnosticRegistryV1 -RepoRoot $repo
$codes = @($registry.diagnostics | ForEach-Object { [string]$_.code })
$orders = @($registry.diagnostics | ForEach-Object { [int]$_.order })
$legacyIds = @($registry.diagnostics | ForEach-Object { [string]$_.legacy_id })
Assert-MIR4DiagnosticsV1 (@($registry.diagnostics).Count -eq 43) 'mir4-diagnostics-registry-count'
Assert-MIR4DiagnosticsV1 (@($codes | Sort-Object -Unique).Count -eq $codes.Count) 'mir4-diagnostics-code-unique'
Assert-MIR4DiagnosticsV1 (@($orders | Sort-Object -Unique).Count -eq $orders.Count) 'mir4-diagnostics-order-unique'
Assert-MIR4DiagnosticsV1 (@($legacyIds | Sort-Object -Unique).Count -eq $legacyIds.Count) 'mir4-diagnostics-legacy-id-unique'
Assert-MIR4DiagnosticsV1 (($codes -join '|') -ceq (@($codes | Sort-Object -CaseSensitive) -join '|')) 'mir4-diagnostics-code-order'

$parity = Test-MIR4DiagnosticsFunctionalParityV1 -RepoRoot $repo
Assert-MIR4DiagnosticsV1 ([string]$parity.digest -ceq $script:MIR4DiagnosticsParityDigestV1) 'mir4-diagnostics-parity-digest'
Assert-MIR4DiagnosticsV1 ([string]$parity.record.rendered[0] -match '^\[MIR4-API-001\] error') 'mir4-diagnostics-error-first'
Assert-MIR4DiagnosticsV1 ([string]$parity.record.rendered[-1] -match '^\[MIR4-MEP-016\] info') 'mir4-diagnostics-info-last'

try { Get-MIR4DiagnosticDefinitionV1 -RepoRoot $repo -Code 'MIR4-NOT-REGISTERED' | Out-Null; throw '[mir4-diagnostics-unknown-accepted]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-diagnostic-unknown]')) { throw } }
try { New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-API-001' -Path ('$' + ('x' * 512)) | Out-Null; throw '[mir4-diagnostics-path-overflow-accepted]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-diagnostic-path]')) { throw } }
$largeContext = [ordered]@{}
foreach ($index in 1..33) { $largeContext["k$index"] = $index }
try { New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-API-001' -Context $largeContext | Out-Null; throw '[mir4-diagnostics-context-overflow-accepted]' }
catch { if (-not $_.Exception.Message.StartsWith('[mir4-diagnostic-context]')) { throw } }

Assert-MIR4DiagnosticsV1 (Test-MIR4DiagnosticsCompatibilityForwarderV1 -RepoRoot $repo) 'mir4-diagnostics-forwarder'
. (Join-Path $repo 'tools/lib/mir4/DiagnosticsV1.ps1')
$compatibilitySample = New-MIR4DiagnosticV1 -RepoRoot $repo -Code 'MIR4-API-001' -Path '$.availability'
Assert-MIR4DiagnosticsV1 ((Format-MIR4DiagnosticV1 $compatibilitySample) -ceq [string]$parity.record.rendered[0]) 'mir4-diagnostics-forwarder-function-parity'
Assert-MIR4DiagnosticsV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-diagnostics-package-source-mutation'

[pscustomobject][ordered]@{
  status='passed'
  implementation='tools/mir/domain/diagnostics/DiagnosticsV1.ps1'
  compatibility_entrypoint='tools/lib/mir4/DiagnosticsV1.ps1'
  registry_count=@($registry.diagnostics).Count
  registry_sha256=[string]$parity.record.registry_sha256
  parity_digest=[string]$parity.digest
  package_source_sha256=$packageBefore
}
