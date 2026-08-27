param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/extensions/ModuleEcosystem.ps1')
. (Join-Path $repo 'tools/mir/application/extensions/ExperimentalApiSdk.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4ModuleEcosystemV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$authority=Get-MIR4ModuleEcosystemAuthority -RepoRoot $repo
Assert-MIR4ModuleEcosystemV1 (@($authority.fragment_kinds).Count-eq12-and@($authority.api_surfaces).Count-eq9-and@($authority.transports).Count-eq17-and@($authority.builder_commands).Count-eq11) 'mir4-module-ecosystem-authority-shape'
foreach($flag in @('semantic_authority','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','safety_kernel_override_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')){
  Assert-MIR4ModuleEcosystemV1 (-not[bool]$authority.$flag) 'mir4-module-ecosystem-authority-firewall' $flag
}

$reference=New-MIR4ReferenceExtensionV1 -RepoRoot $repo
Assert-MIR4ModuleEcosystemV1 (Test-MIR4MepV1Envelope -Envelope $reference -RepoRoot $repo) 'mir4-module-ecosystem-reference-envelope'
$transport=New-MIR4TargetTransportPlanV1 -RepoRoot $repo
$responses=@(foreach($surface in @($authority.api_surfaces)){New-MIR4ApiV1Response -RepoRoot $repo -Surface ([string]$surface) -Target f210 -Items @()})
$files=Get-MIR4ModuleEcosystemSdkFiles -RepoRoot $repo
Invoke-MIR4SdkGenerate -RepoRoot $repo -Check

Assert-MIR4ModuleEcosystemV1 (@($reference.fragments).Count-eq12-and@($reference.fragments.kind|Sort-Object -Unique).Count-eq12) 'mir4-module-ecosystem-fragment-coverage'
Assert-MIR4ModuleEcosystemV1 (@($transport.targets).Count-eq17-and[string]@($transport.targets|Where-Object target -eq f210)[0].admission-ceq'blocked-by-terminal-emitter') 'mir4-module-ecosystem-transport-truth'
Assert-MIR4ModuleEcosystemV1 (@($responses.surface|Sort-Object -Unique).Count-eq9-and@($responses|Where-Object{$_.package_visible-or$_.mutation_authorized-or$_.public_support_claim}).Count-eq0) 'mir4-module-ecosystem-api-boundary'
Assert-MIR4ModuleEcosystemV1 ($files.Count-eq56) 'mir4-module-ecosystem-generated-file-count' ([string]$files.Count)
Assert-MIR4ModuleEcosystemV1 ([string]$authority.independent_consumer.status-ceq'BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER') 'mir4-module-ecosystem-consumer-blocker'

$record=[ordered]@{
  fragment_kind_count=@($authority.fragment_kinds).Count
  api_surface_count=@($authority.api_surfaces).Count
  transport_count=@($authority.transports).Count
  builder_command_count=@($authority.builder_commands).Count
  reference_digest=[string]$reference.digest
  transport_digest=[string]$transport.digest
  api_response_digests=@($responses|ForEach-Object{[string]$_.digest})
  generated_file_count=$files.Count
  production_consumer_status=[string]$authority.independent_consumer.status
  package_visible=$false
  public_support=$false
  release_transition_authority=$false
}
$digest=Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:module-sdk-mep-functional-parity:1'
Assert-MIR4ModuleEcosystemV1 ([string]$digest-ceq'sha256:11b21f03ae7839e0b555dc0604b5d02413d7c11dc023be25cf975dff6c448050') 'mir4-module-ecosystem-functional-parity' ([string]$digest)
Assert-MIR4ModuleEcosystemV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-module-ecosystem-package-source-mutation'

[pscustomobject][ordered]@{status='accepted';functional_digest=[string]$digest;pre_cutover_capture='sha256:5f813a132879013c1d3682ed78ac34e454d2d9c88cab6ec866f3adb31307d284';generated_file_count=$files.Count;production_consumer_status=[string]$authority.independent_consumer.status;package_source_sha256=$packageBefore;release_transition_authority=$false}
