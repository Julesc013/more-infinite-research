param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/targets/TargetCompiler.ps1')

function Assert-MIR4TargetCompilerV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$authority=Get-MIR4TargetCompilerAuthority -RepoRoot $repo
$contracts=New-MIR4TargetContractSet -RepoRoot $repo
$laws=Test-MIR4TargetProviderLaws -RepoRoot $repo

Assert-MIR4TargetCompilerV1 ([string]$authority.kind-ceq'MIR4TargetCompilerProgrammeV1') 'mir4-target-compiler-authority'
Assert-MIR4TargetCompilerV1 (@($contracts.targets).Count-eq17) 'mir4-target-compiler-target-count'
Assert-MIR4TargetCompilerV1 ([bool]$laws.passed-and@($laws.targets).Count-eq17) 'mir4-target-compiler-laws'
Assert-MIR4TargetCompilerV1 (@($contracts.targets|Where-Object{$_.target-in@('f210','f200')-and$_.maturity-ne'stable'}).Count-eq0) 'mir4-target-compiler-stable-targets'
Assert-MIR4TargetCompilerV1 (@($contracts.targets|Where-Object{$_.target-in@('f012','f011','f010','f009','f008','f007','f006')-and$_.inputs.status-ne'BLOCKED_WITH_EVIDENCE'}).Count-eq0) 'mir4-target-compiler-museum-boundary'
Assert-MIR4TargetCompilerV1 (@($contracts.targets|Where-Object{$_.authoritative_output-or$_.mutation_capability-or$_.public_support_claim}).Count-eq0) 'mir4-target-compiler-authority-firewall'

$f210=@($contracts.targets|Where-Object target -eq f210)[0]
$fixture=[pscustomobject][ordered]@{owned=[pscustomobject][ordered]@{};unowned=[pscustomobject][ordered]@{sentinel='preserved'}}
$projected=Invoke-MIR4TargetProviderProjection -Provider $f210 -InputRecord $fixture -OwnedChanges ([pscustomobject][ordered]@{distribution_version='4.0.21000'})
Assert-MIR4TargetCompilerV1 ([string]$projected.owned.distribution_version-ceq'4.0.21000'-and[string]$projected.unowned.sentinel-ceq'preserved') 'mir4-target-compiler-projection'
try{Invoke-MIR4TargetProviderProjection -Provider $f210 -InputRecord $fixture -OwnedChanges ([pscustomobject]@{technology_policy='forbidden'})|Out-Null;throw '[mir4-target-compiler-unowned-write-accepted]'}
catch{if(-not$_.Exception.Message.StartsWith('[mir4-target-provider-unowned-write]')){throw}}

$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($path in @('tools/mir/application/targets/TargetCompiler.ps1','tools/lib/mir4/TargetCompiler.ps1','tests/targets/Test-MIR4TargetCompiler.ps1')){
  Assert-MIR4TargetCompilerV1 ($path-notin$packageFiles) 'mir4-target-compiler-package-visible' $path
}
Assert-MIR4TargetCompilerV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-target-compiler-package-source-mutation'

[pscustomobject][ordered]@{status='passed';canonical_application='tools/mir/application/targets/TargetCompiler.ps1';target_count=17;laws=@($authority.provider_abi.laws);package_source_sha256=$packageBefore;release_transition_authority=$false}
