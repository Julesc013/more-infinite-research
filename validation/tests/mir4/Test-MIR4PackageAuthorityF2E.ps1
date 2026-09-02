param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/PackageAuthorityVerifier.ps1')
$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
if(-not($raw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m41-f2e-package-authority-cutover-v1.schema.json'))){throw '[mir4-f2e-receipt-schema]'}
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
$verification=New-MIR4M41F2EPackageAuthorityVerification -RepoRoot $repo
if([string]$receipt.canonical_authority.record_sha256-cne[string]$verification.package_authority_sha256-or
   [string]$receipt.verification.package_source_sha256-cne[string]$verification.package_source_sha256-or
   [string]$receipt.predecessor_receipt.sha256-cne[string]$verification.predecessor_sha256-or
   [string]$receipt.status-cne'M41-F2E-PACKAGE-SOURCE-CUTOVER-COMPLETE'-or
   -not[bool]$receipt.transition_gate.package_cutover-or-not[bool]$receipt.transition_gate.old_writer_retirement-or
   @($receipt.transition_gate.PSObject.Properties|Where-Object{$_.Name-notin@('package_cutover','old_writer_retirement')-and[bool]$_.Value}).Count-ne0){throw '[mir4-f2e-receipt]'}
if((@($receipt.verification.targets.target)-join'|')-cne'f210|f200|f110|f100'-or
   (@($verification.targets.target)-join'|')-cne'f210|f200|f110|f100'){throw '[mir4-f2e-target-order]'}
$superseded=@($receipt.superseded_pre_cutover_bindings)
$supersededPaths=@($superseded|ForEach-Object{[string]$_.path})
$packageOutputs=@(Get-MIRPackageOutputPaths -RepoRoot $repo)
if($superseded.Count-ne37-or
   @($supersededPaths|Sort-Object -Unique).Count-ne$superseded.Count-or
   @($superseded|Where-Object{[string]$_.historical_sha256-notmatch'^[A-F0-9]{64}$'-or[string]$_.hash_mode-cne'canonical-text-v1'}).Count-ne0-or
   @($supersededPaths|Where-Object{$_-in$packageOutputs}).Count-ne0-or
   @('contracts/release/mir4-release-narrative-result-v1.schema.json','scripts/Invoke-MIRReleaseTargetedGate.ps1','tools/lib/mir4/PreFreezeRelease.ps1','tools/mir/application/package/TargetMaterializer.ps1','tools/mir/application/release/ReleaseNarratives.ps1'|Where-Object{$_-notin$supersededPaths}).Count-ne0){
  throw '[mir4-f2e-superseded-pre-cutover-bindings]'
}
$compositionSchema=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/schemas/mir4-package-composition-result-v1.schema.json')
if(-not$compositionSchema.Contains('passed-canonical-package-authority-materialization')-or-not$compositionSchema.Contains('"package_cutover": {"const": true}')){throw '[mir4-f2e-composition-contract]'}
Write-Host '[ok] M41-F2E has one canonical writer and reader authority, exact four-target reconstruction, retained rollback, and no release transition.'
