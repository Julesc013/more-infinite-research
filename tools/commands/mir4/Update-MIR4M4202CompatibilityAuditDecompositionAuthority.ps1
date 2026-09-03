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

function Set-MIR4M4202CompatibilityAuditProjection {
  param([string]$RelativePath, [string]$Text)
  $path = Join-Path $repo $RelativePath
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) {
      [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
    } else { '' }
    if ($actual -cne $Text) { throw "[mir4-m42-02-compatibility-audit-stale] $RelativePath" }
    return
  }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parent)
  }
  [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202CompatibilityAuditGitText {
  param([string]$Commit, [string]$RelativePath)
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'git'
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  [void]$start.ArgumentList.Add('-C')
  [void]$start.ArgumentList.Add($repo)
  [void]$start.ArgumentList.Add('show')
  [void]$start.ArgumentList.Add("${Commit}:$RelativePath")
  $process = [Diagnostics.Process]::Start($start)
  $text = $process.StandardOutput.ReadToEnd()
  $errorText = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "[mir4-m42-02-compatibility-audit-git-source] $Commit|$RelativePath|$errorText" }
  $text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-MIR4M4202CompatibilityAuditSlice {
  param([string[]]$Lines, [int]$Start, [int]$End)
  (@($Lines[($Start - 1)..($End - 1)]) -join [char]10) + [char]10
}

function Get-MIR4M4202CompatibilityAuditAst {
  param([string]$RelativePath)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath), [ref]$tokens, [ref]$errors)
  if (@($errors).Count -ne 0) { throw "[mir4-m42-02-compatibility-audit-parse] $RelativePath" }
  $ast
}

function Get-MIR4M4202CompatibilityAuditGitTextSha256 {
  param([string]$Commit, [string]$RelativePath)
  Get-MIR4Sha256String -Value (Get-MIR4M4202CompatibilityAuditGitText -Commit $Commit -RelativePath $RelativePath)
}

function ConvertTo-MIR4M4202CompatibilityAuditJson {
  param($Record)
  (($Record | ConvertTo-Json -Depth 100).Replace(([string][char]13 + [char]10), [string][char]10) + [string][char]10)
}

$startingCommit = 'e91fa87db2a2389123061269ada8115ce071770e'
$sourcePath = 'tools/commands/compatibility/Invoke-MIRCompatAudit.ps1'
$sourceSha256 = 'A6776583D9C3D03D001D3E38AFFE66BEC61E307B16077D1F8D63C47E02CEC664'
$sourceText = Get-MIR4M4202CompatibilityAuditGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceLines = @($sourceText.Split([char]10))
if (-not $sourceText.EndsWith([string][char]10) -or
    (Get-MIR4Sha256String -Value $sourceText) -cne $sourceSha256 -or
    $sourceLines.Count -ne 1678) {
  throw '[mir4-m42-02-compatibility-audit-starting-source]'
}

$moduleRoot = 'tools/commands/compatibility/compat-audit'
$moduleSpecs = @(
  [pscustomobject]@{ name = 'Configuration.ps1'; role = 'configuration validation, runtime custody, shared records, and filtering'; start = 50; end = 407; command_root_substitution = $true },
  [pscustomobject]@{ name = 'InputDiscovery.ps1'; role = 'local archive discovery and indexing'; start = 409; end = 470; command_root_substitution = $false },
  [pscustomobject]@{ name = 'ScenarioDefinitions.ps1'; role = 'official dependency modeling and generated scenario definitions'; start = 471; end = 857; command_root_substitution = $true },
  [pscustomobject]@{ name = 'ScenarioResolution.ps1'; role = 'portal, lock, runtime, and assertion resolution'; start = 859; end = 1187; command_root_substitution = $false },
  [pscustomobject]@{ name = 'ScenarioSelection.ps1'; role = 'scenario selection and deterministic lock construction'; start = 1189; end = 1399; command_root_substitution = $false },
  [pscustomobject]@{ name = 'ResultCollation.ps1'; role = 'reports, downloads, runtime result collation, and campaign evidence'; start = 1401; end = 1677; command_root_substitution = $false }
)

$expectedModules = @{}
foreach ($spec in $moduleSpecs) {
  $text = Get-MIR4M4202CompatibilityAuditSlice -Lines $sourceLines -Start $spec.start -End $spec.end
  if ([bool]$spec.command_root_substitution) {
    $text = $text.Replace('$PSScriptRoot', '$compatAuditCommandRoot')
  }
  $relative = "$moduleRoot/$($spec.name)"
  $expectedModules[$relative] = $text
  Set-MIR4M4202CompatibilityAuditProjection -RelativePath $relative -Text $text
}

$parameterBlock = Get-MIR4M4202CompatibilityAuditSlice -Lines $sourceLines -Start 1 -End 48
$facade = $parameterBlock + @'

$compatAuditCommandRoot = $PSScriptRoot
. (Join-Path $compatAuditCommandRoot 'compat-audit/Configuration.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/InputDiscovery.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ScenarioDefinitions.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ScenarioResolution.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ScenarioSelection.ps1')
. (Join-Path $compatAuditCommandRoot 'compat-audit/ResultCollation.ps1')
'@.Replace("`r`n", "`n")
Set-MIR4M4202CompatibilityAuditProjection -RelativePath $sourcePath -Text $facade

$predecessorPath = 'releases/migrations/MIR4-M42-02-Assurance-Release-DecompositionV1.json'
$predecessor = Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath) | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$predecessor.status -cne 'M42-02-PS6-ASSURANCE-RELEASE-DECOMPOSED' -or
    [string]$predecessor.next_fixed_point -cne 'M42-02-PS7-COMPATIBILITY-AUDIT') {
  throw '[mir4-m42-02-compatibility-audit-predecessor]'
}
$characterizationPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization = Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath) | ConvertFrom-Json -Depth 100 -DateKind String
$characterized = @($characterization.tracked_files | Where-Object { [string]$_.path -ceq $sourcePath })
if ($characterized.Count -ne 1 -or [string]$characterized[0].sha256 -cne $sourceSha256) {
  throw '[mir4-m42-02-compatibility-audit-characterization]'
}

$modules = @(
  foreach ($spec in $moduleSpecs) {
    $relative = "$moduleRoot/$($spec.name)"
    $actual = [IO.File]::ReadAllText((Join-Path $repo $relative)).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
    if ($actual -cne [string]$expectedModules[$relative]) { throw "[mir4-m42-02-compatibility-audit-segment] $relative" }
    $ast = Get-MIR4M4202CompatibilityAuditAst -RelativePath $relative
    $lineCount = @([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
    if ($lineCount -gt 400) { throw "[mir4-m42-02-compatibility-audit-module-size] $relative|$lineCount" }
    [pscustomobject][ordered]@{
      path = $relative
      role = [string]$spec.role
      source_lines = [pscustomobject][ordered]@{ start = [int]$spec.start; end = [int]$spec.end }
      sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative)
      hash_mode = 'canonical-text-v1'
      lines = $lineCount
      function_count = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count
      parse_errors = 0
      command_root_substitution = [bool]$spec.command_root_substitution
    }
  }
)
if ($modules.Count -ne 6 -or (@($modules | Measure-Object function_count -Sum).Sum) -ne 35) {
  throw '[mir4-m42-02-compatibility-audit-module-contract]'
}

$facadeAst = Get-MIR4M4202CompatibilityAuditAst -RelativePath $sourcePath
$facadeLines = @([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if (@($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -ne 0 -or
    $facadeLines -gt 80) {
  throw '[mir4-m42-02-compatibility-audit-facade]'
}
$oldTokens = $null
$oldErrors = $null
$oldAst = [Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$oldTokens, [ref]$oldErrors)
$oldFunctions = @($oldAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$currentFunctions = @(
  foreach ($spec in $moduleSpecs) {
    (Get-MIR4M4202CompatibilityAuditAst -RelativePath "$moduleRoot/$($spec.name)").FindAll(
      { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true
    ) | ForEach-Object { $_.Name }
  }
)
$oldFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions)
$currentFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
$parameterBlockSha = Get-MIR4Sha256String -Value $parameterBlock
if ($oldFunctions.Count -ne 35 -or
    ($oldFunctions -join '|') -cne ($currentFunctions -join '|') -or
    $oldFunctionSha -cne $currentFunctionSha -or
    -not $facade.StartsWith($parameterBlock, [StringComparison]::Ordinal)) {
  throw '[mir4-m42-02-compatibility-audit-public-contract]'
}

$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if ([int]$inventory.command_count -ne 85 -or
    [int]$inventory.summary.unknown -ne 0 -or
    [int]$inventory.summary.duplicate_command_keys -ne 0) {
  throw '[mir4-m42-02-compatibility-audit-inventory]'
}

$evolvedPaths = @(
  '.mir/assurance.json',
  '.mir/control/paths.yml',
  '.mir/modules.yml',
  '.mir/test-impact.yml',
  'assurance/catalog/tests.json',
  'docs/architecture/module-boundaries.md',
  'governance/automation/mir4-command-inventory-v1.json',
  'tests/architecture/Test-MIRArchitecture.ps1',
  'tests/compatibility/Test-MIRScenarioManifests.ps1',
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1',
  'tests/release/Test-MIRPerformanceBudgets.ps1',
  'tests/release/Test-MIRSanitationBudgets.ps1',
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tests/tooling/Test-MIRControlPlaneExecutor.ps1',
  'tests/tooling/Test-MIRVerificationSchemas.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1',
  'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4ValidationRunnerDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4AssuranceEvidenceDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4PreFreezeReleaseDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4BootstrapMaterializationDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4AssuranceReleaseDecompositionM4202.ps1',
  'tools/commands/compatibility/Invoke-MIRCompatAudit.ps1',
  'tools/lib/control/Executor.ps1',
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1',
  'tools/lib/validation/runner/StaticCompatibilityTooling.ps1',
  'tools/lib/validation/runner/StaticCompilerDiagnostics.ps1',
  'tools/mir/application/repository/RepositoryFixedPoint.ps1',
  'validation/tests.yml'
)
$evolvedBindings = @(
  $evolvedPaths | ForEach-Object {
    [pscustomobject][ordered]@{
      path = $_
      previous_sha256 = Get-MIR4M4202CompatibilityAuditGitTextSha256 -Commit $startingCommit -RelativePath $_
      current_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $_)
      hash_mode = 'canonical-text-v1'
      package_visible = $false
      release_authority = $false
    }
  }
)
$packageSourceSha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4M4202CompatibilityAuditDecompositionV1'
  status = 'M42-02-PS7-COMPATIBILITY-AUDIT-DECOMPOSED'
  starting_dev = [pscustomobject][ordered]@{ commit = $startingCommit; tree = '38a572548da58e10569e5dcbd8e84632874d0aa0' }
  predecessor = [pscustomobject][ordered]@{
    work_package = 'M42-02-PS6-ASSURANCE-RELEASE'
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
    tree = '38a572548da58e10569e5dcbd8e84632874d0aa0'
    path = $sourcePath
    sha256 = $sourceSha256
    lines = 1677
    function_count = 35
    evolution_chain = @()
  }
  decomposition = [pscustomobject][ordered]@{
    responsibility = 'compatibility-audit'
    facade = [pscustomobject][ordered]@{
      path = $sourcePath
      previous_sha256 = $sourceSha256
      current_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath)
      hash_mode = 'canonical-text-v1'
      previous_lines = 1677
      current_lines = $facadeLines
      maximum_lines = 80
      function_count = 0
    }
    module_root = $moduleRoot
    module_count = $modules.Count
    module_maximum_lines = 400
    modules = $modules
    segment_algorithm = 'ordered-current-source-slices-with-command-root-substitution-v1'
    command_root_substitutions = 3
  }
  public_contract = [pscustomobject][ordered]@{
    function_projection_algorithm = 'ordered-powershell-function-name-list-v1'
    previous_function_sha256 = $oldFunctionSha
    current_function_sha256 = $currentFunctionSha
    parameter_block_sha256 = $parameterBlockSha
    unchanged = $true
    function_count = $currentFunctions.Count
  }
  semantic_contract = [pscustomobject][ordered]@{
    ordered_source_slices_preserved = $true
    command_root_semantics_preserved = $true
    function_names_and_order_unchanged = $true
    parameter_surface_unchanged = $true
    module_load_order_explicit = $true
    configuration_unchanged = $true
    input_discovery_unchanged = $true
    scenario_execution_unchanged = $true
    result_collation_unchanged = $true
    compatibility_claims_unchanged = $true
    stream_authority_unchanged = $true
    pre_freeze_authority_chain_extended_for_ps7 = $true
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
    package_source_sha256 = $packageSourceSha256
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
  next_fixed_point = 'M42-02-PS8-OFFLINE-CUSTODY'
  record_sha256 = ''
}
$receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
$json = ConvertTo-MIR4M4202CompatibilityAuditJson -Record $receipt
if (-not ($json | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compatibility-audit-decomposition-v1.schema.json'))) {
  throw '[mir4-m42-02-compatibility-audit-receipt-schema]'
}
Set-MIR4M4202CompatibilityAuditProjection -RelativePath 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json' -Text $json
$receipt
