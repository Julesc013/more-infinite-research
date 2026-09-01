$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/ShadowTargetMaterializer.ps1')

function Assert-MIR4Shadow([bool]$Condition,[string]$Id,[string]$Detail='') {
  if (-not $Condition) { throw "[$Id] $Detail" }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$readmeBefore = Get-MIRFileSha256 -Path (Join-Path $repo 'README.md')
$reportPath = 'build/reports/package-source/tests/mir4-shadow-target-materializer-v1.json'
$outputRoot = 'build/mir4/package-source/tests/shadow-materializer-v1'
$report = Invoke-MIR4ShadowTargetParity -RepoRoot $repo -OutputRoot $outputRoot -ReportPath $reportPath
Assert-MIR4Shadow (Test-MIR4BootstrapRecordHash -Record $report) 'mir4-shadow-report-self-hash'
Assert-MIR4Shadow ((Get-Content -Raw -LiteralPath (Join-Path $repo $reportPath)) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-shadow-target-materializer-proof-v1.schema.json')) 'mir4-shadow-report-schema'
Assert-MIR4Shadow ([string]$report.status -ceq 'passed-shadow-bootstrap-parity-no-cutover') 'mir4-shadow-status'
Assert-MIR4Shadow (@($report.targets).Count -eq 4) 'mir4-shadow-target-count'
$counts = [ordered]@{f210=@(89,202,14,305);f200=@(89,202,12,303);f110=@(89,81,4,174);f100=@(89,81,4,174)}
foreach ($target in @($report.targets)) {
  $expected = $counts[[string]$target.target]
  Assert-MIR4Shadow ([int]$target.layer_counts.common -eq $expected[0]) 'mir4-shadow-common-count' ([string]$target.target)
  Assert-MIR4Shadow ([int]$target.layer_counts.family -eq $expected[1]) 'mir4-shadow-family-count' ([string]$target.target)
  Assert-MIR4Shadow ([int]$target.layer_counts.target -eq $expected[2]) 'mir4-shadow-target-overlay-count' ([string]$target.target)
  Assert-MIR4Shadow ([int]$target.entry_count -eq $expected[3]) 'mir4-shadow-entry-count' ([string]$target.target)
  Assert-MIR4Shadow ([bool]$target.exact_tree_parity -and [bool]$target.deterministic_archive_bytes) 'mir4-shadow-parity' ([string]$target.target)
  Assert-MIR4Shadow ([string]$target.archive_a -ceq [string]$target.archive_b) 'mir4-shadow-archive-determinism' ([string]$target.target)
}
Assert-MIR4Shadow (@($report.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-shadow-transition-firewall'
Assert-MIR4Shadow ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-shadow-package-mutation'
Assert-MIR4Shadow ((Get-MIRFileSha256 -Path (Join-Path $repo 'README.md')) -ceq $readmeBefore) 'mir4-shadow-readme-mutation'

[pscustomobject][ordered]@{status='passed';targets=4;materializations=8;exact_tree_parity=$true;deterministic_archive_bytes=$true;historical_archive_byte_parity=@($report.targets | Where-Object { [bool]$_.historical_archive_byte_parity }).Count;package_source_sha256=$packageBefore;release_transition_authority=$false;runtime_replay_required=$true;record_sha256=[string]$report.record_sha256} | ConvertTo-Json -Depth 10
