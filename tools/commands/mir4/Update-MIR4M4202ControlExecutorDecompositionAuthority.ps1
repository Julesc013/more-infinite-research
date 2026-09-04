[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Set-MIR4M4202ControlExecutorProjection {
  param([string]$RelativePath, [string]$Text)
  $path = Join-Path $repo $RelativePath
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) {
      [IO.File]::ReadAllText($path).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
    } else { '' }
    if ($actual -cne $Text) { throw "[mir4-m42-02-control-executor-stale] $RelativePath" }
    return
  }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parent)
  }
  [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202ControlExecutorGitText {
  param([string]$Commit, [string]$RelativePath)
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'git'
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in @('-C', $repo, 'show', ($Commit + ':' + $RelativePath))) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::Start($start)
  $text = $process.StandardOutput.ReadToEnd()
  $errorText = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "[mir4-m42-02-control-executor-git-source] $Commit|$RelativePath|$errorText" }
  $text.Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
}

function Get-MIR4M4202ControlExecutorSlice {
  param([string[]]$Lines, [int]$Start, [int]$End)
  (@($Lines[($Start - 1)..($End - 1)]) -join [char]10) + [char]10
}

function Get-MIR4M4202ControlExecutorAst {
  param([string]$RelativePath)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath), [ref]$tokens, [ref]$errors)
  if (@($errors).Count -ne 0) { throw "[mir4-m42-02-control-executor-parse] $RelativePath" }
  $ast
}

function Get-MIR4M4202ControlExecutorGitTextSha256 {
  param([string]$Commit, [string]$RelativePath)
  Get-MIR4Sha256String -Value (Get-MIR4M4202ControlExecutorGitText -Commit $Commit -RelativePath $RelativePath)
}

function ConvertTo-MIR4M4202ControlExecutorJson {
  param($Record)
  (($Record | ConvertTo-Json -Depth 100).Replace(([string][char]13 + [char]10), [string][char]10) + [string][char]10)
}

$startingCommit = '8794596184f295425d0ac0867b06bbb4e15ff52f'
$startingTree = 'e11fdfa672ee0d8acd93e367254ac147188d833b'
$sourcePath = 'tools/lib/control/Executor.ps1'
$sourceSha256 = '97EACF68C080CF9D38102A5BF26E96A42C015020F78DBA049461422E5673AF66'
$sourceText = Get-MIR4M4202ControlExecutorGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceLines = @($sourceText.Split([char]10))
if (-not $sourceText.EndsWith([string][char]10) -or
    (Get-MIR4Sha256String -Value $sourceText) -cne $sourceSha256 -or
    $sourceLines.Count -ne 1231) {
  throw '[mir4-m42-02-control-executor-starting-source]'
}

$moduleRoot = 'tools/lib/control/executor'
$moduleSpecs = @(
  [pscustomobject]@{ name = 'ContextAndTaskExecution.ps1'; role = 'context execution state, canonical candidates, result evidence, task dispatch, and source locks'; start = 3; end = 266 },
  [pscustomobject]@{ name = 'EnvironmentExecution.ps1'; role = 'Factorio context locks, specialized evidence, and environment batch execution'; start = 268; end = 433 },
  [pscustomobject]@{ name = 'PerformanceSourceAndArtifacts.ps1'; role = 'performance authority, source overlays, compact artifact custody, and artifact movement'; start = 435; end = 718 },
  [pscustomobject]@{ name = 'RuntimeMeasurements.ps1'; role = 'performance, upgrade, and ecosystem measurements'; start = 720; end = 921 },
  [pscustomobject]@{ name = 'PackageDeltaMeasurements.ps1'; role = 'ZIP observations, exact path sets, native patch policy, and approved-delta measurements'; start = 923; end = 1137 },
  [pscustomobject]@{ name = 'AggregateGate.ps1'; role = 'aggregate task closure and execution-manifest publication'; start = 1139; end = 1230 }
)

$expectedModules = @{}
foreach ($spec in $moduleSpecs) {
  $text = Get-MIR4M4202ControlExecutorSlice -Lines $sourceLines -Start $spec.start -End $spec.end
  $relative = "$moduleRoot/$($spec.name)"
  $expectedModules[$relative] = $text
  Set-MIR4M4202ControlExecutorProjection -RelativePath $relative -Text $text
}

$setupBlock = Get-MIR4M4202ControlExecutorSlice -Lines $sourceLines -Start 1 -End 2
$facadeTail = @'
. (Join-Path $PSScriptRoot 'executor/ContextAndTaskExecution.ps1')
. (Join-Path $PSScriptRoot 'executor/EnvironmentExecution.ps1')
. (Join-Path $PSScriptRoot 'executor/PerformanceSourceAndArtifacts.ps1')
. (Join-Path $PSScriptRoot 'executor/RuntimeMeasurements.ps1')
. (Join-Path $PSScriptRoot 'executor/PackageDeltaMeasurements.ps1')
. (Join-Path $PSScriptRoot 'executor/AggregateGate.ps1')
'@.Replace(([string][char]13 + [char]10), [string][char]10)
$facade = $setupBlock + $facadeTail
Set-MIR4M4202ControlExecutorProjection -RelativePath $sourcePath -Text $facade

$predecessorPath = 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json'
$predecessor = Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath) | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$predecessor.status -cne 'M42-02-PS9-RELEASE-CAPSULE-DECOMPOSED' -or
    [string]$predecessor.next_fixed_point -cne 'M42-02-PS10-CONTROL-EXECUTOR' -or
    -not (Test-MIR4BootstrapRecordHash -Record $predecessor)) {
  throw '[mir4-m42-02-control-executor-predecessor]'
}

$characterizationPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization = Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath) | ConvertFrom-Json -Depth 100 -DateKind String
$characterized = @($characterization.tracked_files | Where-Object { [string]$_.path -ceq $sourcePath })
if ($characterized.Count -ne 1 -or [string]$characterized[0].sha256 -cne '0DE88F7E2E2BB1FE90E3823D52880C5E54CC772BEEFB783BCD2FD87595600A3E' -or
    [int]$characterized[0].sequence -ne 10 -or [string]$characterized[0].next_node -cne 'M42-02-PS10-CONTROL-EXECUTOR') {
  throw '[mir4-m42-02-control-executor-characterization]'
}

$sourceEvolutionPath = 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
$sourceEvolution = Get-Content -Raw -LiteralPath (Join-Path $repo $sourceEvolutionPath) | ConvertFrom-Json -Depth 100 -DateKind String
$sourceEvolutionBinding = @($sourceEvolution.evolved_bindings | Where-Object { [string]$_.path -ceq $sourcePath })
if ($sourceEvolutionBinding.Count -ne 1 -or
    [string]$sourceEvolutionBinding[0].previous_sha256 -cne [string]$characterized[0].sha256 -or
    [string]$sourceEvolutionBinding[0].current_sha256 -cne $sourceSha256 -or
    [bool]$sourceEvolutionBinding[0].package_visible -or [bool]$sourceEvolutionBinding[0].release_authority) {
  throw '[mir4-m42-02-control-executor-source-evolution]'
}

$modules = @(
  foreach ($spec in $moduleSpecs) {
    $relative = "$moduleRoot/$($spec.name)"
    $actual = [IO.File]::ReadAllText((Join-Path $repo $relative)).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
    if ($actual -cne [string]$expectedModules[$relative]) { throw "[mir4-m42-02-control-executor-segment] $relative" }
    $ast = Get-MIR4M4202ControlExecutorAst -RelativePath $relative
    $lineCount = @([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
    if ($lineCount -gt 400) { throw "[mir4-m42-02-control-executor-module-lines] $relative|$lineCount" }
    [pscustomobject][ordered]@{
      path = $relative
      role = [string]$spec.role
      source_start_line = [int]$spec.start
      source_end_line = [int]$spec.end
      lines = $lineCount
      sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative)
      hash_mode = 'canonical-text-v1'
      function_count = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count
    }
  }
)

$facadeAst = Get-MIR4M4202ControlExecutorAst -RelativePath $sourcePath
$facadeLines = @([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if ($facadeLines -gt 80 -or @($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -ne 0) {
  throw '[mir4-m42-02-control-executor-facade]'
}
$oldTokens = $null
$oldErrors = $null
$oldAst = [Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$oldTokens, [ref]$oldErrors)
$oldFunctions = @($oldAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$currentFunctions = @(
  foreach ($spec in $moduleSpecs) {
    (Get-MIR4M4202ControlExecutorAst -RelativePath "$moduleRoot/$($spec.name)").FindAll(
      { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true
    ) | ForEach-Object { $_.Name }
  }
)
if (@($oldErrors).Count -ne 0 -or $oldFunctions.Count -ne 27 -or ($oldFunctions -join '|') -cne ($currentFunctions -join '|')) {
  throw '[mir4-m42-02-control-executor-public-contract]'
}
$oldFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions)
$currentFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
$setupBlockSha = Get-MIR4Sha256String -Value $setupBlock

$inventory = if ($Check) {
  Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
} else {
  Update-MIR4CommandInventoryV1 -RepoRoot $repo
}
if ([int]$inventory.command_count -ne 85 -or [int]$inventory.summary.unknown -ne 0 -or [int]$inventory.summary.duplicate_command_keys -ne 0) {
  throw '[mir4-m42-02-control-executor-inventory]'
}

$evolvedPaths = @(
  '.mir/assurance.json',
  '.mir/control/paths.yml',
  '.mir/modules.yml',
  '.mir/test-impact.yml',
  'assurance/catalog/tests.json',
  'docs/architecture/module-boundaries.md',
  'fixtures/mir4-mep-discovery-v1/negative/invalid-envelope.json',
  'fixtures/mir4-mep-discovery-v1/positive/host-absent.json',
  'fixtures/mir4-mep-discovery-v1/positive/order-a.json',
  'fixtures/mir4-mep-discovery-v1/positive/order-b.json',
  'fixtures/mir4-mep-v1/negative/cycle-a.json',
  'fixtures/mir4-mep-v1/negative/cycle-b.json',
  'fixtures/mir4-mep-v1/negative/forbidden-callback.json',
  'fixtures/mir4-mep-v1/negative/missing-dependency.json',
  'fixtures/mir4-mep-v1/positive/reference-extension.json',
  'governance/automation/mir4-command-inventory-v1.json',
  'mir.lock',
  'sdk/preview/mir4/mep-v1/templates/all-fragments/extension.json',
  'sdk/preview/mir4/reference-extension-v1/extension.json',
  'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json',
  'sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json',
  'sdk/preview/mir4/reference/compilation-runs.json',
  'sdk/preview/mir4/reference/continuity-bundle-template.json',
  'sdk/preview/mir4/reference/extension-closure-v1.json',
  'sdk/preview/mir4/reference/f210-mep-discovery-v1.json',
  'sdk/preview/mir4/reference/inspection-bundle-v1.json',
  'sdk/preview/mir4/reference/inspector-workbench-result-v1.json',
  'sdk/preview/mir4/reference/merge-law-catalogue.json',
  'sdk/preview/mir4/reference/migration-graph-matrix.json',
  'sdk/preview/mir4/reference/query-snapshot-f210.json',
  'sdk/preview/mir4/reference/shadow-extension-run-v1-f210.json',
  'sdk/preview/mir4/reference/support-bundle-v1.json',
  'tests/architecture/Test-MIRArchitecture.ps1',
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1',
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1',
  'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4CompatibilityAuditDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4OfflineCustodyDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4ReleaseCapsuleDecompositionM4202.ps1',
  'tools/lib/control/Executor.ps1',
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1',
  'validation/tests.yml'
)
$evolvedBindings = @(
  $evolvedPaths | ForEach-Object {
    [pscustomobject][ordered]@{
      path = $_
      previous_sha256 = Get-MIR4M4202ControlExecutorGitTextSha256 -Commit $startingCommit -RelativePath $_
      current_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_)
      hash_mode = 'canonical-text-v1'
      package_visible = $false
      release_authority = $false
    }
  }
)

$receipt = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4M4202ControlExecutorDecompositionV1'
  status = 'M42-02-PS10-CONTROL-EXECUTOR-DECOMPOSED'
  starting_dev = [pscustomobject][ordered]@{ commit = $startingCommit; tree = $startingTree }
  predecessor = [pscustomobject][ordered]@{
    work_package = 'M42-02-PS9-RELEASE-CAPSULE'
    receipt = $predecessorPath
    receipt_sha256 = (Get-FileHash -LiteralPath (Join-Path $repo $predecessorPath) -Algorithm SHA256).Hash.ToUpperInvariant()
    record_sha256 = [string]$predecessor.record_sha256
    status = [string]$predecessor.status
  }
  characterization = [pscustomobject][ordered]@{
    receipt = $characterizationPath
    record_sha256 = [string]$characterization.record_sha256
    path = $sourcePath
    sha256 = [string]$characterized[0].sha256
    lines = [int]$characterized[0].lines
    responsibilities = @($characterized[0].responsibilities)
  }
  current_source = [pscustomobject][ordered]@{
    commit = $startingCommit
    tree = $startingTree
    path = $sourcePath
    sha256 = $sourceSha256
    lines = 1230
    function_count = 27
    evolution_chain = @([pscustomobject][ordered]@{
      receipt = $sourceEvolutionPath
      record_sha256 = [string]$sourceEvolution.record_sha256
      previous_sha256 = [string]$sourceEvolutionBinding[0].previous_sha256
      current_sha256 = [string]$sourceEvolutionBinding[0].current_sha256
      reason = 'preserve PS7 compatibility-audit module overlay and post-cutover package-fingerprint selection'
    })
  }
  decomposition = [pscustomobject][ordered]@{
    responsibility = 'control-executor'
    facade = [pscustomobject][ordered]@{
      path = $sourcePath
      previous_sha256 = $sourceSha256
      current_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath)
      hash_mode = 'canonical-text-v1'
      previous_lines = 1230
      current_lines = $facadeLines
      maximum_lines = 80
      function_count = 0
    }
    module_root = $moduleRoot
    module_count = $modules.Count
    module_maximum_lines = 400
    modules = $modules
    segment_algorithm = 'ordered-current-source-slices-v1'
  }
  public_contract = [pscustomobject][ordered]@{
    function_projection_algorithm = 'ordered-powershell-function-name-list-v1'
    previous_function_sha256 = $oldFunctionSha
    current_function_sha256 = $currentFunctionSha
    setup_block_sha256 = $setupBlockSha
    unchanged = $true
    function_count = $currentFunctions.Count
  }
  semantic_contract = [pscustomobject][ordered]@{
    ordered_current_source_slices_preserved = $true
    function_names_and_order_unchanged = $true
    setup_unchanged = $true
    module_load_order_explicit = $true
    context_execution_state_unchanged = $true
    environment_execution_unchanged = $true
    performance_source_and_artifact_custody_unchanged = $true
    runtime_measurements_unchanged = $true
    package_and_delta_measurements_unchanged = $true
    aggregate_gate_unchanged = $true
    ps7_source_evolution_preserved = $true
    platform_projections_regenerated = $true
    pre_freeze_authority_chain_extended_for_ps10 = $true
  }
  tooling_inventory = [pscustomobject][ordered]@{
    path = 'governance/automation/mir4-command-inventory-v1.json'
    sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json')
    hash_mode = 'canonical-text-v1'
    digest = [string]$inventory.digest
    command_count = [int]$inventory.command_count
    unknown = [int]$inventory.summary.unknown
    duplicate_command_keys = [int]$inventory.summary.duplicate_command_keys
  }
  evolved_bindings = $evolvedBindings
  preservation = [pscustomobject][ordered]@{
    package_source_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
    package_visible_delta = @()
    gameplay = $false
    saves = $true
    settings = $true
    migrations = $true
    compatibility_claims = $true
    stream_identities = $true
  }
  transition_gate = [pscustomobject][ordered]@{
    version_allocation = $false
    tagging = $false
    signing = $false
    sealing = $false
    publication = $false
  }
  next_fixed_point = 'M42-02-PS11-SUPPLY-CHAIN'
  record_sha256 = ''
}
$receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
$json = ConvertTo-MIR4M4202ControlExecutorJson -Record $receipt
if (-not ($json | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-control-executor-decomposition-v1.schema.json'))) {
  throw '[mir4-m42-02-control-executor-receipt-schema]'
}
Set-MIR4M4202ControlExecutorProjection -RelativePath 'releases/migrations/MIR4-M42-02-Control-Executor-DecompositionV1.json' -Text $json
$receipt
