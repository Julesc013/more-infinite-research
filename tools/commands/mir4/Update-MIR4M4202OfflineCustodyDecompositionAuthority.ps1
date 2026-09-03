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

function Set-MIR4M4202OfflineCustodyProjection {
  param([string]$RelativePath, [string]$Text)
  $path = Join-Path $repo $RelativePath
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) {
      [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
    } else { '' }
    if ($actual -cne $Text) { throw "[mir4-m42-02-offline-custody-stale] $RelativePath" }
    return
  }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parent)
  }
  [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202OfflineCustodyGitText {
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
  if ($process.ExitCode -ne 0) { throw "[mir4-m42-02-offline-custody-git-source] $Commit|$RelativePath|$errorText" }
  $text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-MIR4M4202OfflineCustodySlice {
  param([string[]]$Lines, [int]$Start, [int]$End)
  (@($Lines[($Start - 1)..($End - 1)]) -join [char]10) + [char]10
}

function Get-MIR4M4202OfflineCustodyAst {
  param([string]$RelativePath)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath), [ref]$tokens, [ref]$errors)
  if (@($errors).Count -ne 0) { throw "[mir4-m42-02-offline-custody-parse] $RelativePath" }
  $ast
}

function Get-MIR4M4202OfflineCustodyGitTextSha256 {
  param([string]$Commit, [string]$RelativePath)
  Get-MIR4Sha256String -Value (Get-MIR4M4202OfflineCustodyGitText -Commit $Commit -RelativePath $RelativePath)
}

function ConvertTo-MIR4M4202OfflineCustodyJson {
  param($Record)
  (($Record | ConvertTo-Json -Depth 100).Replace(([string][char]13 + [char]10), [string][char]10) + [string][char]10)
}

$startingCommit = '184c8583fb3460b83aea562a177ac8f690ad5c60'
$startingTree = '1f3b92d52a6d481bff4cbea1cfbdfb0daf1507b1'
$sourcePath = 'tools/mir/application/custody/OfflineCandidateCustody.ps1'
$sourceSha256 = '4AA7219BC19A02895F7076DF92E923D64F7C4D440DC4CBC0E937FA8C1CFB5A15'
$sourceText = Get-MIR4M4202OfflineCustodyGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceLines = @($sourceText.Split([char]10))
if (-not $sourceText.EndsWith([string][char]10) -or
    (Get-MIR4Sha256String -Value $sourceText) -cne $sourceSha256 -or
    $sourceLines.Count -ne 1381) {
  throw '[mir4-m42-02-offline-custody-starting-source]'
}

$moduleRoot = 'tools/mir/application/custody/offline-candidate-custody'
$moduleSpecs = @(
  [pscustomobject]@{ name = 'CoreRecords.ps1'; role = 'repository resolution, canonical record validation, and hash-bound record bindings'; start = 27; end = 151; application_root_substitution = $true },
  [pscustomobject]@{ name = 'Admission.ps1'; role = 'candidate, plan, target, and governed-root custody admission'; start = 153; end = 277; application_root_substitution = $false },
  [pscustomobject]@{ name = 'SealInputs.ps1'; role = 'seal-input collection and offline path and executable guards'; start = 279; end = 404; application_root_substitution = $false },
  [pscustomobject]@{ name = 'OpenSshSignatures.ps1'; role = 'bounded OpenSSH invocation, key identity, and signature verification'; start = 406; end = 551; application_root_substitution = $false },
  [pscustomobject]@{ name = 'ExactEngineEvidence.ps1'; role = 'exact-engine qualification evidence verification'; start = 553; end = 677; application_root_substitution = $false },
  [pscustomobject]@{ name = 'PublicationDryRun.ps1'; role = 'non-mutating publication dry-run construction and pair verification'; start = 679; end = 935; application_root_substitution = $false },
  [pscustomobject]@{ name = 'OfflineSeal.ps1'; role = 'proof-only offline seal construction and verification'; start = 937; end = 1183; application_root_substitution = $false },
  [pscustomobject]@{ name = 'RestoreAndCompletion.ps1'; role = 'offline candidate restore and emergency-lane completion records'; start = 1185; end = 1380; application_root_substitution = $false }
)

$expectedModules = @{}
foreach ($spec in $moduleSpecs) {
  $text = Get-MIR4M4202OfflineCustodySlice -Lines $sourceLines -Start $spec.start -End $spec.end
  if ([bool]$spec.application_root_substitution) {
    $text = $text.Replace('$PSScriptRoot', '$script:MIR4OfflineCustodyApplicationRootV1')
  }
  if ([string]$spec.name -ceq 'Admission.ps1') {
    $historicalCheck = '$null = & $checker -RepoRoot $repo -PlanPath $CandidatePlanPath -Target f210 -OutputRoot $governedRoot -Check'
    $explicitHistoricalCheck = '$null = & $checker -RepoRoot $repo -PlanPath $CandidatePlanPath -Target f210 -OutputRoot $governedRoot -HistoricalCompatibility -Check'
    if (-not $text.Contains($historicalCheck, [StringComparison]::Ordinal)) { throw '[mir4-m42-02-offline-custody-historical-check-source]' }
    $text = $text.Replace($historicalCheck, $explicitHistoricalCheck)
  }
  $relative = "$moduleRoot/$($spec.name)"
  $expectedModules[$relative] = $text
  Set-MIR4M4202OfflineCustodyProjection -RelativePath $relative -Text $text
}

$setupBlock = Get-MIR4M4202OfflineCustodySlice -Lines $sourceLines -Start 1 -End 25
$facade = $setupBlock + @'

$script:MIR4OfflineCustodyApplicationRootV1 = $PSScriptRoot
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/CoreRecords.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/Admission.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/SealInputs.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/OpenSshSignatures.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/ExactEngineEvidence.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/PublicationDryRun.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/OfflineSeal.ps1')
. (Join-Path $script:MIR4OfflineCustodyApplicationRootV1 'offline-candidate-custody/RestoreAndCompletion.ps1')
'@.Replace("`r`n", "`n")
Set-MIR4M4202OfflineCustodyProjection -RelativePath $sourcePath -Text $facade

$predecessorPath = 'releases/migrations/MIR4-M42-02-Compatibility-Audit-DecompositionV1.json'
$predecessor = Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath) | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$predecessor.status -cne 'M42-02-PS7-COMPATIBILITY-AUDIT-DECOMPOSED' -or
    [string]$predecessor.next_fixed_point -cne 'M42-02-PS8-OFFLINE-CUSTODY') {
  throw '[mir4-m42-02-offline-custody-predecessor]'
}
$characterizationPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization = Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath) | ConvertFrom-Json -Depth 100 -DateKind String
$characterized = @($characterization.tracked_files | Where-Object { [string]$_.path -ceq $sourcePath })
if ($characterized.Count -ne 1 -or [string]$characterized[0].sha256 -cne $sourceSha256) {
  throw '[mir4-m42-02-offline-custody-characterization]'
}

$modules = @(
  foreach ($spec in $moduleSpecs) {
    $relative = "$moduleRoot/$($spec.name)"
    $actual = [IO.File]::ReadAllText((Join-Path $repo $relative)).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
    if ($actual -cne [string]$expectedModules[$relative]) { throw "[mir4-m42-02-offline-custody-segment] $relative" }
    $ast = Get-MIR4M4202OfflineCustodyAst -RelativePath $relative
    $lineCount = @([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
    if ($lineCount -gt 400) { throw "[mir4-m42-02-offline-custody-module-size] $relative|$lineCount" }
    [pscustomobject][ordered]@{
      path = $relative
      role = [string]$spec.role
      source_lines = [pscustomobject][ordered]@{ start = [int]$spec.start; end = [int]$spec.end }
      sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative)
      hash_mode = 'canonical-text-v1'
      lines = $lineCount
      function_count = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count
      parse_errors = 0
      application_root_substitution = [bool]$spec.application_root_substitution
    }
  }
)
if ($modules.Count -ne 8 -or (@($modules | Measure-Object function_count -Sum).Sum) -ne 26) {
  throw '[mir4-m42-02-offline-custody-module-contract]'
}

$facadeAst = Get-MIR4M4202OfflineCustodyAst -RelativePath $sourcePath
$facadeLines = @([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if (@($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -ne 0 -or
    $facadeLines -gt 80) {
  throw '[mir4-m42-02-offline-custody-facade]'
}
$oldTokens = $null
$oldErrors = $null
$oldAst = [Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$oldTokens, [ref]$oldErrors)
$oldFunctions = @($oldAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$currentFunctions = @(
  foreach ($spec in $moduleSpecs) {
    (Get-MIR4M4202OfflineCustodyAst -RelativePath "$moduleRoot/$($spec.name)").FindAll(
      { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true
    ) | ForEach-Object { $_.Name }
  }
)
$oldFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions)
$currentFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
$setupBlockSha = Get-MIR4Sha256String -Value $setupBlock
if ($oldFunctions.Count -ne 26 -or
    ($oldFunctions -join '|') -cne ($currentFunctions -join '|') -or
    $oldFunctionSha -cne $currentFunctionSha -or
    -not $facade.StartsWith($setupBlock, [StringComparison]::Ordinal)) {
  throw '[mir4-m42-02-offline-custody-public-contract]'
}

$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if ([int]$inventory.command_count -ne 85 -or
    [int]$inventory.summary.unknown -ne 0 -or
    [int]$inventory.summary.duplicate_command_keys -ne 0) {
  throw '[mir4-m42-02-offline-custody-inventory]'
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
  'tools/mir/application/custody/OfflineCandidateCustody.ps1',
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1',
  'validation/tests.yml'
)
$evolvedBindings = @(
  $evolvedPaths | ForEach-Object {
    [pscustomobject][ordered]@{
      path = $_
      previous_sha256 = Get-MIR4M4202OfflineCustodyGitTextSha256 -Commit $startingCommit -RelativePath $_
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
  kind = 'MIR4M4202OfflineCustodyDecompositionV1'
  status = 'M42-02-PS8-OFFLINE-CUSTODY-DECOMPOSED'
  starting_dev = [pscustomobject][ordered]@{ commit = $startingCommit; tree = $startingTree }
  predecessor = [pscustomobject][ordered]@{
    work_package = 'M42-02-PS7-COMPATIBILITY-AUDIT'
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
    lines = 1380
    function_count = 26
    evolution_chain = @()
  }
  decomposition = [pscustomobject][ordered]@{
    responsibility = 'offline-custody'
    facade = [pscustomobject][ordered]@{
      path = $sourcePath
      previous_sha256 = $sourceSha256
      current_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath)
      hash_mode = 'canonical-text-v1'
      previous_lines = 1380
      current_lines = $facadeLines
      maximum_lines = 80
      function_count = 0
    }
    module_root = $moduleRoot
    module_count = $modules.Count
    module_maximum_lines = 400
    modules = $modules
    segment_algorithm = 'ordered-current-source-slices-with-declared-substitutions-v1'
    application_root_substitutions = 1
    historical_compatibility_opt_in_substitutions = 1
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
    ordered_source_slices_preserved_with_declared_substitutions = $true
    application_root_semantics_preserved = $true
    function_names_and_order_unchanged = $true
    setup_unchanged = $true
    module_load_order_explicit = $true
    custody_admission_unchanged = $true
    historical_compatibility_check_explicit = $true
    seal_inputs_unchanged = $true
    signature_verification_unchanged = $true
    qualification_evidence_unchanged = $true
    publication_dry_run_unchanged = $true
    offline_seal_unchanged = $true
    offline_restore_unchanged = $true
    emergency_completion_unchanged = $true
    pre_freeze_authority_chain_extended_for_ps8 = $true
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
  next_fixed_point = 'M42-02-PS9-RELEASE-CAPSULE'
  record_sha256 = ''
}
$receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
$json = ConvertTo-MIR4M4202OfflineCustodyJson -Record $receipt
if (-not ($json | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-offline-custody-decomposition-v1.schema.json'))) {
  throw '[mir4-m42-02-offline-custody-receipt-schema]'
}
Set-MIR4M4202OfflineCustodyProjection -RelativePath 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json' -Text $json
$receipt
