[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')

function Get-MIR4M4202CommandRouterRawSha256([string]$RelativePath){
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-command-router-source] $RelativePath"}
  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function ConvertTo-MIR4M4202CommandRouterJson($Record){
  (($Record|ConvertTo-Json -Depth 100).Replace(([string][char]13+[char]10),[string][char]10)+[string][char]10)
}

function Set-MIR4M4202CommandRouterProjection([string]$RelativePath,[string]$Json){
  $path=Join-Path $repo $RelativePath
  if($Check){
    $actual=if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::ReadAllText($path).Replace(([string][char]13+[char]10),[string][char]10)}else{''}
    if($actual-cne$Json){throw "[mir4-m42-02-command-router-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

function Get-MIR4M4202CommandRouterAst([string]$RelativePath){
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $RelativePath),[ref]$tokens,[ref]$errors)
  if(@($errors).Count-ne0){throw "[mir4-m42-02-command-router-parse] $RelativePath"}
  [pscustomobject]@{ast=$ast;errors=@($errors)}
}

$predecessorPath='releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
$predecessor=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorPath)|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.status-cne'M42-02-RESIDUAL-POWERSHELL-CHARACTERIZED'-or[string]$predecessor.next_fixed_point-cne'M42-02-PS1-COMMAND-ROUTER'){throw '[mir4-m42-02-command-router-predecessor]'}
$predecessorRouter=@($predecessor.tracked_files|Where-Object{[string]$_.path-ceq'tools/mir/cli/Invoke-MIRCommandRouter.ps1'})
if($predecessorRouter.Count-ne1-or[string]$predecessorRouter[0].sha256-cne'AA50E7DF8CD41C756B3270A47A23E13F4F8B911F9ED89B05813D4B99376E7E25'){throw '[mir4-m42-02-command-router-predecessor-router]'}

$inventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
if([int]$inventory.command_count-ne85-or[int]$inventory.summary.unknown-ne0-or[int]$inventory.summary.duplicate_command_keys-ne0){throw '[mir4-m42-02-command-router-inventory]'}
$publicProjection=[pscustomobject][ordered]@{command_count=[int]$inventory.command_count;commands=@($inventory.commands)}
$publicProjectionSha256=Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $publicProjection)
if($publicProjectionSha256-cne'0D3D39A0FDC988F18B218766797991BBF6BEEA86DCD38AF53387C30BFC0A0389'){throw '[mir4-m42-02-command-router-public-contract]'}

$moduleSpecs=[ordered]@{
  'ArgumentParsing.ps1'='argument parsing'
  'RunProfiles.ps1'='profile composition and execution'
  'DocsOnlyRelease.ps1'='documentation-only release checks'
  'MIR4BootstrapCommands.ps1'='bootstrap, historical, and local-build commands'
  'MIR4ApplicationCommands.ps1'='current MIR4 application commands'
  'MIR4MigrationCommands.ps1'='migration and compatibility-reader commands'
  'MIR4PlatformCommands.ps1'='platform and compatibility commands'
  'MIR4CommandDispatcher.ps1'='MIR4 command lookup'
  'CoreCommands.ps1'='core CLI command areas'
  'ProductCommands.ps1'='technology, release, playtest, and audit areas'
  'RepositoryCommands.ps1'='package, backport, storage, report, and profile areas'
  'CommandDispatcher.ps1'='top-level area lookup and invocation'
}
$modules=@(foreach($entry in $moduleSpecs.GetEnumerator()){
  $relative='tools/mir/cli/router/'+[string]$entry.Key
  $parsed=Get-MIR4M4202CommandRouterAst $relative
  $lines=@(Get-Content -LiteralPath (Join-Path $repo $relative)).Count
  if($lines-gt400){throw "[mir4-m42-02-command-router-module-size] $relative|$lines"}
  [pscustomobject][ordered]@{
    path=$relative;role=[string]$entry.Value;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $relative));hash_mode='canonical-text-v1';lines=$lines
    function_count=@($parsed.ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count;parse_errors=0
  }
})
if($modules.Count-ne12){throw '[mir4-m42-02-command-router-module-count]'}

$routerPath='tools/mir/cli/Invoke-MIRCommandRouter.ps1'
$routerParsed=Get-MIR4M4202CommandRouterAst $routerPath
$routerLines=@(Get-Content -LiteralPath (Join-Path $repo $routerPath)).Count
$routerFunctions=@($routerParsed.ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$true)).Count
if($routerLines-gt200-or$routerFunctions-ne1){throw "[mir4-m42-02-command-router-facade] $routerLines|$routerFunctions"}

$previousHashes=[ordered]@{
  '.mir/assurance.json'='F4F215B6767CC432B941328F05005146AC70775909051B5C20E466ECEFA5A9A0'
  '.mir/control/paths.yml'='FEE112A1C40E61DE7D4657D612EE14F23BBE696EB4F22462D7FADB423BA9EF32'
  '.mir/test-impact.yml'='2D6B4B9C5CBCAA0A7F819AD2207241D6AA203AB81A7568FFD4E3A10A64C155EB'
  'assurance/catalog/tests.json'='3BA3A2AA1A77D96B0C168FE3656B913252A382272CBAFDFF7F3AB17A8D41899D'
  'docs/architecture/module-boundaries.md'='24D5CB06F955FC6189D5CA02B4B0769547F16069D20692B4D7F909AB07824F6F'
  'governance/automation/mir4-command-inventory-v1.json'='632430B0872685347F07008F5ECA429954D16596D6A0B305D1D0FB4E476D640F'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='7AEBCF60258BD9FC48514C2FB15415552EFBA89D84F865F8E59DEC81C86F57A9'
  'tests/tooling/Test-MIR4CliReleaseConvergence.ps1'='FECB62355A5E37EA3CA33F9D52F3B36F99BD01011FA7E7C0E341156479BB101A'
  'validation/tests.yml'='78182123F3417E7BE6284165439F7FE55209D7AEAED827B0FCAB12FC35D88846'
  'tools/lib/mir4/PreFreezeRelease.ps1'='1D21940B53412C4878B2E984C4C54F5BE81FDEC2FCD8E734D388FE8B966F2181'
  'tools/mir/application/repository/RepositoryFixedPoint.ps1'='E33A3D0761FE92D03CC32000A033FF5C3C70FE7802982E796FBB2933B84F42C9'
  'tools/mir/cli/Invoke-MIRCommandRouter.ps1'='AA50E7DF8CD41C756B3270A47A23E13F4F8B911F9ED89B05813D4B99376E7E25'
}
$evolvedBindings=@($previousHashes.GetEnumerator()|ForEach-Object{
  [pscustomobject][ordered]@{path=[string]$_.Key;previous_sha256=[string]$_.Value;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo ([string]$_.Key)));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
})

$packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202PowerShellCommandRouterDecompositionV1';status='M42-02-PS1-COMMAND-ROUTER-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='6f1f559fd110e51751cf4dcac197da7af8da5be8';tree='641d12be7658dfc11470f241f422e60547c3fdc7'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-POWERSHELL-CHARACTERIZATION';receipt=$predecessorPath;receipt_sha256=(Get-MIR4M4202CommandRouterRawSha256 $predecessorPath);record_sha256=[string]$predecessor.record_sha256;status=[string]$predecessor.status;router_sha256=[string]$predecessorRouter[0].sha256}
  decomposition=[pscustomobject][ordered]@{responsibility='command-router';facade=[pscustomobject][ordered]@{path=$routerPath;previous_sha256=[string]$predecessorRouter[0].sha256;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $routerPath));hash_mode='canonical-text-v1'};previous_lines=1321;current_lines=$routerLines;facade_maximum_lines=200;facade_function_count=$routerFunctions;module_root='tools/mir/cli/router';module_count=$modules.Count;module_maximum_lines=400;modules=$modules}
  public_contract=[pscustomobject][ordered]@{projection_algorithm='canonical-json-v1(command_count,commands)';previous_sha256=$publicProjectionSha256;current_sha256=$publicProjectionSha256;unchanged=$true;command_count=[int]$inventory.command_count;canonical_internal=[int]$inventory.summary.canonical_internal;unknown=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys;inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo 'governance/automation/mir4-command-inventory-v1.json'));hash_mode='canonical-text-v1';digest=[string]$inventory.digest}}
  evolved_bindings=$evolvedBindings
  preservation=[pscustomobject][ordered]@{package_source_sha256=$packageSourceSha256;package_visible_delta=@();gameplay=$false;saves=$true;settings=$true;migrations=$true;compatibility_claims=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-PS2-VALIDATION-RUNNER';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$json=ConvertTo-MIR4M4202CommandRouterJson $receipt
if(-not($json|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-powershell-command-router-decomposition-v1.schema.json'))){throw '[mir4-m42-02-command-router-receipt-schema]'}
Set-MIR4M4202CommandRouterProjection -RelativePath 'releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json' -Json $json
$receipt
