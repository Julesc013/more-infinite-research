$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/ShadowSourceModel.ps1')

function Assert-MIR4SourceModel([bool]$Condition,[string]$Id,[string]$Detail='') {
  if (-not $Condition) { throw "[$Id] $Detail" }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$readmeBefore = Get-MIRFileSha256 -Path (Join-Path $repo 'README.md')
$outputPath = 'build/reports/package-source/tests/mir4-shadow-source-model-v1.json'
$report = Write-MIR4ShadowSourceModel -RepoRoot $repo -OutputPath $outputPath
Assert-MIR4SourceModel (Test-MIR4BootstrapRecordHash -Record $report) 'mir4-shadow-source-model-self-hash'
Assert-MIR4SourceModel ((Get-Content -Raw -LiteralPath (Join-Path $repo $outputPath)) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-shadow-source-model-proof-v1.schema.json')) 'mir4-shadow-source-model-schema'
Assert-MIR4SourceModel ([string]$report.status -ceq 'passed-semantic-shadow-model-no-editable-source-no-cutover') 'mir4-shadow-source-model-status'
Assert-MIR4SourceModel (@($report.bindings).Count -eq 406) 'mir4-shadow-source-model-bindings'
Assert-MIR4SourceModel (@($report.target_overlays).Count -eq 4) 'mir4-shadow-source-model-targets'
Assert-MIR4SourceModel (@($report.bindings | Where-Object { [string]$_.semantic_class -notin @('common-semantic-source','common-asset-locale','generated-metadata','generated-lifecycle-entrypoint','target-overlay','target-replacement','target-compatibility-shim','migration','package-documentation') }).Count -eq 0) 'mir4-shadow-source-model-unclassified'
Assert-MIR4SourceModel (@($report.target_overlays.operations | Where-Object { [string]$_.semantic_class -ceq 'target-omission' }).Count -gt 0) 'mir4-shadow-source-model-omissions'
Assert-MIR4SourceModel (@($report.target_overlays | Where-Object { [int]$_.operation_counts.replace -ne 0 }).Count -eq 0) 'mir4-shadow-source-model-collision-free-overlays'
Assert-MIR4SourceModel ([bool]$report.invariants.declaration_order_independent -and [bool]$report.invariants.no_path_collision -and [bool]$report.invariants.no_unowned_path) 'mir4-shadow-source-model-invariants'
Assert-MIR4SourceModel (@($report.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-shadow-source-model-transition-firewall'
Assert-MIR4SourceModel (-not (Test-Path -LiteralPath (Join-Path $repo 'src/mod'))) 'mir4-shadow-source-model-premature-editable-source'
Assert-MIR4SourceModel ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-shadow-source-model-package-mutation'
Assert-MIR4SourceModel ((Get-MIRFileSha256 -Path (Join-Path $repo 'README.md')) -ceq $readmeBefore) 'mir4-shadow-source-model-readme-mutation'

[pscustomobject][ordered]@{status='passed';bindings=@($report.bindings).Count;targets=@($report.target_overlays).Count;omissions=@($report.target_overlays.operations | Where-Object semantic_class -ceq 'target-omission').Count;classification_counts=$report.classification_counts;package_source_sha256=$packageBefore;release_transition_authority=$false;record_sha256=[string]$report.record_sha256} | ConvertTo-Json -Depth 20
