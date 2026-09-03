# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-MIR4CommandRouterDecompositionV1([bool]$Condition,[string]$Code,[string]$Detail=''){
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json'
$validationSuccessorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Validation-Runner-DecompositionV1.json'
if(-not(Test-Path -LiteralPath $validationSuccessorPath -PathType Leaf)){
  [void](& (Join-Path $repo 'tools/commands/mir4/Update-MIR4M4202PowerShellCommandRouterDecompositionAuthority.ps1') -RepoRoot $repo -Check)
}
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4CommandRouterDecompositionV1 ($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-powershell-command-router-decomposition-v1.schema.json')) 'mir4-m42-02-command-router-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4CommandRouterDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m42-02-command-router-record'

$predecessorPath=Join-Path $repo ([string]$receipt.predecessor.receipt)
$predecessor=Get-Content -Raw -LiteralPath $predecessorPath|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4CommandRouterDecompositionV1 (((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash) -ceq [string]$receipt.predecessor.receipt_sha256 -and [string]$predecessor.record_sha256 -ceq [string]$receipt.predecessor.record_sha256) 'mir4-m42-02-command-router-predecessor'
Assert-MIR4CommandRouterDecompositionV1 ([string]$receipt.status-ceq'M42-02-PS1-COMMAND-ROUTER-DECOMPOSED'-and[string]$receipt.next_fixed_point-ceq'M42-02-PS2-VALIDATION-RUNNER') 'mir4-m42-02-command-router-scope'

$modulePaths=@($receipt.decomposition.modules|ForEach-Object{[string]$_.path})
Assert-MIR4CommandRouterDecompositionV1 ($modulePaths.Count-eq12-and@($modulePaths|Sort-Object -Unique).Count-eq12) 'mir4-m42-02-command-router-module-count'
foreach($file in @($receipt.decomposition.modules)+@($receipt.decomposition.facade)){
  $path=Join-Path $repo ([string]$file.path)
  $tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
  Assert-MIR4CommandRouterDecompositionV1 (@($parseErrors).Count-eq0) 'mir4-m42-02-command-router-parse' ([string]$file.path)
  $expectedHash=if([string]$file.path-ceq[string]$receipt.decomposition.facade.path){[string]$receipt.decomposition.facade.current_sha256}else{[string]$file.sha256}
  Assert-MIR4CommandRouterDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path $path)-ceq$expectedHash) 'mir4-m42-02-command-router-file-hash' ([string]$file.path)
}
Assert-MIR4CommandRouterDecompositionV1 ([int]$receipt.decomposition.current_lines-le200-and[int]$receipt.decomposition.facade_function_count-eq1) 'mir4-m42-02-command-router-facade-bound'
Assert-MIR4CommandRouterDecompositionV1 (@($receipt.decomposition.modules|Where-Object{[int]$_.lines-gt400-or[int]$_.parse_errors-ne0}).Count-eq0) 'mir4-m42-02-command-router-module-bound'

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
$projection=[pscustomobject][ordered]@{command_count=[int]$inventory.command_count;commands=@($inventory.commands)}
$projectionHash=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $projection)
Assert-MIR4CommandRouterDecompositionV1 ($projectionHash-ceq[string]$receipt.public_contract.previous_sha256-and$projectionHash-ceq[string]$receipt.public_contract.current_sha256-and[bool]$receipt.public_contract.unchanged) 'mir4-m42-02-command-router-public-contract'
Assert-MIR4CommandRouterDecompositionV1 ([int]$inventory.command_count-eq85-and[int]$inventory.summary.unknown-eq0-and[int]$inventory.summary.duplicate_command_keys-eq0) 'mir4-m42-02-command-router-inventory'
foreach($implementation in @($inventory.implementation_files)){
  $implementationPath=Join-Path $repo ([string]$implementation.path)
  Assert-MIR4CommandRouterDecompositionV1 ([string]$implementation.hash_mode-ceq'canonical-text-v1'-and(Get-MIR4CommandInventoryTextSha256V1 -Path $implementationPath)-ceq[string]$implementation.sha256) 'mir4-m42-02-command-router-inventory-file' ([string]$implementation.path)
}

$inventoryProbe=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 tooling inventory-check 2>&1|Out-String).Trim()
Assert-MIR4CommandRouterDecompositionV1 ($LASTEXITCODE-eq0-and$inventoryProbe-match'command_count') 'mir4-m42-02-command-router-inventory-probe' $inventoryProbe
$pathProbe=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') path resolve package.root 2>&1|Out-String).Trim()
Assert-MIR4CommandRouterDecompositionV1 ($LASTEXITCODE-eq0-and$pathProbe-match'src[\\/]mod') 'mir4-m42-02-command-router-path-probe' $pathProbe
$unknownProbe=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') nonsense 2>&1|Out-String).Trim()
Assert-MIR4CommandRouterDecompositionV1 ($LASTEXITCODE-ne0-and$unknownProbe-match'Unknown command area: nonsense') 'mir4-m42-02-command-router-negative-probe' $unknownProbe
$global:LASTEXITCODE=0

$expectedBindingSha=@{}
foreach($binding in @($receipt.evolved_bindings)){$expectedBindingSha[[string]$binding.path]=[string]$binding.current_sha256}
if(Test-Path -LiteralPath $validationSuccessorPath -PathType Leaf){
  $validationSuccessorRaw=Get-Content -Raw -LiteralPath $validationSuccessorPath
  Assert-MIR4CommandRouterDecompositionV1 ($validationSuccessorRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-validation-runner-decomposition-v1.schema.json')) 'mir4-m42-02-command-router-successor-schema'
  $validationSuccessor=$validationSuccessorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4CommandRouterDecompositionV1 (Test-MIR4BootstrapRecordHash -Record $validationSuccessor) 'mir4-m42-02-command-router-successor-record'
  Assert-MIR4CommandRouterDecompositionV1 ((Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-ceq[string]$validationSuccessor.predecessor.receipt_sha256-and[string]$receipt.record_sha256-ceq[string]$validationSuccessor.predecessor.record_sha256) 'mir4-m42-02-command-router-successor-predecessor'
  foreach($binding in @($validationSuccessor.evolved_bindings)){
    $path=[string]$binding.path
    if($expectedBindingSha.ContainsKey($path)){
      Assert-MIR4CommandRouterDecompositionV1 ([string]$binding.previous_sha256-ceq[string]$expectedBindingSha[$path]) 'mir4-m42-02-command-router-successor-binding' $path
      $expectedBindingSha[$path]=[string]$binding.current_sha256
    }
  }
}
foreach($binding in @($receipt.evolved_bindings)){
  $path=[string]$binding.path
  Assert-MIR4CommandRouterDecompositionV1 ((Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $path))-ceq[string]$expectedBindingSha[$path]-and[string]$binding.hash_mode-ceq'canonical-text-v1'-and-not[bool]$binding.package_visible-and-not[bool]$binding.release_authority) 'mir4-m42-02-command-router-evolved-binding' $path
}
Assert-MIR4CommandRouterDecompositionV1 ([string]$receipt.preservation.package_source_sha256-ceq$packageBefore-and@($receipt.preservation.package_visible_delta).Count-eq0) 'mir4-m42-02-command-router-package-firewall'
Assert-MIR4CommandRouterDecompositionV1 (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'mir4-m42-02-command-router-release-firewall'
Assert-MIR4CommandRouterDecompositionV1 ((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-m42-02-command-router-package-mutation'

[pscustomobject][ordered]@{
  status='M42-02-PS1-COMMAND-ROUTER-DECOMPOSITION-PASSED'
  public_commands=[int]$inventory.command_count
  facade_lines=[int]$receipt.decomposition.current_lines
  modules=@($receipt.decomposition.modules).Count
  maximum_module_lines=(@($receipt.decomposition.modules|Measure-Object lines -Maximum).Maximum)
  public_contract_sha256=$projectionHash
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
