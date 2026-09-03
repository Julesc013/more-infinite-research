# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4AssuranceEvidenceDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202AssuranceEvidenceDecompositionAuthority.ps1') -RepoRoot $repo -Check
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Assurance-Evidence-DecompositionV1.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4AssuranceEvidenceDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-assurance-evidence-decomposition-v1.schema.json')) 'mir4-m42-02-assurance-evidence-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4AssuranceEvidenceDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-assurance-evidence-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-assurance-evidence-predecessor'
Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS4-PRE-FREEZE-RELEASE') 'mir4-m42-02-assurance-evidence-scope'

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
Assert-MIR4AssuranceEvidenceDecompositionV1 (@($facadeErrors).Count-eq0-and@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq0-and[int]$receipt.decomposition.facade.current_lines-le20) 'mir4-m42-02-assurance-evidence-facade'
Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $facadePath)-ceq[string]$receipt.decomposition.facade.current_sha256) 'mir4-m42-02-assurance-evidence-facade-hash'

$functionNames=[Collections.Generic.List[string]]::new()
Assert-MIR4AssuranceEvidenceDecompositionV1 (@($receipt.decomposition.modules).Count-eq9-and@($receipt.decomposition.modules|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-assurance-evidence-module-count'
foreach($module in @($receipt.decomposition.modules)){
  $path=Join-Path $repo ([string]$module.path)
  $tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4AssuranceEvidenceDecompositionV1 (@($parseErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$module.sha256-and[int]$module.lines-le600) 'mir4-m42-02-assurance-evidence-module' ([string]$module.path)
  foreach($function in @($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
}
$projectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4AssuranceEvidenceDecompositionV1 ($functionNames.Count-eq62-and$projectionSha-ceq[string]$receipt.public_contract.previous_sha256-and$projectionSha-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-assurance-evidence-public-contract'

$script:repo=$repo
. $facadePath
foreach($requiredFunction in @('Get-MIRAssuranceTestFingerprint','Test-MIRAssuranceTrustedProducer','Import-MIRAssuranceWorkerEvidence','Get-MIRAssuranceEvidenceDecision','Write-MIRAssuranceAttempt','Invoke-MIRAssuranceCommandText','Complete-MIRAssurancePlan','Invoke-MIRAssuranceGate')){
  Assert-MIR4AssuranceEvidenceDecompositionV1 ($null-ne(Get-Command $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) 'mir4-m42-02-assurance-evidence-load' $requiredFunction
}
Assert-MIR4AssuranceEvidenceDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact-and[bool]$receipt.semantic_contract.fingerprints_unchanged-and[bool]$receipt.semantic_contract.producer_trust_unchanged-and[bool]$receipt.semantic_contract.worker_ingestion_unchanged-and[bool]$receipt.semantic_contract.plans_and_gates_unchanged) 'mir4-m42-02-assurance-evidence-semantic-contract'

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4AssuranceEvidenceDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq[string]$receipt.tooling_inventory.digest) 'mir4-m42-02-assurance-evidence-inventory'
foreach($binding in @($receipt.evolved_bindings)){
  Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo ([string]$binding.path)))-ceq[string]$binding.current_sha256-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-assurance-evidence-evolved-binding' ([string]$binding.path)
}
Assert-MIR4AssuranceEvidenceDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0) 'mir4-m42-02-assurance-evidence-package-firewall'
Assert-MIR4AssuranceEvidenceDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-assurance-evidence-release-firewall'
Assert-MIR4AssuranceEvidenceDecompositionV1 ((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-assurance-evidence-package-mutation'

[pscustomobject][ordered]@{
  status='M42-02-PS3-ASSURANCE-EVIDENCE-DECOMPOSITION-PASSED'
  facade_lines=[int]$receipt.decomposition.facade.current_lines
  modules=@($receipt.decomposition.modules).Count
  maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum)
  functions=$functionNames.Count
  public_contract_sha256=$projectionSha
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
