# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4PreFreezeReleaseDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202PreFreezeReleaseDecompositionAuthority.ps1') -RepoRoot $repo -Check
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Pre-Freeze-Release-DecompositionV1.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4PreFreezeReleaseDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-pre-freeze-release-decomposition-v1.schema.json')) 'mir4-m42-02-pre-freeze-release-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4PreFreezeReleaseDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-pre-freeze-release-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-ceq[string]$receipt.predecessor.receipt_sha256-and[string]$predecessor.record_sha256-ceq[string]$receipt.predecessor.record_sha256) 'mir4-m42-02-pre-freeze-release-predecessor'
Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS5-BOOTSTRAP-MATERIALIZATION') 'mir4-m42-02-pre-freeze-release-scope'
Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$receipt.characterization.sha256-ceq'1D21940B53412C4878B2E984C4C54F5BE81FDEC2FCD8E734D388FE8B966F2181'-and[string]$receipt.current_source.sha256-ceq'EF715051266F0984B7A57C1F61497E0FB614E2AB28F80EFE5A56D2350CB9C89E'-and[int]$receipt.current_source.lines-eq2283) 'mir4-m42-02-pre-freeze-release-source-chain'

$facadePath=Join-Path $repo ([string]$receipt.decomposition.facade.path)
$facadeTokens=$null;$facadeErrors=$null
$facadeAst=[Management.Automation.Language.Parser]::ParseFile($facadePath,[ref]$facadeTokens,[ref]$facadeErrors)
Assert-MIR4PreFreezeReleaseDecompositionV1 (@($facadeErrors).Count-eq0-and@($facadeAst.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count-eq0-and[int]$receipt.decomposition.facade.current_lines-le20) 'mir4-m42-02-pre-freeze-release-facade'
Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $facadePath)-ceq[string]$receipt.decomposition.facade.current_sha256) 'mir4-m42-02-pre-freeze-release-facade-hash'

$functionNames=[Collections.Generic.List[string]]::new()
Assert-MIR4PreFreezeReleaseDecompositionV1 (@($receipt.decomposition.modules).Count-eq6-and@($receipt.decomposition.modules|Group-Object path|Where-Object{$_.Count-ne1}).Count-eq0) 'mir4-m42-02-pre-freeze-release-module-count'
foreach($module in @($receipt.decomposition.modules)){
  $path=Join-Path $repo ([string]$module.path);$tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4PreFreezeReleaseDecompositionV1 (@($parseErrors).Count-eq0-and(Get-MIR4BootstrapTextSha256 -Path $path)-ceq[string]$module.sha256-and[int]$module.lines-le1000) 'mir4-m42-02-pre-freeze-release-module' ([string]$module.path)
  foreach($function in @($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true))){[void]$functionNames.Add($function.Name)}
}
$projectionSha=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $functionNames.ToArray())
Assert-MIR4PreFreezeReleaseDecompositionV1 ($functionNames.Count-eq25-and$projectionSha-ceq[string]$receipt.public_contract.previous_sha256-and$projectionSha-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-pre-freeze-release-public-contract'

. $facadePath
foreach($requiredFunction in @('Get-MIR4PreFreezeAuthorityState','Test-MIR4PreFreezeAuthorities','Get-MIR4ReleaseDoctor','Test-MIR4ReleaseWorkflowInvocation','New-MIR4PlaytestSession','Complete-MIR4PlaytestSession')){
  Assert-MIR4PreFreezeReleaseDecompositionV1 ($null-ne(Get-Command $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) 'mir4-m42-02-pre-freeze-release-load' $requiredFunction
}
Assert-MIR4PreFreezeReleaseDecompositionV1 ([bool]$receipt.semantic_contract.source_segments_exact_except_declared_self_successor-and[bool]$receipt.semantic_contract.declared_self_successor_extension-and[bool]$receipt.semantic_contract.authority_locks_unchanged-and[bool]$receipt.semantic_contract.release_doctor_unchanged-and[bool]$receipt.semantic_contract.playtest_sessions_unchanged) 'mir4-m42-02-pre-freeze-release-semantic-contract'
$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
Assert-MIR4PreFreezeReleaseDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0-and[string]$inventory.digest-ceq[string]$receipt.tooling_inventory.digest) 'mir4-m42-02-pre-freeze-release-inventory'
foreach($binding in @($receipt.evolved_bindings)){
  Assert-MIR4PreFreezeReleaseDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo ([string]$binding.path)))-ceq[string]$binding.current_sha256-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-pre-freeze-release-evolved-binding' ([string]$binding.path)
}
Assert-MIR4PreFreezeReleaseDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0-and(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-pre-freeze-release-package-firewall'
Assert-MIR4PreFreezeReleaseDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-pre-freeze-release-release-firewall'

[pscustomobject][ordered]@{status='M42-02-PS4-PRE-FREEZE-RELEASE-DECOMPOSITION-PASSED';facade_lines=[int]$receipt.decomposition.facade.current_lines;modules=@($receipt.decomposition.modules).Count;maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum);functions=$functionNames.Count;public_contract_sha256=$projectionSha;package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
