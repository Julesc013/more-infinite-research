param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/domain/safety/SafetyKernel.ps1')
. (Join-Path $repo 'tools/mir/application/processir/ProcessIR.ps1')
. (Join-Path $repo 'tools/mir/application/processir/ExactProcessIR.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

function Assert-MIR4ProcessIRExactV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){$suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"};throw "[$Code]$suffix"}
}

$packageBefore=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$authority=Get-MIR4ProcessIRSynthesisAuthority -RepoRoot $repo
foreach($flag in @('semantic_authority','player_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','planner_or_emitter_admission_authorized','safety_kernel_override_authorized','public_support_authorized','signing_or_sealing_authorized','publication_authorized')){Assert-MIR4ProcessIRExactV1 (-not[bool]$authority.$flag) 'mir4-processir-authority-firewall' $flag}
$records=New-MIR4W06Records -RepoRoot $repo -SourceIdentity $null
Assert-MIR4ProcessIRExactV1 ([bool]$records.parity.passed-and[bool]$records.parity.bilateral_gate.passed-and-not[bool]$records.parity.bilateral_gate.reject_everything) 'mir4-processir-bilateral-parity'
Assert-MIR4ProcessIRExactV1 (@($records.parity.fixture_results|Where-Object{-not$_.passed}).Count-eq0-and[bool]$records.parity.risk_parity.passed) 'mir4-processir-fixture-parity'
Assert-MIR4ProcessIRExactV1 ([string]$records.parity.exact_target_evidence.custody_blocker-ceq'BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO'-and[bool]$records.parity.exact_target_evidence.deterministic-and-not[bool]$records.parity.exact_target_evidence.authoritative) 'mir4-processir-exact-boundary'
Assert-MIR4ProcessIRExactV1 (@($records.effects.channels).Count-eq6-and[bool]$records.effects.opaque_preserved) 'mir4-processir-effects'
Assert-MIR4ProcessIRExactV1 (@($records.synthesis.candidates|Where-Object{$_.mutation_authorized-or$_.planner_admission-or$_.operation_object}).Count-eq0) 'mir4-processir-synthesis-firewall'
$t12=Get-MIR4T12Authority -RepoRoot $repo
Assert-MIR4ProcessIRExactV1 (@($t12.captures).Count-eq11-and-not[bool]$t12.release_admission_authorized-and-not[bool]$t12.publication_authorized) 'mir4-exact-processir-authority'
$exactOutput=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1') -RepoRoot $repo -ReferenceRoot 'sdk/preview/mir4/reference/t12' -Check 2>&1|Out-String).Trim()
Assert-MIR4ProcessIRExactV1 ($LASTEXITCODE-eq0-and$exactOutput-match'"status"\s*:\s*"passed"') 'mir4-exact-processir-check' $exactOutput
Assert-MIR4ProcessIRExactV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo)-ceq$packageBefore) 'mir4-processir-package-mutation'
[pscustomobject][ordered]@{status='accepted';processir_parity_digest=[string]$records.parity.digest;effect_channel_digest=[string]$records.effects.digest;synthesis_maturity_digest=[string]$records.synthesis.digest;exact_capture_count=@($t12.captures).Count;custody_blocker='BLOCKED-EXACT-ARCHIVE-CUSTODY-F200-K2SO';package_source_sha256=$packageBefore;package_visible=$false;release_transition_authority=$false}
