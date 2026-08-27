. (Join-Path $PSScriptRoot '../../mir/domain/canonicalization/CanonicalJsonV1.ps1')

$script:MIR4PlatformInputPaths = @(
  '.gitattributes',
  'mir.toml',
  'spec/platform/mir4-preview-v0/platform.json',
  'spec/platform/mir4-preview-v0/release-dag.json',
  'spec/api/mir4-v0/contracts.json',
  'spec/api/mir4-v1/contracts.json',
  'spec/api/mir4-v1/schema-namespace.json',
  'spec/api/mir4-v1/diagnostics.json',
  'spec/api/mir4-v1/compatibility.json',
  'spec/canonicalization/mir-canonical-json-v1.json',
  'spec/canonicalization/reference/mir4_canonical_json_v1.py',
  'fixtures/mir4-canonical-json-v1/vectors.json',
  '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json',
  '.mir/releases/waves/mir4-r0/MIR4-Target-Compiler-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
  'spec/schemas/mir4-compilation-run-v1.schema.json',
  'spec/schemas/mir4-whole-platform-programme-v1.schema.json',
  'spec/schemas/mir4-technology-acceptance-queue-v1.schema.json',
  '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-F210-MEP-Discovery-ContractV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json',
  '.mir/releases/waves/mir4-r0/MIR4-Compatibility-Campaign-SOL07V1.json',
  'spec/compatibility/claims.json',
  'spec/schemas/mir4-runtime-state-matrix-v1.schema.json',
  'spec/schemas/mir4-migration-graph-matrix-v1.schema.json',
  'spec/schemas/mir4-continuity-bundle-v1.schema.json',
  'spec/schemas/mir4-canonical-recipe-fact-input-v1.schema.json',
  'spec/schemas/mir4-process-ir-v1.schema.json',
  'spec/schemas/mir4-effect-channel-registry-v1.schema.json',
  'spec/schemas/mir4-synthesis-maturity-matrix-v1.schema.json',
  'spec/schemas/mir4-inspection-bundle-v1.schema.json',
  'spec/schemas/mir4-compatibility-subject-ledger-v1.schema.json',
  'spec/schemas/mir4-compatibility-factory-plan-v1.schema.json',
  'spec/schemas/mir4-inspector-workbench-result-v1.schema.json',
  'spec/schemas/mir4-historical-museum-matrix-v1.schema.json',
  'spec/schemas/mir4-successor-host-result-v1.schema.json',
  '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json',
  '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json',
  '.mir/compatibility.yml',
  '.mir/streams.yml',
  '.mir/fixtures.yml',
  '.mir/modules.yml',
  '.mir/technology-lifecycle.json',
  '.mir/technology-governance.json',
  '.mir/control/repository-fixed-point.json',
  'governance/repository/migrations/fixed-point-tooling-v1.json',
  'contracts/repository/mir4-repository-migration-authority-v1.schema.json',
  'contracts/repository/mir4-repository-migration-proof-v1.schema.json',
  'contracts/repository/mir4-repository-migration-receipt-v1.schema.json',
  'assurance/repository/fixed-point-tooling-v1.json',
  'governance/repository/migrations/canonicalization-tooling-v1.json',
  'contracts/repository/mir4-canonicalization-migration-authority-v1.schema.json',
  'contracts/repository/mir4-canonicalization-migration-proof-v1.schema.json',
  'contracts/repository/mir4-canonicalization-migration-receipt-v1.schema.json',
  'assurance/repository/canonicalization-tooling-v1.json',
  'governance/repository/migrations/diagnostics-tooling-v1.json',
  'contracts/repository/mir4-diagnostics-migration-authority-v1.schema.json',
  'contracts/repository/mir4-diagnostics-migration-proof-v1.schema.json',
  'contracts/repository/mir4-diagnostics-migration-receipt-v1.schema.json',
  'assurance/repository/diagnostics-tooling-v1.json',
  'governance/repository/migrations/target-key-tooling-v1.json',
  'contracts/repository/mir4-target-key-migration-authority-v1.schema.json',
  'contracts/repository/mir4-target-key-migration-proof-v1.schema.json',
  'contracts/repository/mir4-target-key-migration-receipt-v1.schema.json',
  'assurance/repository/target-key-tooling-v1.json',
  'governance/repository/migrations/whole-platform-tooling-v1.json',
  'contracts/repository/mir4-whole-platform-migration-authority-v1.schema.json',
  'contracts/repository/mir4-whole-platform-migration-proof-v1.schema.json',
  'contracts/repository/mir4-whole-platform-migration-receipt-v1.schema.json',
  'assurance/repository/whole-platform-tooling-v1.json',
  'governance/repository/migrations/technology-acceptance-tooling-v1.json',
  'contracts/repository/mir4-technology-acceptance-migration-authority-v1.schema.json',
  'contracts/repository/mir4-technology-acceptance-migration-proof-v1.schema.json',
  'contracts/repository/mir4-technology-acceptance-migration-receipt-v1.schema.json',
  'assurance/repository/technology-acceptance-tooling-v1.json',
  'governance/repository/migrations/module-sdk-mep-tooling-v1.json',
  'contracts/repository/mir4-module-sdk-mep-migration-authority-v1.schema.json',
  'contracts/repository/mir4-module-sdk-mep-migration-proof-v1.schema.json',
  'contracts/repository/mir4-module-sdk-mep-migration-receipt-v1.schema.json',
  'assurance/repository/module-sdk-mep-tooling-v1.json',
  'tools/mir/application/extensions/ExperimentalApiSdk.ps1',
  'tools/mir/application/extensions/ExtensionDeveloperExperience.ps1',
  'tools/mir/application/extensions/MepDiscovery.ps1',
  'tools/mir/application/extensions/SdkV1.ps1',
  'tools/mir/cli/Invoke-MIR4ExperimentalApi.ps1',
  'tools/mir/cli/Invoke-MIR4Extension.ps1',
  'tools/mir/cli/Export-MIR4ModuleEcosystemRecords.ps1',
  'tools/lib/mir4/ExperimentalApiSdk.ps1',
  'tools/lib/mir4/ExtensionDeveloperExperience.ps1',
  'tools/lib/mir4/MepDiscovery.ps1',
  'tools/commands/mir4/Invoke-MIR4Extension.ps1',
  'tools/lib/mir4/SdkV1.ps1',
  'tools/templates/mir4/sdk-v1/powershell/MIR4.Api.V1.psm1',
  'tools/templates/mir4/sdk-v1/python/mir4_api_v1.py',
  'tools/templates/mir4/sdk-v1/typescript/index.mjs',
  'tools/templates/mir4/sdk-v1/typescript/index.ts',
  'tools/templates/mir4/sdk-v1/typescript/package.json',
  'tools/templates/mir4/sdk-v1/lua/mir4_api_v1.lua',
  'tools/templates/mir4/sdk-v1/lua/mir4_api_v1.luals.lua',
  'tools/templates/mir4/sdk-v1/conformance/Invoke-MIR4SdkV1Conformance.ps1',
  'spec/schemas/preview/mir4-sdk-v1-conformance-corpus.schema.json',
  'tools/lib/mir4/CanonicalJsonV1.ps1',
  'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1',
  'tools/mir/domain/diagnostics/DiagnosticsV1.ps1',
  'tools/lib/mir4/DiagnosticsV1.ps1',
  'tools/mir/domain/targets/TargetKey.ps1',
  'tools/lib/mir4/PlatformPreview.ps1',
  'spec/schemas/preview/mir4-extension-lock-v1.schema.json',
  'spec/schemas/preview/mir4-extension-diff-v1.schema.json',
  'spec/schemas/preview/mir4-f210-mod-data-snapshot-v1.schema.json',
  'spec/schemas/preview/mir4-f210-mep-discovery-result-v1.schema.json',
  'docs/reference/mir4-first-extension.md',
  'docs/reference/mir4-f210-mep-discovery.md',
  'tools/mir/domain/safety/SafetyKernel.ps1',
  'tools/mir/domain/policy/PolicyEngine.ps1',
  'tools/mir/application/compiler/NormalizedCompiler.ps1',
  'tools/mir/application/targets/TargetCompiler.ps1',
  'tools/lib/mir4/TargetCompiler.ps1',
  'tools/mir/application/compiler/CompilationRun.ps1',
  'tools/mir/application/runtime/RuntimeStateModel.ps1',
  'tools/mir/application/extensions/ModuleEcosystem.ps1',
  'tools/lib/mir4/ModuleEcosystem.ps1',
  'tools/lib/mir4/ProcessIR.ps1',
  'tools/lib/mir4/SupportAssessment.ps1',
  'tools/lib/mir4/CompatibilityIndex.ps1',
  'tools/lib/mir4/CompatibilityFactory.ps1',
  'tools/lib/mir4/EnvironmentEvidence.ps1',
  'tools/lib/mir4/Inspector.ps1',
  'tools/commands/mir4/Invoke-MIR4EnvironmentEvidence.ps1',
  'spec/schemas/preview/mir4-environment-lock-v1.schema.json',
  'spec/schemas/preview/mir4-environment-diff-v1.schema.json',
  'spec/schemas/preview/mir4-support-bundle-v1.schema.json',
  'docs/reference/mir4-environment-evidence.md',
  'tools/lib/mir4/HistoricalSuccession.ps1',
  'tools/lib/mir4/SuccessorHost.ps1',
  'tools/lib/mir4/ReleaseDag.ps1',
  'tools/lib/mir4/RepositoryFixedPoint.ps1',
  'tools/mir/domain/repository/RepositoryFixedPoint.ps1',
  'tools/mir/ports/repository/RepositoryInventory.ps1',
  'tools/mir/adapters/repository/GitRepositoryInventory.ps1',
  'tools/mir/application/repository/RepositoryFixedPoint.ps1',
  'tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1',
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tools/mir/application/canonicalization/CanonicalizationMigration.ps1',
  'tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1',
  'tests/canonicalization/Test-MIR4CanonicalizationDiagnostics.ps1',
  'tests/canonicalization/Test-MIR4CanonicalizationMigration.ps1',
  'tools/mir/application/migration/AppendOnlyAuthorityMigration.ps1',
  'tools/mir/application/diagnostics/DiagnosticsMigration.ps1',
  'tools/mir/cli/Invoke-MIR4DiagnosticsMigration.ps1',
  'tests/diagnostics/Test-MIR4DiagnosticsV1.ps1',
  'tests/diagnostics/Test-MIR4DiagnosticsMigration.ps1',
  'tools/mir/application/targets/TargetKeyMigration.ps1',
  'tools/mir/cli/Invoke-MIR4TargetKeyMigration.ps1',
  'tests/targets/Test-MIR4TargetKey.ps1',
  'tests/targets/Test-MIR4TargetKeyMigration.ps1',
  'tools/lib/mir4/TargetKey.ps1',
  'tools/mir/application/targets/TargetCompilerMigration.ps1',
  'tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1',
  'tests/targets/Test-MIR4TargetCompiler.ps1',
  'tests/targets/Test-MIR4TargetCompilerMigration.ps1',
  'tools/mir/application/platform/WholePlatform.ps1',
  'tools/mir/application/platform/WholePlatformMigration.ps1',
  'tools/mir/cli/Invoke-MIR4WholePlatformMigration.ps1',
  'tests/platform/Test-MIR4WholePlatform.ps1',
  'tests/platform/Test-MIR4WholePlatformMigration.ps1',
  'tools/lib/mir4/WholePlatform.ps1',
  'tools/commands/mir4/Invoke-MIR4WholePlatform.ps1',
  'tools/mir/application/technology/TechnologyAcceptance.ps1',
  'tools/mir/application/technology/TechnologyAcceptanceMigration.ps1',
  'tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1',
  'tests/technology/Test-MIR4TechnologyAcceptance.ps1',
  'tests/technology/Test-MIR4TechnologyAcceptanceMigration.ps1',
  'tools/lib/mir4/TechnologyAcceptance.ps1'
)

function Get-MIR4PlatformRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4PlatformFileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-MIR4PlatformBytesSha256 {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}

function Get-MIR4PlatformInputSha256 {
  param([Parameter(Mandatory)][string]$Path)
  $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
  try { $text = $strictUtf8.GetString([IO.File]::ReadAllBytes($Path)) }
  catch { throw "[mir4-platform-input-encoding] $Path" }
  $canonical = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($canonical))).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}

function ConvertTo-MIR4PlatformCanonicalValue {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
      $result[$key] = ConvertTo-MIR4PlatformCanonicalValue $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
      $result[$property.Name] = ConvertTo-MIR4PlatformCanonicalValue $property.Value
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    Write-Output -NoEnumerate @($Value | ForEach-Object { ConvertTo-MIR4PlatformCanonicalValue $_ })
    return
  }
  return $Value
}

function ConvertTo-MIR4PlatformCanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ((ConvertTo-MIR4PlatformCanonicalValue $Value) | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR4PlatformDigest {
  param([Parameter(Mandatory)]$Value)
  $material = [ordered]@{}
  foreach ($property in $Value.PSObject.Properties) {
    if ($property.Name -ne 'digest') { $material[$property.Name] = $property.Value }
  }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $material))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return 'sha256:' + ([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()) }
  finally { $sha.Dispose() }
}

function Add-MIR4PlatformDigest {
  param([Parameter(Mandatory)]$Value)
  $Value.digest = Get-MIR4PlatformDigest $Value
  return $Value
}

function Get-MIR4PlatformInputs {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  return @(
    foreach ($relative in $script:MIR4PlatformInputPaths) {
      $path = Join-Path $repo $relative
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-platform-input-missing] $relative" }
      [ordered]@{ path=$relative; sha256=(Get-MIR4PlatformInputSha256 $path) }
    }
  )
}

function Get-MIR4PlatformTargetKey {
  param([Parameter(Mandatory)][string]$Code)
  return 'f' + $Code
}

function Get-MIR4PlatformDistributionVersion {
  param([Parameter(Mandatory)][string]$Code)
  return '4.0.' + $Code + '00'
}

function Get-MIR4PlatformPredecessorPath {
  param([AllowNull()][string]$Release)
  if ([string]::IsNullOrWhiteSpace($Release)) { return $null }
  return ".mir/releases/terminal/baselines/$Release/normalized-snapshot.json"
}

. (Join-Path $PSScriptRoot '../../mir/domain/safety/SafetyKernel.ps1')
. (Join-Path $PSScriptRoot '../../mir/domain/policy/PolicyEngine.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/compiler/NormalizedCompiler.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/targets/TargetCompiler.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/runtime/RuntimeStateModel.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/extensions/ModuleEcosystem.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/extensions/MepDiscovery.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/extensions/ExperimentalApiSdk.ps1')
. (Join-Path $PSScriptRoot 'ProcessIR.ps1')
. (Join-Path $PSScriptRoot 'Inspector.ps1')
. (Join-Path $PSScriptRoot 'CompatibilityFactory.ps1')
. (Join-Path $PSScriptRoot 'ReleaseDag.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/compiler/CompilationRun.ps1')

function Get-MIR4TargetProviderRecords {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return @(New-MIR4NormalizedTargetProviders -RepoRoot $RepoRoot)
}

function Get-MIR4CompilationRunRecords {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Providers)
  return @(New-MIR4NormalizedCompilationRuns -RepoRoot $RepoRoot -Providers $Providers)
}

function Get-MIR4RuntimeStateInventory {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return New-MIR4RuntimeStateInventory -RepoRoot $RepoRoot
}

function Get-MIR4ProcessIRInventory {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$PlatformSpec)
  return New-MIR4ProcessIRInventory -RepoRoot $RepoRoot -PlatformSpec $PlatformSpec
}

function Get-MIR4OpportunityCatalogue {
  param([Parameter(Mandatory)]$PlatformSpec,[Parameter(Mandatory)]$ProcessIR)
  return New-MIR4OpportunityCatalogue -PlatformSpec $PlatformSpec -ProcessIR $ProcessIR
}

function Get-MIR4MepSchema {
  param([Parameter(Mandatory)]$PlatformSpec)
  return [ordered]@{
    '$schema'='https://json-schema.org/draft/2020-12/schema'
    '$id'='https://mir.invalid/preview/mir4-mep-v0.schema.json'
    title='MIR Extension Protocol V0 Preview'
    type='object'; additionalProperties=$false
    required=@('kind','schema','extension_id','targets','fragments','canonicalization','digest')
    properties=[ordered]@{
      kind=@{ const='MIR4ExtensionEnvelopeV0' }
      schema=@{ const=0 }
      extension_id=@{ type='string'; pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$' }
      targets=@{ type='array'; minItems=1; maxItems=17; uniqueItems=$true; items=@{ type='string'; pattern='^f[0-9]{3}$' } }
      fragments=@{ type='array'; minItems=1; maxItems=64; items=@{ type='object'; additionalProperties=$false; required=@('id','kind','data'); properties=@{ id=@{type='string';pattern='^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'}; kind=@{enum=@($PlatformSpec.mep_fragments)}; data=@{type='object';maxProperties=64;additionalProperties=$true} } } }
      canonicalization=@{ const='mir-canonical-json-v0' }
      digest=@{ type='string'; pattern='^sha256:[0-9a-f]{64}$' }
    }
  }
}

function Test-MIR4MepForbiddenValue {
  param([Parameter(Mandatory)][AllowNull()]$Value, [Parameter(Mandatory)][string[]]$Forbidden, [string]$Path='$')
  if ($null -eq $Value) { return }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      if ([string]$property.Name -in $Forbidden) { throw "[mir4-mep-forbidden-field] $Path.$($property.Name)" }
      Test-MIR4MepForbiddenValue -Value $property.Value -Forbidden $Forbidden -Path "$Path.$($property.Name)"
    }
  } elseif ($Value -is [Collections.IDictionary]) {
    foreach ($key in $Value.Keys) {
      if ([string]$key -in $Forbidden) { throw "[mir4-mep-forbidden-field] $Path.$key" }
      Test-MIR4MepForbiddenValue -Value $Value[$key] -Forbidden $Forbidden -Path "$Path.$key"
    }
  } elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) { Test-MIR4MepForbiddenValue -Value $item -Forbidden $Forbidden -Path "$Path[$index]"; $index++ }
  }
}

function Test-MIR4MepEnvelope {
  param([Parameter(Mandatory)]$Envelope, [Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $spec = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/platform.json') | ConvertFrom-Json
  $schema = Join-Path $repo 'spec/schemas/preview/mir4-mep-v0.schema.json'
  try { $valid = (($Envelope | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schema -ErrorAction Stop) }
  catch { throw '[mir4-mep-schema] Envelope schema validation failed.' }
  if (-not $valid) { throw '[mir4-mep-schema] Envelope schema validation failed.' }
  Test-MIR4MepForbiddenValue -Value $Envelope -Forbidden @($spec.mep_forbidden_fields)
  $ids = @($Envelope.fragments | ForEach-Object { [string]$_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw '[mir4-mep-duplicate-fragment] Fragment IDs must be unique.' }
  if ([string]$Envelope.digest -cne (Get-MIR4PlatformDigest $Envelope)) { throw '[mir4-mep-digest] Envelope digest mismatch.' }
  return $true
}

function New-MIR4ReferenceExtension {
  $record = [pscustomobject][ordered]@{
    kind='MIR4ExtensionEnvelopeV0'; schema=0; extension_id='org.more-infinite-research.reference'; targets=@('f210','f200','f110','f100')
    fragments=@(
      [ordered]@{id='org.more-infinite-research.compatibility';kind='CompatibilityFragment';data=[ordered]@{subjects=@('reference-intermediate');disposition='preserve-opaque'}},
      [ordered]@{id='org.more-infinite-research.profile';kind='ProfileFragment';data=[ordered]@{profile='reference-safe';settings=@{}}},
      [ordered]@{id='org.more-infinite-research.proof';kind='ProofFragment';data=[ordered]@{fixtures=@('reference-positive');claim_level='load-checked'}},
      [ordered]@{id='org.more-infinite-research.presentation';kind='PresentationFragment';data=[ordered]@{title='MIR 4 V0 reference extension';summary='Data-only conformance consumer.'}},
      [ordered]@{id='org.more-infinite-research.capability';kind='CapabilityRequirement';data=[ordered]@{all_of=@('query.read','support.snapshot')}},
      [ordered]@{id='org.more-infinite-research.dependency';kind='ExtensionDependency';data=[ordered]@{extension_id='org.more-infinite-research.platform';constraint='v0-preview'}},
      [ordered]@{id='org.more-infinite-research.conflict';kind='ExtensionConflict';data=[ordered]@{extension_ids=@()}},
      [ordered]@{id='org.more-infinite-research.finalization';kind='FinalizationRequirement';data=[ordered]@{phase='after-normalization';writes_allowed=$false}}
    )
    canonicalization='mir-canonical-json-v0'; digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function Get-MIR4InspectorHtml {
  return @'
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MIR 4 Inspector V0 Preview</title><style>body{font:15px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#20242a}header{display:flex;gap:1rem;align-items:center}section{border:1px solid #ccd3db;border-radius:8px;padding:1rem;margin:1rem 0}pre{white-space:pre-wrap;overflow:auto;background:#f5f7f9;padding:1rem}.badge{padding:.2rem .5rem;border-radius:1rem;background:#fff0bf}dt{font-weight:700}dd{margin:0 0 .5rem}</style></head><body><header><h1>MIR 4 Inspector</h1><span class="badge">V0 preview · read only</span></header><p>Select a generated Query API, support, compilation, runtime, or ProcessIR JSON record. Nothing is uploaded or mutated.</p><input id="file" type="file" accept="application/json"><section><h2>Overview</h2><dl id="overview"></dl></section><section><h2>Capabilities</h2><pre id="capabilities">No snapshot loaded.</pre></section><section><h2>Research streams</h2><pre id="streams">No snapshot loaded.</pre></section><section><h2>Diagnostics</h2><pre id="diagnostics">No snapshot loaded.</pre></section><section><h2>Settings / profile</h2><pre id="profile">No snapshot loaded.</pre></section><button id="export" disabled>Export support snapshot</button><script>let value=null;const show=(id,v)=>document.getElementById(id).textContent=JSON.stringify(v??[],null,2);const overview=v=>{const root=document.getElementById('overview');root.replaceChildren();for(const key of ['kind','schema','maturity','digest']){const dt=document.createElement('dt'),dd=document.createElement('dd');dt.textContent=key;dd.textContent=String(v[key]??'');root.append(dt,dd)}};document.getElementById('file').onchange=async e=>{try{value=JSON.parse(await e.target.files[0].text());overview(value);const p=value.payload||value;show('capabilities',value.capabilities||p.capabilities);show('streams',p.streams||p.channels);show('diagnostics',p.diagnostics||value.diagnostics);show('profile',p.profile||p.settings||p.state_specs);document.getElementById('export').disabled=false}catch(error){value=null;show('diagnostics',{code:'mir4-inspector-invalid-json',message:String(error)});document.getElementById('export').disabled=true}};document.getElementById('export').onclick=()=>{const blob=new Blob([JSON.stringify(value,null,2)+'\n'],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='mir4-support-snapshot.json';a.click();URL.revokeObjectURL(a.href)};</script></body></html>
'@
}

function Get-MIR4PlatformGeneratedFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  . (Join-Path $repo 'tools/mir/application/extensions/ExperimentalApiSdk.ps1')
  $platform = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/platform.json') | ConvertFrom-Json
  $wholePlatform = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json') | ConvertFrom-Json
  $releaseDag = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/platform/mir4-preview-v0/release-dag.json') | ConvertFrom-Json
  Test-MIR4ReleaseDag -Dag $releaseDag | Out-Null
  $providers = @(Get-MIR4TargetProviderRecords $repo)
  $targetContracts = New-MIR4TargetContractSet -RepoRoot $repo
  $targetLaws = Test-MIR4TargetProviderLaws -RepoRoot $repo
  $providerProtocols = New-MIR4ProviderMicroProtocolMatrix -RepoRoot $repo
  $featureSettingCutover = New-MIR4FeatureSettingCutoverMatrix -RepoRoot $repo -Providers $providers
  $semanticMergeLaws = Test-MIR4SemanticMergeLaws -RepoRoot $repo
  $affectedTargets = New-MIR4AffectedTargetPlan -Providers $providers
  $runs = @(Get-MIR4CompilationRunRecords -RepoRoot $repo -Providers $providers)
  $runtime = Get-MIR4RuntimeStateInventory $repo
  $migration = New-MIR4MigrationGraphMatrix -RepoRoot $repo -Providers $providers -SourceIdentity $null
  $continuity = New-MIR4ContinuityBundle -RepoRoot $repo -Providers $providers -SourceIdentity $null -CandidateZip $null -RuntimeStateMatrix $runtime -MigrationGraphMatrix $migration
  $extensionV1 = New-MIR4ReferenceExtensionV1 -RepoRoot $repo
  $extensionClosureV1 = Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($extensionV1) -Target f210
  $continuity.module_extension_closure.external_extensions = [ordered]@{status='complete-preview';opaque_reference=$false;closure_digest=[string]$extensionClosureV1.digest;authority='.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json'}
  Add-MIR4PlatformDigest $continuity | Out-Null
  $w06 = New-MIR4W06Records -RepoRoot $repo -SourceIdentity $null
  $process = $w06.parity
  $effects = $w06.effects
  $opportunities = $w06.synthesis
  $compatibilityLedgerV1 = New-MIR4CompatibilitySubjectLedger -RepoRoot $repo -SourceIdentity $null
  $supportBundleV1 = New-MIR4ReferenceSupportBundleV1 -Ledger $compatibilityLedgerV1 -RepoRoot $repo -Target f210
  $environmentEvidenceV1 = New-MIR4ReferenceEnvironmentEvidenceV1 -RepoRoot $repo
  $compatibilityFactoryPlanV1 = New-MIR4CompatibilityFactoryPlanV1 -SupportBundle $supportBundleV1 -Ledger $compatibilityLedgerV1 -RepoRoot $repo -SourceIdentity $null
  $previewFactoryPackage = [pscustomobject][ordered]@{path='build/mir4/m4c02-inspector-compatibility/factory/mir4-compatibility-reference-v1.zip';bytes=0;sha256=$null;entry_count=0;status='not-built-platform-generation-is-nonpackaging'}
  $inspectorV1 = New-MIR4InspectorWorkbenchResultV1 -RepoRoot $repo -Ledger $compatibilityLedgerV1 -FactoryPlan $compatibilityFactoryPlanV1 -FactoryPackage $previewFactoryPackage -SourceIdentity $null
  $mepSchema = Get-MIR4MepSchema $platform
  $extension = New-MIR4ReferenceExtension
  $shadowExtensionRun = New-MIR4ShadowExtensionCompilation -RepoRoot $repo -TargetId 'f210' -Envelope $extension
  $shadowExtensionRunV1 = New-MIR4ShadowExtensionCompilationV1 -RepoRoot $repo -TargetId 'f210' -Envelope $extensionV1
  $processSafeFixture = [ordered]@{schema=0;kind='MIR4ProcessIRSafetyFixtureV0';id='bounded-reference-loop';expected_status='accepted-for-policy-evaluation';contribution=[ordered]@{subject='process.reference.bounded';operations=@('data-only-fragment');evidence=@('fixture:bounded-reference-loop');positive_cycle=$true;proven_bounded=$true;owner_opaque=$false;owner_rewrite=$false;requested_disposition='preserve'}}
  $processUnsafeFixture = [ordered]@{schema=0;kind='MIR4ProcessIRSafetyFixtureV0';id='unbounded-reference-loop';expected_status='rejected';expected_violation='unbounded-positive-cycle';contribution=[ordered]@{subject='process.reference.unbounded';operations=@('data-only-fragment');evidence=@('fixture:unbounded-reference-loop');positive_cycle=$true;proven_bounded=$false;owner_opaque=$false;owner_rewrite=$false;requested_disposition='handle'}}
  $primary = $providers | Where-Object { $_.id -eq 'f210' }
  $primaryRun = $runs | Where-Object { $_.target.id -eq 'f210' }
  $query = New-MIR4ApiRecord -Kind MIR4QuerySnapshotV0 -TargetId f210 -FactorioLine '2.1' -SourceVersion '4.0.0' -DistributionVersion '4.0.21000' -Capabilities @('query.read','support.snapshot','streams.read','diagnostics.read','settings.read') -Payload ([ordered]@{ provider=$primary; compilation=$primaryRun; streams=[ordered]@{ authority='.mir/streams.yml'; mode='read-only' }; diagnostics=@(); profile=[ordered]@{ maturity='preview'; mutation_allowed=$false } })
  $support = New-MIR4ApiRecord -Kind MIR4SupportSnapshotV0 -TargetId f210 -FactorioLine '2.1' -SourceVersion '4.0.0' -DistributionVersion '4.0.21000' -Capabilities @('support.snapshot') -Payload ([ordered]@{ target=$primary; maturity='candidate-programme-only'; public_claim=$false; evidence=@('target-provider','compilation-run','runtime-state-inventory','process-ir-parity-result') })
  $components = @($platform.components | ForEach-Object { "| ``$($_.id)`` | $($_.maturity) | $($_.mode) |" }) -join "`n"
  $generatedDoc = "---`ntitle: `"MIR 4 Platform Component Matrix`"`nstatus: current`napplies_to: `"4.0.0 $($wholePlatform.programme_id)`"`naudience: developer`ndoc_type: reference`nowner: mir-maintainers`nlast_reviewed: 2026-08-24`nsupersedes: []`nsuperseded_by: []`nsource_of_truth_for:`n  - generated-mir4-component-maturity`n---`n# MIR 4 Platform Component Matrix`n`nGenerated from ``spec/platform/mir4-preview-v0/platform.json``. V1 is the current release-facing developer preview; V0 remains a superseded compatibility input for migration testing only.`n`n| Component | Maturity | Mode |`n| --- | --- | --- |`n$components`n`nThe conformance gate enforces the eight non-interference rules and keeps every non-stable surface outside player packages.`n"
  $psBinding = @'
# Generated standalone MIR Extension Protocol V0 preview binding.
function ConvertTo-MIR4MepCanonicalValue($Value){
  if($null-eq$Value){return $null}
  if($Value-is[string]-or$Value-is[bool]-or$Value-is[ValueType]){return $Value}
  if($Value-is[Collections.IDictionary]){$result=[ordered]@{};foreach($key in @($Value.Keys|ForEach-Object{[string]$_}|Sort-Object -CaseSensitive)){$result[$key]=ConvertTo-MIR4MepCanonicalValue $Value[$key]};return $result}
  if($Value-is[pscustomobject]){$result=[ordered]@{};foreach($property in @($Value.PSObject.Properties|Sort-Object Name -CaseSensitive)){$result[$property.Name]=ConvertTo-MIR4MepCanonicalValue $property.Value};return $result}
  if($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){Write-Output -NoEnumerate @($Value|ForEach-Object{ConvertTo-MIR4MepCanonicalValue $_});return}
  return $Value
}
function ConvertTo-MIR4MepCanonicalJson{param([Parameter(Mandatory)]$Value)(ConvertTo-MIR4MepCanonicalValue $Value)|ConvertTo-Json -Depth 100 -Compress}
function Get-MIR4MepDigest{param([Parameter(Mandatory)]$Value)$material=[ordered]@{};foreach($property in $Value.PSObject.Properties){if($property.Name-ne'digest'){$material[$property.Name]=$property.Value}};$bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4MepCanonicalJson $material));$sha=[Security.Cryptography.SHA256]::Create();try{'sha256:'+([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}}
function Test-MIR4MepForbiddenValue{param([Parameter(Mandatory)][AllowNull()]$Value,[string]$Path='$')$forbidden=@('callback','callbacks','compiler_context','data_raw','executor','prototype','prototype_write','safety_kernel');if($null-eq$Value){return};if($Value-is[pscustomobject]){foreach($property in $Value.PSObject.Properties){if([string]$property.Name-in$forbidden){throw "[mir4-mep-forbidden-field] $Path.$($property.Name)"};Test-MIR4MepForbiddenValue $property.Value "$Path.$($property.Name)"}}elseif($Value-is[Collections.IDictionary]){foreach($key in $Value.Keys){if([string]$key-in$forbidden){throw "[mir4-mep-forbidden-field] $Path.$key"};Test-MIR4MepForbiddenValue $Value[$key] "$Path.$key"}}elseif($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){$index=0;foreach($item in $Value){Test-MIR4MepForbiddenValue $item "$Path[$index]";$index++}}}
function Test-MIR4MepEnvelope{
  param([Parameter(Mandatory)]$Envelope,[string]$RepoRoot='')
  $schemaPath=if($RepoRoot-and(Test-Path -LiteralPath (Join-Path $RepoRoot 'spec/schemas/preview/mir4-mep-v0.schema.json') -PathType Leaf)){Join-Path $RepoRoot 'spec/schemas/preview/mir4-mep-v0.schema.json'}else{Join-Path $PSScriptRoot '../schema/mir4-mep-v0.schema.json'}
  try{$valid=(($Envelope|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schemaPath -ErrorAction Stop)}catch{throw '[mir4-mep-schema] Envelope schema validation failed.'}
  if(-not$valid){throw '[mir4-mep-schema] Envelope schema validation failed.'}
  Test-MIR4MepForbiddenValue $Envelope
  $ids=@($Envelope.fragments|ForEach-Object{[string]$_.id});if(@($ids|Sort-Object -Unique).Count-ne$ids.Count){throw '[mir4-mep-duplicate-fragment] Fragment IDs must be unique.'}
  if([string]$Envelope.digest-cne(Get-MIR4MepDigest $Envelope)){throw '[mir4-mep-digest] Envelope digest mismatch.'}
  return $true
}
Export-ModuleMember -Function Test-MIR4MepEnvelope,ConvertTo-MIR4MepCanonicalJson,Get-MIR4MepDigest
'@
  $luaBinding = @'
-- Generated MIR Extension Protocol V0 preview structural validator.
local M = {}
local kinds = {CompatibilityFragment=true,ProfileFragment=true,ProofFragment=true,PresentationFragment=true,CapabilityRequirement=true,ExtensionDependency=true,ExtensionConflict=true,FinalizationRequirement=true}
local forbidden = {callback=true,callbacks=true,compiler_context=true,data_raw=true,executor=true,prototype=true,prototype_write=true,safety_kernel=true}
local function scan(v)
  if type(v) ~= 'table' then return true end
  for k,item in pairs(v) do if forbidden[k] then return nil,'mir4-mep-forbidden-field' end; local ok,err=scan(item); if not ok then return nil,err end end
  return true
end
function M.validate(v)
  if type(v)~='table' or v.kind~='MIR4ExtensionEnvelopeV0' or v.schema~=0 or type(v.fragments)~='table' or #v.fragments<1 then return nil,'mir4-mep-schema' end
  local seen={}; for _,f in ipairs(v.fragments) do if type(f)~='table' or not kinds[f.kind] or type(f.id)~='string' or seen[f.id] or type(f.data)~='table' then return nil,'mir4-mep-schema' end; seen[f.id]=true end
  return scan(v)
end
return M
'@
  $inspectorPs = @'
param([Parameter(Mandatory)][string]$InputPath,[string]$OutputPath='')
$record=Get-Content -Raw -LiteralPath $InputPath|ConvertFrom-Json
$view=[ordered]@{kind=$record.kind;schema=$record.schema;maturity=$record.maturity;target=$record.target;capabilities=$record.capabilities;payload=$record.payload;diagnostics=$record.diagnostics;digest=$record.digest}
$json=$view|ConvertTo-Json -Depth 100
if($OutputPath){[IO.File]::WriteAllText($OutputPath,$json+"`n",[Text.UTF8Encoding]::new($false))}else{$json}
'@
  $conformancePs = @'
param([string]$SdkRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SdkRoot 'api-v0/powershell/MIR4.Api.V0.psm1') -Force
Import-Module (Join-Path $SdkRoot 'powershell/MIR4.MEP.V0.psm1') -Force
if((ConvertTo-MIR4ApiCanonicalJson ([ordered]@{empty=@()})) -cne '{"empty":[]}' -or (ConvertTo-MIR4MepCanonicalJson ([ordered]@{empty=@()})) -cne '{"empty":[]}'){throw '[mir4-sdk-canonical-empty-array]'}
$query=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference/query-snapshot-f210.json')|ConvertFrom-Json
Test-MIR4ApiRecord $query|Out-Null
$badApi=$query|ConvertTo-Json -Depth 100|ConvertFrom-Json;$badApi.digest='sha256:'+('0'*64)
try{Test-MIR4ApiRecord $badApi|Out-Null;throw '[mir4-sdk-negative-api-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-api-digest]')){throw}}
$extension=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference-extension/extension.json')|ConvertFrom-Json
Test-MIR4MepEnvelope $extension|Out-Null
$badMep=$extension|ConvertTo-Json -Depth 100|ConvertFrom-Json;$badMep.fragments[0].data|Add-Member -NotePropertyName callback -NotePropertyValue run
try{Test-MIR4MepEnvelope $badMep|Out-Null;throw '[mir4-sdk-negative-mep-accepted]'}catch{if(-not$_.Exception.Message.StartsWith('[mir4-mep-forbidden-field]')){throw}}
Write-Host '[ok] standalone MIR 4 SDK V0 conformance passed.'
'@
  $conformanceV1Ps = @'
param([string]$SdkRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $SdkRoot 'api-v1/powershell/MIR4.Api.V1.psm1') -Force
$available=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'api-v1/vectors/available-page-1.json')|ConvertFrom-Json
$unavailable=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'api-v1/vectors/unavailable-observation-f012.json')|ConvertFrom-Json
Test-MIR4ApiV1Availability $available|Out-Null
Test-MIR4ApiV1Availability $unavailable|Out-Null
$copy=Copy-MIR4ApiV1Data $available
$copy.items=@()
if(@($available.items).Count-eq 0){throw '[mir4-sdk-v1-copy-isolation]'}
$extension=Get-Content -Raw -LiteralPath (Join-Path $SdkRoot 'reference-extension-v1/extension.json')|ConvertFrom-Json
$schema=Join-Path $SdkRoot 'mep-v1/json-schema/mir4-mep-v1.schema.json'
if(-not(($extension|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $schema)){throw '[mir4-sdk-v1-mep-schema]'}
if(@($extension.fragments).Count-ne 12){throw '[mir4-sdk-v1-fragment-count]'}
Write-Host '[ok] standalone MIR 4 SDK V1 conformance passed.'
'@
  $lock = [ordered]@{ schema=1; kind='MIR4PlatformLockV1'; source_version='4.0.0'; programme_id=[string]$wholePlatform.programme_id; programme_execution_id='M4C02-09-24H'; candidate_state='pre-freeze-unallocated'; next_candidate='M4RC1'; canonicalization='mir-canonical-json/1'; inputs=(Get-MIR4PlatformInputs $repo); generated_by='tools/lib/mir4/PlatformPreview.ps1'; digest='' }
  $lockObject = [pscustomobject]$lock
  $lockObject.digest = Get-MIR4CanonicalDigestV1 -Value $lockObject -Domain 'mir4:platform-lock-v1' -OmitTopLevelDigest
  $files = [ordered]@{
    'mir.lock' = (ConvertTo-MIR4CanonicalJsonV1 $lockObject) + "`n"
    'spec/schemas/preview/mir4-mep-v0.schema.json' = (ConvertTo-MIR4PlatformCanonicalJson $mepSchema) + "`n"
    'sdk/preview/mir4/schema/mir4-mep-v0.schema.json' = (ConvertTo-MIR4PlatformCanonicalJson $mepSchema) + "`n"
    'sdk/preview/mir4/powershell/MIR4.MEP.V0.psm1' = $psBinding.Replace("`r`n","`n")
    'sdk/preview/mir4/lua/mir4_mep_v0.lua' = $luaBinding.Replace("`r`n","`n")
    'sdk/preview/mir4/reference/target-providers.json' = (ConvertTo-MIR4PlatformCanonicalJson ([ordered]@{schema=0;kind='MIR4TargetProviderSetV0';providers=$providers})) + "`n"
    'sdk/preview/mir4/reference/target-contracts.json' = (ConvertTo-MIR4PlatformCanonicalJson $targetContracts) + "`n"
    'sdk/preview/mir4/reference/target-provider-law-results.json' = (ConvertTo-MIR4PlatformCanonicalJson $targetLaws) + "`n"
    'sdk/preview/mir4/reference/affected-target-plan.json' = (ConvertTo-MIR4PlatformCanonicalJson $affectedTargets) + "`n"
    'sdk/preview/mir4/reference/compilation-runs.json' = (ConvertTo-MIR4PlatformCanonicalJson ([ordered]@{schema=1;kind='MIR4CompilationRunSetV1';runs=$runs})) + "`n"
    'sdk/preview/mir4/reference/feature-setting-cutover-matrix.json' = (ConvertTo-MIR4PlatformCanonicalJson $featureSettingCutover) + "`n"
    'sdk/preview/mir4/reference/provider-micro-protocol-matrix.json' = (ConvertTo-MIR4PlatformCanonicalJson $providerProtocols) + "`n"
    'sdk/preview/mir4/reference/merge-law-catalogue.json' = (ConvertTo-MIR4PlatformCanonicalJson $semanticMergeLaws) + "`n"
    'sdk/preview/mir4/reference/runtime-state-inventory.json' = (ConvertTo-MIR4PlatformCanonicalJson $runtime) + "`n"
    'sdk/preview/mir4/reference/migration-graph-matrix.json' = (ConvertTo-MIR4PlatformCanonicalJson $migration) + "`n"
    'sdk/preview/mir4/reference/continuity-bundle-template.json' = (ConvertTo-MIR4PlatformCanonicalJson $continuity) + "`n"
    'sdk/preview/mir4/reference/process-ir-inventory.json' = (ConvertTo-MIR4PlatformCanonicalJson $process) + "`n"
    'sdk/preview/mir4/reference/opportunity-catalogue.json' = (ConvertTo-MIR4PlatformCanonicalJson $opportunities) + "`n"
    'sdk/preview/mir4/reference/process-ir-parity-result.json' = (ConvertTo-MIR4PlatformCanonicalJson $process) + "`n"
    'sdk/preview/mir4/reference/effect-channel-registry-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $effects) + "`n"
    'sdk/preview/mir4/reference/synthesis-maturity-matrix-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $opportunities) + "`n"
    'sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $compatibilityLedgerV1) + "`n"
    'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $compatibilityFactoryPlanV1) + "`n"
    'sdk/preview/mir4/reference/inspection-bundle-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $inspectorV1.inspection_bundle) + "`n"
    'sdk/preview/mir4/reference/inspector-workbench-result-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $inspectorV1.result) + "`n"
    'sdk/preview/mir4/reference/support-bundle-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $supportBundleV1) + "`n"
    'sdk/preview/mir4/reference/release-dag.json' = (ConvertTo-MIR4PlatformCanonicalJson $releaseDag) + "`n"
    'sdk/preview/mir4/reference/query-snapshot-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $query) + "`n"
    'sdk/preview/mir4/reference/support-snapshot-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $support) + "`n"
    'sdk/preview/mir4/reference/shadow-extension-run-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $shadowExtensionRun) + "`n"
    'sdk/preview/mir4/reference/shadow-extension-run-v1-f210.json' = (ConvertTo-MIR4PlatformCanonicalJson $shadowExtensionRunV1) + "`n"
    'sdk/preview/mir4/reference-extension/extension.json' = (ConvertTo-MIR4PlatformCanonicalJson $extension) + "`n"
    'sdk/preview/mir4/reference-extension/README.md' = "# MIR 4 reference extension V0`n`nThis data-only extension exercises all eight MEP V0 fragment kinds and carries no prototype-write capability.`n"
    'sdk/preview/mir4/inspector/index.html' = (Get-MIR4InspectorHtml).Replace("`r`n","`n")
    'sdk/preview/mir4/inspector/Export-MIR4SupportSnapshot.ps1' = $inspectorPs.Replace("`r`n","`n")
    'sdk/preview/mir4/inspector/README.md' = "# MIR 4 Inspector V0`n`nOpen ``index.html`` locally and select a generated JSON snapshot. The browser-only viewer performs no upload and no mutation.`n"
    'sdk/preview/mir4/inspector-v1/index.html' = $inspectorV1.html.Replace("`r`n","`n")
    'sdk/preview/mir4/inspector-v1/Export-MIR4InspectionBundle.ps1' = $inspectorV1.exporter.Replace("`r`n","`n")
    'sdk/preview/mir4/inspector-v1/README.md' = $inspectorV1.readme.Replace("`r`n","`n")
    'sdk/preview/mir4/conformance/Invoke-MIR4SdkConformance.ps1' = $conformancePs.Replace("`r`n","`n")
    'sdk/preview/mir4/conformance-v1/Invoke-MIR4SdkV1Conformance.ps1' = $conformanceV1Ps.Replace("`r`n","`n")
    'sdk/preview/mir4/README.md' = "# MIR 4 SDK V1 developer preview`n`nRun ``.\conformance-v1\Invoke-MIR4SdkV1Conformance.ps1`` with PowerShell 7; use ``-RequireNode`` in CI. The 12-positive/18-negative corpus proves identical accepted/rejected cases and digests across available executable ports, both in-tree and from the clean extracted API archive. Current Lua, TypeScript/Node, Python, and PowerShell API bindings are under ``api-v1``; MEP bindings and V0-to-V1 migration helpers are under ``mep-v1``; bounded examples are under ``reference``. V0 remains a superseded compatibility input only. This preview is read-only, package-excluded, and may change before 1.0.`n"
    'fixtures/mir4-mep-v0/positive/reference-extension.json' = (ConvertTo-MIR4PlatformCanonicalJson $extension) + "`n"
    'fixtures/mir4-mep-v0/negative/forbidden-callback.json' = "{`"expected_diagnostic`":`"mir4-mep-forbidden-field`",`"kind`":`"MIR4ExtensionEnvelopeV0`",`"schema`":0,`"extension_id`":`"org.example.bad`",`"targets`":[`"f210`"],`"fragments`":[{`"id`":`"org.example.bad.fragment`",`"kind`":`"CompatibilityFragment`",`"data`":{`"callback`":`"run`"}}],`"canonicalization`":`"mir-canonical-json-v0`",`"digest`":`"sha256:0000000000000000000000000000000000000000000000000000000000000000`"}`n"
    'fixtures/mir4-process-ir-v0/positive/bounded-loop.json' = (ConvertTo-MIR4PlatformCanonicalJson $processSafeFixture) + "`n"
    'fixtures/mir4-process-ir-v0/negative/unbounded-loop.json' = (ConvertTo-MIR4PlatformCanonicalJson $processUnsafeFixture) + "`n"
    'sdk/preview/mir4/reference/environment-lock-f210-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $environmentEvidenceV1.f210) + [Environment]::NewLine
    'sdk/preview/mir4/reference/environment-lock-f200-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $environmentEvidenceV1.f200) + [Environment]::NewLine
    'sdk/preview/mir4/reference/environment-diff-f210-f200-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $environmentEvidenceV1.diff) + [Environment]::NewLine
    'sdk/preview/mir4/reference/support-bundle-minimized-v1.json' = (ConvertTo-MIR4PlatformCanonicalJson $environmentEvidenceV1.minimized) + [Environment]::NewLine
    'docs/reference/generated/mir4-platform-component-matrix.md' = $generatedDoc
  }
  foreach ($entry in (Get-MIR4ModuleEcosystemSdkFiles -RepoRoot $repo).GetEnumerator()) {
    $files[$entry.Key] = $entry.Value
  }
  return $files
}

function Invoke-MIR4PlatformGenerate {
  param([Parameter(Mandatory)][string]$RepoRoot, [switch]$Check)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $getStalePaths = {
    param([Parameter(Mandatory)]$Files)
    $stale = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Files.GetEnumerator()) {
      $path = Join-Path $repo $entry.Key
      $bytes = [Text.UTF8Encoding]::new($false).GetBytes(([string]$entry.Value).Replace("`r`n","`n"))
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
          -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path),[byte[]]$bytes)) {
        $stale.Add([string]$entry.Key)
      }
    }
    return $stale.ToArray()
  }

  $files = Get-MIR4PlatformGeneratedFiles $repo
  $stalePaths = @(& $getStalePaths $files)
  if ($Check) {
    if ($stalePaths.Count) { throw "[mir4-platform-stale] $($stalePaths[0])" }
    return $files.Keys
  }

  # Several projections consume other generated projections. Converge the on-disk
  # set so one successful generate invocation always leaves a checkable fixed point.
  $maximumPasses = 8
  for ($pass = 1; $pass -le $maximumPasses -and $stalePaths.Count; $pass++) {
    foreach ($relative in $stalePaths) {
      $path = Join-Path $repo $relative
      $bytes = [Text.UTF8Encoding]::new($false).GetBytes(([string]$files[$relative]).Replace("`r`n","`n"))
      New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
      [IO.File]::WriteAllBytes($path,$bytes)
    }
    $files = Get-MIR4PlatformGeneratedFiles $repo
    $stalePaths = @(& $getStalePaths $files)
  }
  if ($stalePaths.Count) {
    throw "[mir4-platform-generation-nonconvergent] passes=$maximumPasses stale=$($stalePaths -join ',')"
  }
  return $files.Keys
}

function Test-MIR4PlatformConformance {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check | Out-Null
  . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  $sourceBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  $positive = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-mep-v0/positive/reference-extension.json') | ConvertFrom-Json
  Test-MIR4MepEnvelope -Envelope $positive -RepoRoot $repo | Out-Null
  $negative = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-mep-v0/negative/forbidden-callback.json') | ConvertFrom-Json
  $expected = [string]$negative.expected_diagnostic
  $negative.PSObject.Properties.Remove('expected_diagnostic')
  try { Test-MIR4MepEnvelope -Envelope $negative -RepoRoot $repo | Out-Null; throw '[mir4-mep-negative-accepted] Forbidden callback fixture was accepted.' }
  catch { if (-not $_.Exception.Message.StartsWith("[$expected]")) { throw "[mir4-mep-negative-diagnostic] Expected $expected, got $($_.Exception.Message)" } }
  $sourceAfter = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($sourceBefore -cne $sourceAfter) { throw '[mir4-platform-package-mutation] Platform generation changed player package sources.' }
  $shipped = @(Get-MIRPackageSourceFiles -RepoRoot $repo)
  foreach ($prefix in @('sdk/','spec/','fixtures/','docs/','tools/','.mir/','mir.toml','mir.lock')) {
    if (@($shipped | Where-Object { $_.StartsWith($prefix) -or $_ -eq $prefix.TrimEnd('/') }).Count -gt 0) { throw "[mir4-platform-package-visible] $prefix" }
  }
  $runs = (Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/compilation-runs.json') | ConvertFrom-Json).runs
  $targetContracts = Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/target-contracts.json') | ConvertFrom-Json
  $targetLaws = Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/target-provider-law-results.json') | ConvertFrom-Json
  $semanticLaws = Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/merge-law-catalogue.json') | ConvertFrom-Json
  if (@($targetContracts.targets).Count -ne 17 -or -not $targetLaws.passed) { throw '[mir4-platform-target-compiler-incomplete]' }
  if (-not $semanticLaws.implemented_passed -or -not $semanticLaws.complete -or @($semanticLaws.deferred_owners).Count -ne 0) { throw '[mir4-platform-semantic-merge-laws]' }
  if (@($runs | Where-Object { $_.authoritative_output -or $_.mutation_capability }).Count -gt 0) { throw '[mir4-platform-shadow-interference] Shadow run acquired authority or mutation.' }
  if (@($runs | Where-Object { [string]$_.kind -ne 'MIR4CompilationRunV1' -or [int]$_.schema -ne 1 -or $_.runtime_state_mutation_capability -or $_.public_support_claim }).Count -gt 0) { throw '[mir4-platform-semantic-run-boundary]' }
  if (@($runs | Where-Object { -not $_.feature_manifest -or -not $_.setting_spec -or 'safety-kernel' -notin @($_.stages) -or 'policy-engine' -notin @($_.stages) }).Count -gt 0) { throw '[mir4-platform-normalized-run-incomplete]' }
  $releaseDag = Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/release-dag.json') | ConvertFrom-Json
  Test-MIR4ReleaseDag -Dag $releaseDag | Out-Null
  $accepted = Resolve-MIR4PolicyDisposition -Contribution ([pscustomobject]@{subject='reference-safe';operations=@('read-only-query');evidence=@('fixture:reference-positive');requested_disposition='preserve'})
  if ([string]$accepted.disposition -cne 'preserve' -or $accepted.mutation_authorized -or -not $accepted.review_required) { throw '[mir4-policy-safe-disposition]' }
  $rejected = Resolve-MIR4PolicyDisposition -Contribution ([pscustomobject]@{subject='reference-unsafe';operations=@('prototype-write');evidence=@('fixture:reference-negative');requested_disposition='handle'})
  if ([string]$rejected.disposition -cne 'fail-hard-safety' -or $rejected.mutation_authorized -or $rejected.safety.hard_safety_overridable) { throw '[mir4-policy-hard-safety-override]' }
  foreach ($fixturePath in @('fixtures/mir4-process-ir-v0/positive/bounded-loop.json','fixtures/mir4-process-ir-v0/negative/unbounded-loop.json')) {
    $fixture = Get-Content -Raw -LiteralPath (Join-Path $repo $fixturePath) | ConvertFrom-Json
    $decision = Resolve-MIR4PolicyDisposition -Contribution $fixture.contribution
    if ([string]$decision.safety.status -cne [string]$fixture.expected_status) { throw "[mir4-process-ir-fixture-status] $fixturePath" }
    $expectedViolation = if ($null -ne $fixture.PSObject.Properties['expected_violation']) { [string]$fixture.expected_violation } else { '' }
    if ($expectedViolation -and $expectedViolation -notin @($decision.safety.violations)) { throw "[mir4-process-ir-fixture-violation] $fixturePath" }
  }
  $w06 = New-MIR4W06Records -RepoRoot $repo -SourceIdentity $null
  if(-not$w06.parity.passed-or-not$w06.parity.bilateral_gate.passed-or-not$w06.effects.opaque_preserved-or$w06.synthesis.automatic_player_mutation){throw '[mir4-platform-w06-conformance]'}
  if([string]$w06.parity.exact_target_status-cne'CAPTURED-EXACT-F210-F200-PROCESSIR-PREVIEW-WITH-DECLARED-CUSTODY-BLOCKER'-or-not$w06.parity.exact_target_evidence.deterministic-or$w06.parity.exact_target_evidence.authoritative){throw '[mir4-platform-w06-exact-target-truth]'}
  $w07Ledger=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json')|ConvertFrom-Json -Depth 100
  Test-MIR4CompatibilitySubjectLedger -Ledger $w07Ledger -RepoRoot $repo|Out-Null
  $w07Bundle=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/inspection-bundle-v1.json')|ConvertFrom-Json -Depth 100
  Test-MIR4InspectionBundleV1 -Bundle $w07Bundle -RepoRoot $repo|Out-Null
  $w07Plan=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json')|ConvertFrom-Json -Depth 100
  Test-MIR4CompatibilityFactoryPlanV1 -Plan $w07Plan -RepoRoot $repo|Out-Null
  $w07Html=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/inspector-v1/index.html')
  Test-MIR4InspectorHtmlV1 -Html $w07Html|Out-Null
  if([string](Test-MIR4CompatibilityProvenance -Ledger $w07Ledger -RepoRoot $repo).status-cne'current'){throw '[mir4-platform-w07-provenance]'}
  $environmentLock=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/environment-lock-f210-v1.json')|ConvertFrom-Json -Depth 100
  $environmentDiff=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/environment-diff-f210-f200-v1.json')|ConvertFrom-Json -Depth 100
  $supportBundle=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/support-bundle-minimized-v1.json')|ConvertFrom-Json -Depth 100
  $mepDiscovery=Get-Content -Raw -LiteralPath (Join-Path $repo 'sdk/preview/mir4/reference/f210-mep-discovery-v1.json')|ConvertFrom-Json -Depth 100
  Test-MIR4EnvironmentLockV1 $environmentLock|Out-Null
  Test-MIR4EnvironmentDiffV1 $environmentDiff|Out-Null
  Test-MIR4SupportBundleV1 $supportBundle|Out-Null
  Test-MIR4F210MepDiscoveryResultV1 -RepoRoot $repo -Result $mepDiscovery|Out-Null
  if([string]$mepDiscovery.result-cne'shadow-complete'-or[int]$mepDiscovery.counts.accepted_records-ne2-or@($mepDiscovery.shadow_plans).Count-ne2){throw '[mir4-platform-t11-discovery]'}
  foreach($pair in @(
    @($environmentLock,'spec/schemas/preview/mir4-environment-lock-v1.schema.json'),
    @($environmentDiff,'spec/schemas/preview/mir4-environment-diff-v1.schema.json'),
    @($supportBundle,'spec/schemas/preview/mir4-support-bundle-v1.schema.json')
  )){
    if(-not(($pair[0]|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile (Join-Path $repo $pair[1]))){throw "[mir4-platform-environment-schema] $($pair[1])"}
  }
  return $true
}

function Write-MIR4DeterministicPreviewArchive {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$RootName,[Parameter(Mandatory)][string[]]$RelativePaths)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath -Parent) | Out-Null
  Add-Type -AssemblyName System.IO.Compression
  $stream = [IO.File]::Open($OutputPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    $zip = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try {
      $rows = @()
      foreach ($relative in @($RelativePaths | Sort-Object -Unique)) {
        $path = Join-Path $repo $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-preview-package-input] Missing $relative" }
        $bytes = [IO.File]::ReadAllBytes($path)
        $rows += [ordered]@{path=$relative.Replace('\','/');bytes=$bytes.Length;sha256=(Get-MIR4PlatformFileSha256 $path)}
        $entry = $zip.CreateEntry(($RootName + '/' + $relative.Replace('\','/')),[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
        $entryStream = $entry.Open(); try { $entryStream.Write($bytes,0,$bytes.Length) } finally { $entryStream.Dispose() }
      }
      $sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
      $sourceTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
      $sourceClean = @(& git -C $repo status --porcelain --untracked-files=no).Count -eq 0
      $contractRows = @($rows | Where-Object { $_.path -match '^spec/(?:api/|schemas/)' })
      $contractSet = [pscustomobject][ordered]@{kind='MIR4PreviewContractSetV1';files=$contractRows;digest=''}
      Add-MIR4PlatformDigest $contractSet | Out-Null
      $generatedMap = @($rows | Where-Object { $_.path -match '^sdk/preview/mir4/' } | ForEach-Object {
        [ordered]@{generated_path=$_.path;generator='tools/lib/mir4/PlatformPreview.ps1';checked_in=$true}
      })
      $sbom = [pscustomobject][ordered]@{
        spdxVersion='SPDX-2.3';dataLicense='CC0-1.0';SPDXID='SPDXRef-DOCUMENT';name=$RootName
        documentNamespace=("https://more-infinite-research.invalid/spdx/{0}/{1}" -f $RootName,$contractSet.digest.Replace('sha256:',''))
        creationInfo=[ordered]@{creators=@('Tool: MIR4 PlatformPreview.ps1');licenseListVersion='3.25'}
        packages=@([ordered]@{SPDXID='SPDXRef-Package';name=$RootName;versionInfo='4.0.0';downloadLocation='NOASSERTION';filesAnalyzed=$true;licenseConcluded='MPL-2.0';licenseDeclared='MPL-2.0';copyrightText='NOASSERTION'})
        files=@($rows | ForEach-Object -Begin {$index=0} -Process {$index++;[ordered]@{SPDXID=('SPDXRef-File-{0:d4}' -f $index);fileName=$_.path;checksums=@([ordered]@{algorithm='SHA256';checksumValue=$_.sha256});licenseConcluded='MPL-2.0';copyrightText='NOASSERTION'}})
      }
      $provenance = [pscustomobject][ordered]@{
        schema=1;kind='MIR4PreviewProvenanceV1';build_type='mir4-deterministic-preview-archive-v1'
        source=[ordered]@{repository='Julesc013/more-infinite-research';commit=$sourceCommit;tree=$sourceTree;clean=$sourceClean}
        builder=[ordered]@{id='tools/lib/mir4/PlatformPreview.ps1';network_required=$false}
        invocation=[ordered]@{asset_root=$RootName;candidate_state='pre-freeze-unallocated';production_candidate=$false}
        materials=$rows;subject_scope='archive-payload-before-containerization';contract_set_digest=$contractSet.digest
        source_freeze_authorized=$false;publication_authorized=$false
      }
      $sbomBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $sbom)+[Environment]::NewLine)
      $provenanceBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $provenance)+[Environment]::NewLine)
      foreach ($metadata in @(
        @{name='sbom.spdx.json';bytes=$sbomBytes},
        @{name='provenance.json';bytes=$provenanceBytes}
      )) {
        $metadataEntry = $zip.CreateEntry(($RootName + '/' + $metadata.name),[IO.Compression.CompressionLevel]::Optimal)
        $metadataEntry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
        $metadataStream = $metadataEntry.Open(); try { $metadataStream.Write($metadata.bytes,0,$metadata.bytes.Length) } finally { $metadataStream.Dispose() }
      }
      $manifestObject = [pscustomobject][ordered]@{
        schema=1;kind='MIR4PreviewAssetManifestV1';root=$RootName;source_version='4.0.0'
        programme_id='M4C10-WHOLE-4X-IN-4.0';programme_execution_id='M4C02-09-24H';candidate_state='pre-freeze-unallocated'
        production_candidate=$false;publication_authorized=$false
        source=[ordered]@{repository='Julesc013/more-infinite-research';commit=$sourceCommit;tree=$sourceTree;clean=$sourceClean}
        contract_set=$contractSet;files=$rows
        license_inventory=@([ordered]@{path='LICENSE';spdx_id='MPL-2.0'})
        generated_source_map=$generatedMap
        conformance=[ordered]@{status='passed-before-packaging';commands=@('mir4 platform check','mir4 platform conformance')}
        v0_migration_policy='V0 is superseded migration-only compatibility input and is not a public preview asset.'
        compatibility_notice='Developer preview: read-only, package-excluded, not API/SDK 1.0 stable, and not a Mod Portal payload.'
        embedded_metadata=@(
          [ordered]@{path='sbom.spdx.json';bytes=$sbomBytes.Length;sha256=(Get-MIR4PlatformBytesSha256 $sbomBytes)},
          [ordered]@{path='provenance.json';bytes=$provenanceBytes.Length;sha256=(Get-MIR4PlatformBytesSha256 $provenanceBytes)}
        )
        digest=''
      }
      Add-MIR4PlatformDigest $manifestObject | Out-Null
      $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $manifestObject)+"`n")
      $manifestEntry = $zip.CreateEntry(($RootName + '/manifest.json'),[IO.Compression.CompressionLevel]::Optimal)
      $manifestEntry.LastWriteTime = [DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
      $manifestStream = $manifestEntry.Open(); try { $manifestStream.Write($manifestBytes,0,$manifestBytes.Length) } finally { $manifestStream.Dispose() }
    } finally { $zip.Dispose() }
  } finally { $stream.Dispose() }
}

function New-MIR4PlatformPreviewPackages {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$OutputRoot='build/mir4/platform-preview')
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  Invoke-MIR4PlatformGenerate -RepoRoot $repo -Check | Out-Null
  Test-MIR4PlatformConformance -RepoRoot $repo | Out-Null
  $output = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
  $allowedOutput = [IO.Path]::GetFullPath((Join-Path $repo 'build')).TrimEnd('\') + '\'
  if (-not ($output + '\').StartsWith($allowedOutput,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-preview-output-boundary] $output" }
  $assetContract = @('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip')
  New-Item -ItemType Directory -Path $output -Force | Out-Null
  $unexpectedDirectories = @(Get-ChildItem -LiteralPath $output -Directory -Force)
  if ($unexpectedDirectories.Count -ne 0) { throw "[mir4-preview-output-directory] $($unexpectedDirectories[0].FullName)" }
  foreach ($staleFile in @(Get-ChildItem -LiteralPath $output -File -Force)) {
    Remove-Item -LiteralPath $staleFile.FullName -Force
  }
  $allSdk = @(Get-ChildItem -LiteralPath (Join-Path $repo 'sdk/preview/mir4') -Recurse -File) | ForEach-Object { [IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/') }
  $sdkV0 = @($allSdk | Where-Object { $_ -notmatch '/(?:mep-v1|api-v1|reference-extension-v1|inspector-v1)/' -and $_ -notmatch '/reference/(?:process-ir-parity-result|effect-channel-registry-v1|synthesis-maturity-matrix-v1|compatibility-subject-ledger-v1|compatibility-factory-plan-v1|inspection-bundle-v1|inspector-workbench-result-v1|support-bundle-v1)\.json$' })
  $sdkV0 = @($sdkV0 | Where-Object { $_ -notmatch '/reference/(?:environment-lock-f210-v1|environment-lock-f200-v1|environment-diff-f210-f200-v1|support-bundle-minimized-v1|f210-mep-discovery-v1)\.json$' })
  $sdkV1 = @($allSdk | Where-Object { $_ -match '/(?:mep-v1|api-v1|reference-extension-v1)/' -or $_ -match '/reference/(?:extension-closure-v1|extension-transport-plan-v1|shadow-extension-run-v1|f210-mep-discovery-v1)' })
  $apiV1 = @($allSdk | Where-Object { $_ -match '/api-v1/' })
  $mepV1 = @($allSdk | Where-Object { $_ -match '/mep-v1/' -or $_ -match '/reference/(?:extension-closure-v1|extension-transport-plan-v1|shadow-extension-run-v1|f210-mep-discovery-v1)' })
  $mepAuthority = Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
  $sets = [ordered]@{
    'mir4-sdk-v0-preview.zip' = @($sdkV0 + @('spec/api/mir4-v0/contracts.json','spec/schemas/preview/mir4-mep-v0.schema.json','docs/reference/generated/mir4-experimental-api-v0.md','docs/reference/mir4-mep-v0.md','docs/reference/mir4-sdk-v0-quickstart.md','docs/reference/mir4-api-sdk-v0-stability.md','LICENSE'))
    'mir4-api-sdk-v1-preview.zip' = @($apiV1 + @('sdk/preview/mir4/canonical-json-v1/powershell/MIR4.CanonicalJson.V1.psm1','sdk/preview/mir4/canonical-json-v1/python/mir4_canonical_json_v1.py','spec/api/mir4-v1/contracts.json','spec/api/mir4-v1/schema-namespace.json','spec/api/mir4-v1/diagnostics.json','spec/api/mir4-v1/compatibility.json','spec/canonicalization/mir-canonical-json-v1.json','fixtures/mir4-canonical-json-v1/vectors.json','spec/schemas/preview/mir4-api-v1-response.schema.json','spec/schemas/preview/mir4-canonical-json-v1.schema.json','spec/schemas/preview/mir4-canonical-json-vectors-v1.schema.json','spec/schemas/preview/mir4-schema-namespace-v1.schema.json','spec/schemas/preview/mir4-diagnostic-registry-v1.schema.json','spec/schemas/preview/mir4-preview-compatibility-policy-v1.schema.json','docs/reference/generated/mir4-api-sdk-v1.md','docs/reference/mir4-sdk-v1-quickstart.md','docs/reference/mir4-canonical-json-v1.md','LICENSE'))
    'mir4-platform-preview-v0.zip' = @('mir.toml','mir.lock','spec/platform/mir4-preview-v0/platform.json','spec/platform/mir4-preview-v0/release-dag.json','spec/schemas/mir4-compilation-run-v1.schema.json','spec/schemas/mir4-runtime-state-matrix-v1.schema.json','spec/schemas/mir4-migration-graph-matrix-v1.schema.json','spec/schemas/mir4-continuity-bundle-v1.schema.json','spec/schemas/mir4-canonical-recipe-fact-input-v1.schema.json','spec/schemas/mir4-process-ir-v1.schema.json','spec/schemas/mir4-effect-channel-registry-v1.schema.json','spec/schemas/mir4-synthesis-maturity-matrix-v1.schema.json','.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json','docs/architecture/mir4-platform-preview.md','docs/architecture/mir4-target-compiler.md','docs/architecture/mir4-semantic-compiler.md','docs/architecture/mir4-runtime-continuity.md','docs/architecture/mir4-processir-synthesis.md','docs/reference/generated/mir4-platform-component-matrix.md','sdk/preview/mir4/reference/target-providers.json','sdk/preview/mir4/reference/target-contracts.json','sdk/preview/mir4/reference/target-provider-law-results.json','sdk/preview/mir4/reference/affected-target-plan.json','sdk/preview/mir4/reference/compilation-runs.json','sdk/preview/mir4/reference/feature-setting-cutover-matrix.json','sdk/preview/mir4/reference/provider-micro-protocol-matrix.json','sdk/preview/mir4/reference/merge-law-catalogue.json','sdk/preview/mir4/reference/runtime-state-inventory.json','sdk/preview/mir4/reference/migration-graph-matrix.json','sdk/preview/mir4/reference/continuity-bundle-template.json','sdk/preview/mir4/reference/process-ir-parity-result.json','sdk/preview/mir4/reference/effect-channel-registry-v1.json','sdk/preview/mir4/reference/synthesis-maturity-matrix-v1.json','sdk/preview/mir4/reference/release-dag.json','sdk/preview/mir4/reference/shadow-extension-run-f210.json','fixtures/mir4-process-ir-v0/positive/bounded-loop.json','fixtures/mir4-process-ir-v0/negative/unbounded-loop.json','fixtures/mir4-process-ir-v1/positive/ordinary-safe.json','fixtures/mir4-process-ir-v1/positive/catalyst-container-bounded-cycle.json','fixtures/mir4-process-ir-v1/positive/recycling-recovery.json','fixtures/mir4-process-ir-v1/negative/unbounded-positive-cycle.json','fixtures/mir4-process-ir-v1/negative/unsupported-unknown.json','fixtures/mir4-process-ir-v1/permutation/scc-order-a.json','fixtures/mir4-process-ir-v1/permutation/scc-order-b.json','tools/mir/domain/safety/SafetyKernel.ps1','tools/mir/domain/policy/PolicyEngine.ps1','tools/mir/application/compiler/NormalizedCompiler.ps1','tools/mir/application/targets/TargetCompiler.ps1','tools/mir/application/compiler/CompilationRun.ps1','tools/mir/application/runtime/RuntimeStateModel.ps1','tools/lib/mir4/ProcessIR.ps1','tools/lib/mir4/ReleaseDag.ps1','LICENSE')
    'mir4-reference-extension-v0.zip' = @('sdk/preview/mir4/reference-extension/extension.json','sdk/preview/mir4/reference-extension/README.md','spec/schemas/preview/mir4-mep-v0.schema.json','LICENSE')
    'mir4-reference-extension-v1-preview.zip' = @('sdk/preview/mir4/reference-extension-v1/extension.json','sdk/preview/mir4/reference-extension-v1/README.md','sdk/preview/mir4/canonical-json-v1/powershell/MIR4.CanonicalJson.V1.psm1','sdk/preview/mir4/canonical-json-v1/python/mir4_canonical_json_v1.py','spec/canonicalization/mir-canonical-json-v1.json','spec/schemas/preview/mir4-canonical-json-v1.schema.json','spec/schemas/preview/mir4-mep-v1.schema.json','LICENSE')
    'mir4-inspector-preview-v0.zip' = @('sdk/preview/mir4/inspector/index.html','sdk/preview/mir4/inspector/Export-MIR4SupportSnapshot.ps1','sdk/preview/mir4/inspector/README.md','sdk/preview/mir4/reference/query-snapshot-f210.json','sdk/preview/mir4/reference/support-snapshot-f210.json','LICENSE')
  }
  $sets['mir4-api-sdk-v1-preview.zip'] += @(
    'sdk/preview/mir4/conformance-v1/Invoke-MIR4SdkV1Conformance.ps1',
    'sdk/preview/mir4/reference-extension-v1/extension.json',
    'sdk/preview/mir4/reference-extension-v1/README.md',
    'sdk/preview/mir4/mep-v1/json-schema/mir4-mep-v1.schema.json',
    'spec/schemas/preview/mir4-mep-v1.schema.json',
    'spec/schemas/preview/mir4-sdk-v1-conformance-corpus.schema.json'
  )
  $sets['mir4-platform-preview-v0.zip'] += @(
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json',
    '.mir/technology-lifecycle.json','.mir/technology-governance.json',
    'spec/schemas/mir4-whole-platform-programme-v1.schema.json','spec/schemas/mir4-technology-acceptance-queue-v1.schema.json',
    'docs/releases/mir4-4.0-whole-platform-programme.md','docs/reference/generated/mir4-whole-platform-matrix.md',
    'tools/mir/domain/targets/TargetKey.ps1','tools/lib/mir4/TargetKey.ps1',
    'tools/mir/application/platform/WholePlatform.ps1','tools/lib/mir4/WholePlatform.ps1',
    'tools/mir/application/technology/TechnologyAcceptance.ps1','tools/lib/mir4/TechnologyAcceptance.ps1',
    'tools/commands/mir4/Invoke-MIR4WholePlatform.ps1','tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1'
  )
  $sets['mir4-platform-preview-v0.zip'] += @(
    '.mir/releases/waves/mir4-r0/MIR4-Inspector-Compatibility-ProgrammeV1.json',
    'spec/schemas/mir4-inspection-bundle-v1.schema.json','spec/schemas/mir4-compatibility-subject-ledger-v1.schema.json',
    'spec/schemas/mir4-compatibility-factory-plan-v1.schema.json','spec/schemas/mir4-inspector-workbench-result-v1.schema.json',
    'docs/architecture/mir4-inspector-compatibility.md','sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json',
    'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json','sdk/preview/mir4/reference/inspection-bundle-v1.json',
    'sdk/preview/mir4/reference/inspector-workbench-result-v1.json','sdk/preview/mir4/reference/support-bundle-v1.json',
    'fixtures/mir4-inspector-compatibility-v1/positive/bounded-reference-request.json',
    'fixtures/mir4-inspector-compatibility-v1/negative/blanket-support-boolean.json',
    'fixtures/mir4-inspector-compatibility-v1/negative/forbidden-callback.json',
    'fixtures/mir4-inspector-compatibility-v1/negative/unbounded-page.json',
    'fixtures/mir4-inspector-compatibility-v1/permutation/subject-order-a.json',
    'fixtures/mir4-inspector-compatibility-v1/permutation/subject-order-b.json',
    'fixtures/mir4-inspector-compatibility-v1/evidence/ir4-no-exact-closure.json',
    'fixtures/mir4-inspector-compatibility-v1/evidence/aai-historical-exact-nontransferable.json',
    'fixtures/mir4-inspector-compatibility-v1/evidence/synthetic-claim-attempt.json',
    'tools/lib/mir4/SupportAssessment.ps1','tools/lib/mir4/CompatibilityIndex.ps1','tools/lib/mir4/CompatibilityFactory.ps1','tools/lib/mir4/Inspector.ps1'
  )
  $sets['mir4-inspector-v1-preview.zip'] = @(
    'sdk/preview/mir4/inspector-v1/index.html','sdk/preview/mir4/inspector-v1/Export-MIR4InspectionBundle.ps1','sdk/preview/mir4/inspector-v1/README.md',
    'sdk/preview/mir4/reference/inspection-bundle-v1.json','sdk/preview/mir4/reference/compatibility-subject-ledger-v1.json',
    'sdk/preview/mir4/reference/compatibility-factory-plan-v1.json','sdk/preview/mir4/reference/inspector-workbench-result-v1.json',
    'sdk/preview/mir4/reference/support-bundle-v1.json','spec/schemas/mir4-inspection-bundle-v1.schema.json',
    'spec/schemas/mir4-compatibility-subject-ledger-v1.schema.json','spec/schemas/mir4-compatibility-factory-plan-v1.schema.json',
    'spec/schemas/mir4-inspector-workbench-result-v1.schema.json',
    'sdk/preview/mir4/reference/environment-lock-f210-v1.json','sdk/preview/mir4/reference/environment-lock-f200-v1.json',
    'sdk/preview/mir4/reference/environment-diff-f210-f200-v1.json','sdk/preview/mir4/reference/support-bundle-minimized-v1.json',
    'spec/schemas/preview/mir4-environment-lock-v1.schema.json','spec/schemas/preview/mir4-environment-diff-v1.schema.json',
    'spec/schemas/preview/mir4-support-bundle-v1.schema.json','docs/reference/mir4-environment-evidence.md','LICENSE'
  )
  $sets['mir4-mep-v1-preview.zip'] = @($mepV1 + @(
    'spec/api/mir4-v1/diagnostics.json','spec/api/mir4-v1/compatibility.json',
    'spec/canonicalization/mir-canonical-json-v1.json','fixtures/mir4-canonical-json-v1/vectors.json',
    'spec/schemas/preview/mir4-mep-v1.schema.json','spec/schemas/preview/mir4-extension-lock-v1.schema.json',
    'spec/schemas/preview/mir4-extension-diff-v1.schema.json','spec/schemas/preview/mir4-canonical-json-v1.schema.json',
    'spec/schemas/preview/mir4-f210-mod-data-snapshot-v1.schema.json','spec/schemas/preview/mir4-f210-mep-discovery-result-v1.schema.json',
    'spec/schemas/preview/mir4-canonical-json-vectors-v1.schema.json','docs/architecture/mir4-module-ecosystem.md',
    'docs/reference/mir4-canonical-json-v1.md','docs/reference/mir4-first-extension.md','docs/reference/mir4-f210-mep-discovery.md',
    'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1','tools/lib/mir4/CanonicalJsonV1.ps1',
    'tools/mir/domain/diagnostics/DiagnosticsV1.ps1','tools/lib/mir4/DiagnosticsV1.ps1',
    'tools/mir/application/extensions/ModuleEcosystem.ps1','tools/mir/application/extensions/ExtensionDeveloperExperience.ps1','tools/mir/application/extensions/MepDiscovery.ps1','tools/mir/application/extensions/SdkV1.ps1',
    'tools/mir/cli/Invoke-MIR4Extension.ps1',
    'tools/lib/mir4/ModuleEcosystem.ps1','tools/lib/mir4/ExtensionDeveloperExperience.ps1','tools/lib/mir4/MepDiscovery.ps1','tools/lib/mir4/SdkV1.ps1',
    'tools/commands/mir4/Invoke-MIR4Extension.ps1',
    '.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-F210-MEP-Discovery-ContractV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json',
    '.mir/targets.json','.mir/module-dependencies.json','LICENSE'
  ) + @($mepAuthority.inputs) | Sort-Object -Unique)
  foreach ($legacyAsset in @('mir4-sdk-v0-preview.zip','mir4-platform-preview-v0.zip','mir4-reference-extension-v0.zip','mir4-inspector-preview-v0.zip')) {
    [void]$sets.Remove($legacyAsset)
  }
  $hashes = @()
  foreach ($set in $sets.GetEnumerator()) {
    $path = Join-Path $output $set.Key
    Write-MIR4DeterministicPreviewArchive -RepoRoot $repo -OutputPath $path -RootName ([IO.Path]::GetFileNameWithoutExtension($set.Key)) -RelativePaths @($set.Value)
    $hashes += [ordered]@{name=$set.Key;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-MIR4PlatformFileSha256 $path)}
  }
  $manifest = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PreviewAssetSetV1';source_version='4.0.0'
    programme_id='M4C10-WHOLE-4X-IN-4.0';programme_execution_id='M4C02-09-24H';candidate_state='pre-freeze-unallocated'
    source=[ordered]@{
      repository='Julesc013/more-infinite-research'
      commit=(& git -C $repo rev-parse HEAD).Trim()
      tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
      clean=(@(& git -C $repo status --porcelain --untracked-files=no).Count -eq 0)
    }
    asset_contract=$assetContract
    assets=$hashes;embedded_manifest_required=$true;embedded_spdx_required=$true;embedded_provenance_required=$true
    v0_policy='migration-only-no-public-v0-assets';publication='github-preview-only-not-mod-portal';digest=''
  }
  Add-MIR4PlatformDigest $manifest | Out-Null
  [IO.File]::WriteAllText((Join-Path $output 'preview-assets.json'),(ConvertTo-MIR4PlatformCanonicalJson $manifest)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  $actualOutput = @(Get-ChildItem -LiteralPath $output -File | ForEach-Object Name | Sort-Object)
  $expectedOutput = @($assetContract + 'preview-assets.json' | Sort-Object)
  if (($actualOutput -join '|') -cne ($expectedOutput -join '|')) { throw '[mir4-preview-output-exact-set]' }
  return $manifest
}
