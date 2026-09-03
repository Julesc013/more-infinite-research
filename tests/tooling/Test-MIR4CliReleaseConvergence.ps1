param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')
. (Join-Path $repo 'tools/mir/application/release/ReleaseApplicationDag.ps1')

function Assert-MIR4CliReleaseConvergenceV1 {
  param([bool]$Condition,[string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$facadePath = Join-Path $repo 'tools/mir.ps1'
$routerPath = Join-Path $repo 'tools/mir/cli/Invoke-MIRCommandRouter.ps1'
$dispatcherPath = Join-Path $repo 'tools/mir/cli/router/CommandDispatcher.ps1'
$mir4DispatcherPath = Join-Path $repo 'tools/mir/cli/router/MIR4CommandDispatcher.ps1'
$facade = Get-Content -Raw -LiteralPath $facadePath
$router = Get-Content -Raw -LiteralPath $routerPath
$dispatcher = Get-Content -Raw -LiteralPath $dispatcherPath
$mir4Dispatcher = Get-Content -Raw -LiteralPath $mir4DispatcherPath
Assert-MIR4CliReleaseConvergenceV1 (($facade -split ([string][char]10)).Count -le 40) 'mir4-m42-01-public-cli-size'
Assert-MIR4CliReleaseConvergenceV1 ($facade -match 'Invoke-MIRCommandRouter\.ps1' -and $facade -notmatch 'function Show-MIRHelp|switch \(\$area\)') 'mir4-m42-01-public-cli-thin'
Assert-MIR4CliReleaseConvergenceV1 (($router -split ([string][char]10)).Count -le 200 -and $router -match 'function Show-MIRHelp' -and $router -match 'Invoke-MIRCommandDispatch' -and $router -notmatch 'switch ($area)') 'mir4-m42-01-command-router'
Assert-MIR4CliReleaseConvergenceV1 ($dispatcher -match 'Invoke-MIR4CommandDispatch' -and $dispatcher -match 'Invoke-MIRCoreCommandGroup' -and $mir4Dispatcher -match 'Invoke-MIR4ApplicationCommandGroup' -and $mir4Dispatcher -match 'Invoke-MIR4PlatformCommandGroup') 'mir4-m42-01-command-dispatch'

$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4CliReleaseConvergenceV1 ([string]$inventory.public_entrypoint -ceq 'tools/mir.ps1') 'mir4-m42-01-public-entrypoint'
Assert-MIR4CliReleaseConvergenceV1 ([int]$inventory.summary.canonical_public -eq 1 -and [int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0) 'mir4-m42-01-command-inventory'
Assert-MIR4CliReleaseConvergenceV1 (@($inventory.commands | Where-Object { [int]$_.implementation_count -ne 1 }).Count -eq 0) 'mir4-m42-01-command-single-implementation'

$dag = Get-MIR4ReleaseApplicationDagV1 -RepoRoot $repo
$dagCheck = Test-MIR4ReleaseApplicationDagV1 -RepoRoot $repo
Assert-MIR4CliReleaseConvergenceV1 ([string]$dagCheck.status -ceq 'M42-01-RELEASE-APPLICATION-DAG-PASSED' -and -not [bool]$dagCheck.publisher_can_build) 'mir4-m42-01-release-dag'
Assert-MIR4CliReleaseConvergenceV1 (@($dag.nodes | Where-Object id -eq 'publication-rehearsal').Count -eq 1 -and @($dag.publisher.forbidden_capabilities) -contains 'build') 'mir4-m42-01-publisher-confinement'
Assert-MIR4CliReleaseConvergenceV1 (@($dag.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-m42-01-release-firewall'

$wrapper = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4ReleaseWorkflow.ps1')
Assert-MIR4CliReleaseConvergenceV1 ($wrapper -match 'MIR4-RELEASE-WORKFLOW-COMPATIBILITY-COMMAND' -and $wrapper -match 'Invoke-MIR4ReleaseEngine\.ps1' -and $wrapper -notmatch 'Invoke-MIR4ReleasePhaseEngine') 'mir4-m42-01-release-wrapper'

$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json'
if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
  Assert-MIR4CliReleaseConvergenceV1 ([string]$receipt.status -ceq 'M42-01A-CLI-RELEASE-CONVERGENCE-COMPLETE' -and -not [bool]$receipt.release_application_dag.publisher_can_build) 'mir4-m42-01-receipt'
}

$cliOutput = & (Join-Path $repo 'tools/mir.ps1') mir4 release-engine check 2>&1 | Out-String
Assert-MIR4CliReleaseConvergenceV1 ($cliOutput -match 'M42-01-RELEASE-APPLICATION-DAG-PASSED') 'mir4-m42-01-public-release-command'
Assert-MIR4CliReleaseConvergenceV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-01-package-mutation'

[pscustomobject][ordered]@{
  status='M42-01A-CLI-RELEASE-CONVERGENCE-PASSED'
  command_count=[int]$inventory.command_count
  implementation_file_count=@($inventory.implementation_files).Count
  release_dag_node_count=[int]$dagCheck.node_count
  publisher_can_build=$false
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
