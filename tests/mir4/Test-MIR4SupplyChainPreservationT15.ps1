# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

$records=[ordered]@{
  '.mir/releases/waves/mir4-r0/MIR4-Supply-Chain-Preservation-T15V1.json'='spec/schemas/mir4-supply-chain-preservation-t15-v1.schema.json'
  '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json'='spec/schemas/mir4-t15-independent-machine-acceptance-v1.schema.json'
  '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json'='spec/schemas/mir4-t15-authority-evolution-receipt-v1.schema.json'
  '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json'='spec/schemas/mir4-pre-freeze-execution-programme-v1.schema.json'
}
$parsed=@{}
foreach($entry in $records.GetEnumerator()){
  $path=Join-Path $repo $entry.Key
  $schema=Join-Path $repo $entry.Value
  $json=Get-Content -Raw -LiteralPath $path
  if(-not($json|Test-Json -SchemaFile $schema)){throw "[mir4-t15-schema] $($entry.Key)"}
  $parsed[$entry.Key]=$json|ConvertFrom-Json -Depth 100
}

$machine=$parsed['.mir/releases/waves/mir4-r0/MIR4-Supply-Chain-Preservation-T15V1.json']
$acceptance=$parsed['.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json']
$evolution=$parsed['.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json']
$programme=$parsed['.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json']

if([string]$machine.source.commit-cne'c4a68809a54a81ae0a1959d257c2e4a97ef0e490'-or
   [string]$machine.source.tree-cne'c76a5fb46bc950264652b7033c6ce72b7f9b1991'-or
   [string]$machine.source.package_source_sha256-cne'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'-or
   -not[bool]$machine.source.working_tree_clean-or-not[bool]$machine.machine_conclusion.t15_prerequisites_satisfied-or
   [int]$machine.verification_plan.unknown_paths-ne0-or[int]$machine.verification_plan.invalid-ne2-or
   (@($machine.verification_plan.invalid_tests)-join'|')-cne'static.mir4-bootstrap-materialization|static.mir4-offline-custody'-or
   @($machine.workers).Count-ne5-or@($machine.preview_assets).Count-ne4-or
   [string]$machine.release_capsule.direct_verification-cne'passed'-or-not[bool]$machine.offline_restoration.receipts_byte_identical-or
   [int]$machine.offline_restoration.independent_restore_count-ne2-or[int]$machine.offline_restoration.network_calls-ne0-or
   -not[bool]$machine.runner_publisher_confinement.cross_worktree_bytes_identical-or
   [bool]$machine.signing_preparation.proof_private_key_retained-or[bool]$machine.signing_preparation.production_authority-or
   [bool]$machine.independent_machine_audit.human_acceptance_inferred-or
   @($machine.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-t15-machine-authority]'
}

$machinePath=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Supply-Chain-Preservation-T15V1.json'
$machineSha=(Get-FileHash -LiteralPath $machinePath -Algorithm SHA256).Hash.ToUpperInvariant()
if([string]$acceptance.review_input.machine_authority_sha256-cne$machineSha-or
   [string]$acceptance.review_input.audit_diagnostic_record_sha256-cne[string]$machine.independent_machine_audit.diagnostic_record_sha256-or
   [string]$acceptance.review_input.external_export_manifest_record_sha256-cne[string]$machine.external_custody.manifest_record_sha256-or
   [string]$acceptance.verdict-cne'ACCEPTED-T15-MACHINE-SCOPE'-or
   [bool]$acceptance.reviewer.human_reviewer_claimed-or[bool]$acceptance.reviewer.human_acceptance_inferred-or
   [bool]$acceptance.package_visible-or[bool]$acceptance.release_authority-or
   @($acceptance.explicit_non_acceptances.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-t15-independent-machine-acceptance]'
}

$t14Path=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json'
$acceptancePath=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json'
$t14Sha=(Get-FileHash -LiteralPath $t14Path -Algorithm SHA256).Hash.ToUpperInvariant()
$acceptanceSha=(Get-FileHash -LiteralPath $acceptancePath -Algorithm SHA256).Hash.ToUpperInvariant()
if([string]$evolution.predecessor_receipt.sha256-cne$t14Sha-or
   [string]$evolution.machine_receipt.sha256-cne$machineSha-or
   [string]$evolution.independent_machine_acceptance.sha256-cne$acceptanceSha-or
   [string]$evolution.player_package_source_sha256-cne(Get-MIRPackageSourceFingerprint -RepoRoot $repo)-or
   [string]$evolution.execution_transition.current_status-cne'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-RELEASE-BLOCKED'-or
   $null -ne $evolution.execution_transition.next_dependency_ready_turn-or
   (@($evolution.execution_transition.human_blocked_turns)-join'|')-cne'T16|T17'-or
   @($evolution.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-t15-authority-evolution]'
}

if([string]$programme.status-cne'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-RELEASE-BLOCKED'-or
   $null -ne $programme.next_dependency_ready_turn-or
   @($programme.turns|Where-Object{$_.id-eq'T15'-and$_.state-eq'completed'}).Count-ne1-or
   @($programme.turns|Where-Object{$_.id-in@('T16','T17')-and$_.state-eq'blocked-human'}).Count-ne2-or
   @($programme.turns|Where-Object{$_.id-eq'T18'-and$_.state-eq'blocked-dependency'}).Count-ne1-or
   @($programme.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
  throw '[mir4-t15-programme-state]'
}

$packageFiles=@(Get-MIRPackageSourceFiles -RepoRoot $repo)
foreach($path in @($records.Keys)+@(
  'spec/schemas/mir4-supply-chain-preservation-t15-v1.schema.json',
  'spec/schemas/mir4-t15-independent-machine-acceptance-v1.schema.json',
  'spec/schemas/mir4-t15-authority-evolution-receipt-v1.schema.json',
  'tests/mir4/Test-MIR4SupplyChainPreservationT15.ps1'
)){
  if($path-in$packageFiles){throw "[mir4-t15-package-visible] $path"}
}

Write-Host '[ok] MIR 4 T15 supply-chain and preservation is independently accepted within machine scope; T16/T17 human gates and every release transition remain closed.'
