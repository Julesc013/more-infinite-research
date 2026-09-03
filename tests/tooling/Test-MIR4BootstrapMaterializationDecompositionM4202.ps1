# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4BootstrapMaterializationDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202BootstrapMaterializationDecompositionAuthority.ps1') -RepoRoot $repo -Check
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Bootstrap-Materialization-DecompositionV1.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4BootstrapMaterializationDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-bootstrap-materialization-decomposition-v1.schema.json')) 'mir4-m42-02-bootstrap-materialization-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4BootstrapMaterializationDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-bootstrap-materialization-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4BootstrapMaterializationDecompositionV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-bootstrap-materialization-predecessor'
Assert-MIR4BootstrapMaterializationDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS6-ASSURANCE-RELEASE') 'mir4-m42-02-bootstrap-materialization-scope'
Assert-MIR4BootstrapMaterializationDecompositionV1 ([string]$receipt.characterization.sha256-ceq'3B496E1D8DA0A772E4B1856761EBB3C40921742D0161D59811E360256901FB30'-and[string]$receipt.current_source.sha256-ceq'3B496E1D8DA0A772E4B1856761EBB3C40921742D0161D59811E360256901FB30'-and[int]$receipt.current_source.lines-eq1872) 'mir4-m42-02-bootstrap-materialization-source-chain'

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
Assert-MIR4BootstrapMaterializationDecompositionV1 (@($facadeErrors).Count-eq0-and@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq0-and[int]$receipt.decomposition.facade.current_lines-le20) 'mir4-m42-02-bootstrap-materialization-facade'
Assert-MIR4BootstrapMaterializationDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $facadePath)-ceq[string]$receipt.decomposition.facade.current_sha256) 'mir4-m42-02-bootstrap-materialization-facade-hash'

$functionNames=[Collections.Generic.List[string]]::new()
Assert-MIR4BootstrapMaterializationDecompositionV1 (@($receipt.decomposition.modules).Count-eq6-and@($receipt.decomposition.modules|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-bootstrap-materialization-module-count'
foreach($module in @($receipt.decomposition.modules)){
  $path=Join-Path $repo ([string]$module.path);$tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4BootstrapMaterializationDecompositionV1 (@($parseErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$module.sha256-and[int]$module.lines-le600) 'mir4-m42-02-bootstrap-materialization-module' ([string]$module.path)
  foreach($function in @($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
}
$projectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4BootstrapMaterializationDecompositionV1 ($functionNames.Count-eq51-and$projectionSha-ceq[string]$receipt.public_contract.previous_sha256-and$projectionSha-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-bootstrap-materialization-public-contract'

. $facadePath
foreach($requiredFunction in @('Get-MIR4Sha256Bytes','Write-MIR4BootstrapRecord','Assert-MIR4DescendantPath','Write-MIR4DeterministicArchive','Get-MIR4ArchiveInventory','Compare-MIR4BootstrapCandidate','Assert-MIR4GitSourceProof','New-MIR4GitSourceProof','Assert-MIR4BootstrapCapsuleManifestClosure','Assert-MIR4BootstrapCapsuleArtifact','New-MIR4BootstrapSourceCapsule')){
  Assert-MIR4BootstrapMaterializationDecompositionV1 ($null-ne(Get-Command $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) 'mir4-m42-02-bootstrap-materialization-load' $requiredFunction
}
Assert-MIR4BootstrapMaterializationDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact-and[bool]$receipt.semantic_contract.digests_and_records_unchanged-and[bool]$receipt.semantic_contract.safe_paths_and_cleanup_unchanged-and[bool]$receipt.semantic_contract.archive_construction_and_comparison_unchanged-and[bool]$receipt.semantic_contract.git_source_proof_unchanged-and[bool]$receipt.semantic_contract.capsule_contract_unchanged-and[bool]$receipt.semantic_contract.capsule_artifacts_unchanged-and[bool]$receipt.semantic_contract.pre_freeze_authority_chain_extended_for_ps5) 'mir4-m42-02-bootstrap-materialization-semantic-contract'
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4BootstrapMaterializationDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq[string]$receipt.tooling_inventory.digest) 'mir4-m42-02-bootstrap-materialization-inventory'
foreach($binding in @($receipt.evolved_bindings)){
  Assert-MIR4BootstrapMaterializationDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo ([string]$binding.path)))-ceq[string]$binding.current_sha256-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-bootstrap-materialization-evolved-binding' ([string]$binding.path)
}
Assert-MIR4BootstrapMaterializationDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0-and(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-bootstrap-materialization-package-firewall'
Assert-MIR4BootstrapMaterializationDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-bootstrap-materialization-release-firewall'

[pscustomobject][ordered]@{status='M42-02-PS5-BOOTSTRAP-MATERIALIZATION-DECOMPOSITION-PASSED';facade_lines=[int]$receipt.decomposition.facade.current_lines;modules=@($receipt.decomposition.modules).Count;maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum);functions=$functionNames.Count;public_contract_sha256=$projectionSha;package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
