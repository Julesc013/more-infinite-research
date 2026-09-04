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

function Set-MIR4M4202ReleaseCapsuleProjection {
  param([string]$RelativePath, [string]$Text)
  $path = Join-Path $repo $RelativePath
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) {
      [IO.File]::ReadAllText($path).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
    } else { '' }
    if ($actual -cne $Text) { throw "[mir4-m42-02-release-capsule-stale] $RelativePath" }
    return
  }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $parent)
  }
  [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202ReleaseCapsuleGitText {
  param([string]$Commit, [string]$RelativePath)
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'git'
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  [void]$start.ArgumentList.Add('-C')
  [void]$start.ArgumentList.Add($repo)
  [void]$start.ArgumentList.Add('show')
  [void]$start.ArgumentList.Add($Commit + ':' + $RelativePath)
  $process = [Diagnostics.Process]::Start($start)
  $text = $process.StandardOutput.ReadToEnd()
  $errorText = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "[mir4-m42-02-release-capsule-git-source] $Commit|$RelativePath|$errorText" }
  $text.Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
}

function Get-MIR4M4202ReleaseCapsuleSlice {
  param([string[]]$Lines, [int]$Start, [int]$End)
  (@($Lines[($Start - 1)..($End - 1)]) -join [char]10) + [char]10
}

function Get-MIR4M4202ReleaseCapsuleAst {
  param([string]$RelativePath)
  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath), [ref]$tokens, [ref]$errors)
  if (@($errors).Count -ne 0) { throw "[mir4-m42-02-release-capsule-parse] $RelativePath" }
  $ast
}

function Get-MIR4M4202ReleaseCapsuleGitTextSha256 {
  param([string]$Commit, [string]$RelativePath)
  Get-MIR4Sha256String -Value (Get-MIR4M4202ReleaseCapsuleGitText -Commit $Commit -RelativePath $RelativePath)
}

function ConvertTo-MIR4M4202ReleaseCapsuleJson {
  param($Record)
  (($Record | ConvertTo-Json -Depth 100).Replace(([string][char]13 + [char]10), [string][char]10) + [string][char]10)
}

$startingCommit = '941844acfd7e9c8af40109a2cf7e9cab50c377cd'
$startingTree = '64bde62adf06dc3710ab1cb72b03e8309da258f0'
$sourcePath = 'tools/lib/mir4/ReleaseCapsule.ps1'
$sourceSha256 = '6F35762B10F47084B71759E2A36B9163FF1B83CB336B325D67A48D426CCDB51D'
$sourceText = Get-MIR4M4202ReleaseCapsuleGitText -Commit $startingCommit -RelativePath $sourcePath
$sourceLines = @($sourceText.Split([char]10))
if (-not $sourceText.EndsWith([string][char]10) -or
    (Get-MIR4Sha256String -Value $sourceText) -cne $sourceSha256 -or
    $sourceLines.Count -ne 1357) {
  throw '[mir4-m42-02-release-capsule-starting-source]'
}

$moduleRoot = 'tools/lib/mir4/release-capsule'
$moduleSpecs = @(
  [pscustomobject]@{ name = 'CoreRecords.ps1'; role = 'repository resolution, immutable JSON records, object paths, and stream hashing'; start = 19; end = 79 },
  [pscustomobject]@{ name = 'CustodyInventory.ps1'; role = 'private custody inventory construction and validation'; start = 81; end = 217 },
  [pscustomobject]@{ name = 'SourceArchiveAndDescriptors.ps1'; role = 'deterministic git source archives and capsule descriptor projection'; start = 219; end = 334 },
  [pscustomobject]@{ name = 'SupportRecords.ps1'; role = 'support-record construction and archive inventory'; start = 336; end = 488 },
  [pscustomobject]@{ name = 'ArchiveReadingAndClosure.ps1'; role = 'bounded archive entry reading, manifest loading, and role closure'; start = 490; end = 543 },
  [pscustomobject]@{ name = 'CapsuleConstruction.ps1'; role = 'content-addressed release capsule construction'; start = 545; end = 891 },
  [pscustomobject]@{ name = 'CapsuleVerification.ps1'; role = 'capsule, provenance, preview asset, and publisher-admission verification'; start = 893; end = 1100 },
  [pscustomobject]@{ name = 'CapsuleRestore.ps1'; role = 'contained offline capsule restoration and receipt construction'; start = 1102; end = 1356 }
)

$expectedModules = @{}
foreach ($spec in $moduleSpecs) {
  $text = Get-MIR4M4202ReleaseCapsuleSlice -Lines $sourceLines -Start $spec.start -End $spec.end
  $relative = "$moduleRoot/$($spec.name)"
  $expectedModules[$relative] = $text
  Set-MIR4M4202ReleaseCapsuleProjection -RelativePath $relative -Text $text
}

$setupBlock = Get-MIR4M4202ReleaseCapsuleSlice -Lines $sourceLines -Start 1 -End 18
$facadeTail = @'
. (Join-Path $PSScriptRoot 'release-capsule/CoreRecords.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CustodyInventory.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/SourceArchiveAndDescriptors.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/SupportRecords.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/ArchiveReadingAndClosure.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CapsuleConstruction.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CapsuleVerification.ps1')
. (Join-Path $PSScriptRoot 'release-capsule/CapsuleRestore.ps1')
'@.Replace(([string][char]13 + [char]10), [string][char]10)
$facade = $setupBlock + $facadeTail
Set-MIR4M4202ReleaseCapsuleProjection -RelativePath $sourcePath -Text $facade

$predecessorPath = 'releases/migrations/MIR4-M42-02-Offline-Custody-DecompositionV1.json'
$predecessor = Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath) | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$predecessor.status -cne 'M42-02-PS8-OFFLINE-CUSTODY-DECOMPOSED' -or
    [string]$predecessor.next_fixed_point -cne 'M42-02-PS9-RELEASE-CAPSULE') {
  throw '[mir4-m42-02-release-capsule-predecessor]'
}
$characterizationPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$characterization = Get-Content -Raw -LiteralPath (Join-Path $repo $characterizationPath) | ConvertFrom-Json -Depth 100 -DateKind String
$characterized = @($characterization.tracked_files | Where-Object { [string]$_.path -ceq $sourcePath })
if ($characterized.Count -ne 1 -or [string]$characterized[0].sha256 -cne $sourceSha256) {
  throw '[mir4-m42-02-release-capsule-characterization]'
}

$modules = @(
  foreach ($spec in $moduleSpecs) {
    $relative = "$moduleRoot/$($spec.name)"
    $actual = [IO.File]::ReadAllText((Join-Path $repo $relative)).Replace(([string][char]13 + [char]10), [string][char]10).Replace([string][char]13, [string][char]10)
    if ($actual -cne [string]$expectedModules[$relative]) { throw "[mir4-m42-02-release-capsule-segment] $relative" }
    $ast = Get-MIR4M4202ReleaseCapsuleAst -RelativePath $relative
    $lineCount = @([IO.File]::ReadAllLines((Join-Path $repo $relative))).Count
    if ($lineCount -gt 400) { throw "[mir4-m42-02-release-capsule-module-size] $relative|$lineCount" }
    [pscustomobject][ordered]@{
      path = $relative
      role = [string]$spec.role
      source_lines = [pscustomobject][ordered]@{ start = [int]$spec.start; end = [int]$spec.end }
      sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative)
      hash_mode = 'canonical-text-v1'
      lines = $lineCount
      function_count = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count
      parse_errors = 0
    }
  }
)
if ($modules.Count -ne 8 -or (@($modules | Measure-Object function_count -Sum).Sum) -ne 19) {
  throw '[mir4-m42-02-release-capsule-module-contract]'
}

$facadeAst = Get-MIR4M4202ReleaseCapsuleAst -RelativePath $sourcePath
$facadeLines = @([IO.File]::ReadAllLines((Join-Path $repo $sourcePath))).Count
if (@($facadeAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count -ne 0 -or
    $facadeLines -gt 80) {
  throw '[mir4-m42-02-release-capsule-facade]'
}
$oldTokens = $null
$oldErrors = $null
$oldAst = [Management.Automation.Language.Parser]::ParseInput($sourceText, [ref]$oldTokens, [ref]$oldErrors)
$oldFunctions = @($oldAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$currentFunctions = @(
  foreach ($spec in $moduleSpecs) {
    (Get-MIR4M4202ReleaseCapsuleAst -RelativePath "$moduleRoot/$($spec.name)").FindAll(
      { param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true
    ) | ForEach-Object { $_.Name }
  }
)
$oldFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $oldFunctions)
$currentFunctionSha = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $currentFunctions)
$setupBlockSha = Get-MIR4Sha256String -Value $setupBlock
if ($oldFunctions.Count -ne 19 -or
    ($oldFunctions -join '|') -cne ($currentFunctions -join '|') -or
    $oldFunctionSha -cne $currentFunctionSha -or
    -not $facade.StartsWith($setupBlock, [StringComparison]::Ordinal)) {
  throw '[mir4-m42-02-release-capsule-public-contract]'
}

$inventory = if ($Check) {
  Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
} else {
  Update-MIR4CommandInventoryV1 -RepoRoot $repo
}
if ([int]$inventory.command_count -ne 85 -or
    [int]$inventory.summary.unknown -ne 0 -or
    [int]$inventory.summary.duplicate_command_keys -ne 0) {
  throw '[mir4-m42-02-release-capsule-inventory]'
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
  'tests/mir4/Test-MIR4ReleaseCapsule.ps1',
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
  'tools/lib/mir4/ReleaseCapsule.ps1',
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1',
  'validation/tests.yml'
)
$evolvedBindings = @(
  $evolvedPaths | ForEach-Object {
    [pscustomobject][ordered]@{
      path = $_
      previous_sha256 = Get-MIR4M4202ReleaseCapsuleGitTextSha256 -Commit $startingCommit -RelativePath $_
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
  kind = 'MIR4M4202ReleaseCapsuleDecompositionV1'
  status = 'M42-02-PS9-RELEASE-CAPSULE-DECOMPOSED'
  starting_dev = [pscustomobject][ordered]@{ commit = $startingCommit; tree = $startingTree }
  predecessor = [pscustomobject][ordered]@{
    work_package = 'M42-02-PS8-OFFLINE-CUSTODY'
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
    lines = 1356
    function_count = 19
    evolution_chain = @()
  }
  decomposition = [pscustomobject][ordered]@{
    responsibility = 'release-capsule'
    facade = [pscustomobject][ordered]@{
      path = $sourcePath
      previous_sha256 = $sourceSha256
      current_sha256 = Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $sourcePath)
      hash_mode = 'canonical-text-v1'
      previous_lines = 1356
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
    ordered_source_slices_preserved = $true
    function_names_and_order_unchanged = $true
    setup_unchanged = $true
    module_load_order_explicit = $true
    custody_inventory_unchanged = $true
    source_archive_unchanged = $true
    descriptor_projection_unchanged = $true
    support_records_unchanged = $true
    role_closure_unchanged = $true
    capsule_construction_unchanged = $true
    capsule_verification_unchanged = $true
    provenance_binding_unchanged = $true
    preview_asset_verification_unchanged = $true
    publisher_admission_unchanged = $true
    offline_restore_unchanged = $true
    platform_projections_regenerated = $true
    post_cutover_package_non_interference_assertion = $true
    pre_freeze_authority_chain_extended_for_ps9 = $true
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
  next_fixed_point = 'M42-02-PS10-CONTROL-EXECUTOR'
  record_sha256 = ''
}
$receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
$json = ConvertTo-MIR4M4202ReleaseCapsuleJson -Record $receipt
if (-not ($json | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-release-capsule-decomposition-v1.schema.json'))) {
  throw '[mir4-m42-02-release-capsule-receipt-schema]'
}
Set-MIR4M4202ReleaseCapsuleProjection -RelativePath 'releases/migrations/MIR4-M42-02-Release-Capsule-DecompositionV1.json' -Text $json
$receipt
