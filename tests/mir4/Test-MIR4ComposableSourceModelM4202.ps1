# MIR4-CANONICAL-EXECUTABLE-TEST
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/ComposableSourceModel.ps1')

function Assert-MIR4ComposableSourceModel([bool]$Condition,[string]$Id) {
  if (-not $Condition) { throw "[$Id]" }
}

$output = 'build/reports/package-source/tests/mir4-composable-source-model-v2.json'
$model = Write-MIR4ComposableSourceModel -RepoRoot $repo -OutputPath $output
$raw = Get-Content -Raw -LiteralPath (Join-Path $repo $output)
Assert-MIR4ComposableSourceModel (Test-MIR4BootstrapRecordHash -Record $model) 'mir4-composable-source-model-self-hash'
$schemaPath = Join-Path $repo 'spec/schemas/mir4-composable-source-model-proof-v2.schema.json'
Assert-MIR4ComposableSourceModel ($raw | Test-Json -SchemaFile $schemaPath) 'mir4-composable-source-model-schema'
Assert-MIR4ComposableSourceModel ([string]$model.status -ceq 'passed-canonical-composable-source-model') 'mir4-composable-source-model-status'
Assert-MIR4ComposableSourceModel ([string]$model.source_authority.source_root -ceq 'source' -and [string]$model.source_authority.sole_writer -ceq 'tools/mir/application/package/TargetMaterializer.ps1') 'mir4-composable-source-model-authority'
$expectedBindingTargets = @('f013','f014','f015','f016','f017','f100','f110','f200','f210')
$actualBindingTargets = @($model.bindings | ForEach-Object { @($_.target_scope) } | ForEach-Object { [string]$_ } | Sort-Object -Unique -CaseSensitive)
$expectedModelTargets = @('f100','f110','f200','f210')
$actualModelTargets = @($model.targets | ForEach-Object { [string]$_.target } | Sort-Object -CaseSensitive)
Assert-MIR4ComposableSourceModel (@($model.bindings).Count -eq 376 -and @($model.targets).Count -eq 4) 'mir4-composable-source-model-cardinality'
Assert-MIR4ComposableSourceModel (($actualBindingTargets -join '|') -ceq ($expectedBindingTargets -join '|')) 'mir4-composable-source-model-binding-target-scopes'
Assert-MIR4ComposableSourceModel (($actualModelTargets -join '|') -ceq ($expectedModelTargets -join '|')) 'mir4-composable-source-model-target-authority'

$unknownScopeModel = $raw | ConvertFrom-Json -Depth 100 -DateKind String
$unknownScopeModel.bindings[12].target_scope = @('f999')
$unknownScopeRejected = $false
try { $unknownScopeRejected = -not [bool](($unknownScopeModel | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) } catch { $unknownScopeRejected = $true }
Assert-MIR4ComposableSourceModel $unknownScopeRejected 'mir4-composable-source-model-reject-unknown-binding-target-scope'
$duplicateScopeModel = $raw | ConvertFrom-Json -Depth 100 -DateKind String
$duplicateScopeModel.bindings[12].target_scope = @('f017','f017')
$duplicateScopeRejected = $false
try { $duplicateScopeRejected = -not [bool](($duplicateScopeModel | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) } catch { $duplicateScopeRejected = $true }
Assert-MIR4ComposableSourceModel $duplicateScopeRejected 'mir4-composable-source-model-reject-duplicate-binding-target-scope'
Assert-MIR4ComposableSourceModel (@($model.targets | Where-Object { [string]$_.composition.path -notmatch '^targets/f(?:210|200|110|100)/composition[.]json$' }).Count -eq 0) 'mir4-composable-source-model-compositions'
Assert-MIR4ComposableSourceModel ([bool]$model.invariants.single_editable_source_root -and [bool]$model.invariants.era_family_labels_absent -and [bool]$model.invariants.retired_source_tree_absent -and [bool]$model.invariants.target_payload_directories_absent -and [bool]$model.invariants.declaration_order_independent) 'mir4-composable-source-model-invariants'
Assert-MIR4ComposableSourceModel ([bool]$model.transition_gate.package_cutover -and [bool]$model.transition_gate.old_writer_retirement -and @($model.transition_gate.PSObject.Properties | Where-Object { $_.Name -notin @('package_cutover','old_writer_retirement') -and [bool]$_.Value }).Count -eq 0) 'mir4-composable-source-model-transition-firewall'
Assert-MIR4ComposableSourceModel ($raw -notmatch 'src/mod|families[.](?:modern|legacy)|overlay[.]json') 'mir4-composable-source-model-no-retired-authority'

$cliRaw = & (Join-Path $repo 'tools/mir/cli/Invoke-MIR4PackageSource.ps1') -Command model -RepoRoot $repo -OutputPath 'build/reports/package-source/tests/mir4-composable-source-model-cli-v2.json'
$cli = $cliRaw | ConvertFrom-Json -Depth 20 -DateKind String
Assert-MIR4ComposableSourceModel ([string]$cli.status -ceq 'passed-canonical-composable-source-model' -and [int]$cli.bindings -eq 376 -and [int]$cli.targets -eq 4) 'mir4-composable-source-model-cli'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-composable-source-model-m42-02';bindings=@($model.bindings).Count;targets=@($model.targets).Count;release_authority=$false;record_sha256=[string]$model.record_sha256} | ConvertTo-Json -Depth 10
