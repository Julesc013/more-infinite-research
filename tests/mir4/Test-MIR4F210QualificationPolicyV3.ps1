# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot='')
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RepoRoot)){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')
$writer=Join-Path $repo 'tools/commands/mir4/Update-MIR4F210CurrentQualificationPolicyV3Authority.ps1'
$defaultCheck=& $writer -Check
if([string]$defaultCheck.status-cne'current'){throw '[mir4-f210-v3-default-reporoot]'}
& $writer -RepoRoot $repo -Check|Out-Null
$v2=Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $repo
$v3=Get-MIR4F210CurrentQualificationPolicyV3 -RepoRoot $repo
$receipt=Get-MIR4F210CurrentQualificationPolicySuccessionV2 -RepoRoot $repo
$channel=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/engines/mir4-factorio-2.1-experimental-channel-v2.json')|ConvertFrom-Json -Depth 100 -DateKind String
$observedAt=[string]$channel.current_review.observed_at
if([string]$v2.support_floor-cne'2.1.18' -or [string]$v3.support_floor-cne'2.1.18' -or [string]$receipt.current_policy.record_sha256-cne[string]$v3.record_sha256 -or [string]$v3.recorded_at-cne$observedAt -or [string]$receipt.recorded_at-cne$observedAt -or [string]$v3.observed_engine_channel_review.observed_at-cne$observedAt){throw '[mir4-f210-v3-policy-binding]'}
$info=Get-Content -Raw -LiteralPath (Join-Path $repo 'source/presentation/f210/info.json.template')|ConvertFrom-Json -Depth 20
$required=@('base >= 2.1.18','? recycler >= 2.1.18','? space-age >= 2.1.18')
if(@($required|Where-Object {$_ -notin @($info.dependencies)}).Count-ne0){throw '[mir4-f210-v3-metadata-floor]'}
$profile=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/profiles/factorio-2.1.json')|ConvertFrom-Json -Depth 20
if([string]$profile.minimum_factorio_version-cne'2.1.18' -or [string]$profile.qualification_factorio_channel_authority-cne'spec/engines/mir4-factorio-2.1-experimental-channel-v2.json'){throw '[mir4-f210-v3-profile-binding]'}
if([string]$channel.current_review.version-cne'2.1.22' -or [string]$channel.current_review.binary_sha256-cne'D8C745FD4E8C901BF0FC250C4D0FF75B454987857C1AEAADF8E775F0E65A9E4B' -or [string]$observedAt-cne'2026-10-19T12:39:29.3637648+00:00' -or @($channel.current_review.review_tasks|Where-Object status -ne 'complete').Count-ne0){throw '[mir4-f210-v3-channel-binding]'}
if(-not[bool]$v3.qualification.current_engine_intake_observed -or [bool]$v3.qualification.current_engine_api_prototype_data_mod_capsule_admitted -or [bool]$v3.qualification.current_engine_qualification_passed -or [bool]$receipt.exact_engine_qualification.admitted -or [bool]$receipt.exact_engine_qualification.qualified -or @($v3.boundaries.PSObject.Properties|Where-Object {[bool]$_.Value}).Count-ne0){throw '[mir4-f210-v3-native-boundary]'}
$policyPath=Join-Path $repo $script:MIR4F210CurrentPolicyV3RelativePath
$receiptPath=Join-Path $repo $script:MIR4F210CurrentPolicySuccessionV2RelativePath
$policyHash=(Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash
$receiptHash=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
$current=& $writer -RepoRoot $repo
if([string]$current.status-cne'current' -or [string]$current.recorded_at-cne$observedAt -or (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash-cne$policyHash -or (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash-cne$receiptHash){throw '[mir4-f210-v3-idempotent]'}
$timestampConflict=$false;try{& $writer -RepoRoot $repo -RecordedAt '2026-10-19T12:39:30.3637648+00:00'|Out-Null}catch{$timestampConflict=$_.Exception.Message-match'existing-timestamp-immutable'}
if(-not$timestampConflict){throw '[mir4-f210-v3-timestamp-immutable]'}
Write-Host '[ok] F210 2.1.22 observation successor is host-validated; package support floor and native boundaries remain unchanged.'

# Current cap execution is a separate successor, not a mutation of the
# observation or a claim that either of the native harnesses has passed.
$capWriter=Join-Path $repo 'tools/commands/mir4/Update-MIR4F210CurrentCapHarnessAdmissionAuthority.ps1'
$cap=Get-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $repo
$capPath=Join-Path $repo $script:MIR4F210CapHarnessV4Path
$capHash=(Get-FileHash -LiteralPath $capPath).Hash
$testInputs=(Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json -Depth 100).tests
foreach($id in @('static.mir4-f210-qualification-policy')+@($cap.admission.harnesses)){
  $rows=@($testInputs|Where-Object id -ceq $id)
  if($rows.Count-ne1){throw '[mir4-f210-cap-v4-test-input-row]'}
  foreach($inputPath in @($script:MIR4F210CapHarnessV4Path,$script:MIR4F210CapHarnessV4Schema,$script:MIR4F210CurrentPolicyV3RelativePath,$script:MIR4F210CurrentPolicySuccessionV2RelativePath,$script:MIR4F210CurrentEngineChannelReviewV2RelativePath)){
    if($inputPath-notin@($rows[0].inputs)){throw "[mir4-f210-cap-v4-test-input-missing] $id : $inputPath"}
  }
}
if((& $capWriter -RepoRoot $repo -Check).status-cne'current'){throw '[mir4-f210-cap-v4-writer-check]'}
$null=& $capWriter -RepoRoot $repo
if((Get-FileHash -LiteralPath $capPath).Hash-cne$capHash){throw '[mir4-f210-cap-v4-writer-rewrote-authority]'}
$conflict=$false
try{& $capWriter -RepoRoot $repo -RecordedAt ([DateTimeOffset]::Parse($cap.recorded_at).AddSeconds(1).ToString('o'))|Out-Null}catch{$conflict=$_.Exception.Message-match'existing-timestamp-immutable'}
if(-not$conflict){throw '[mir4-f210-cap-v4-timestamp-mutable]'}

$scratch=Join-Path $repo ('build/tmp/f210-cap-v4-controls-'+[guid]::NewGuid().ToString('N'))
$paths=@(Get-Variable -Scope Script -Name 'MIR4F210*'|Where-Object {$_.Value-is[string]-and$_.Value-match'^(?:[.]mir|spec)/'}|ForEach-Object {$_.Value})
$paths+=@('spec/schemas/mir4-f210-release-qualification-policy-v1.schema.json','spec/schemas/mir4-f210-qualification-policy-authority-evolution-receipt-v1.schema.json','spec/schemas/mir4-factorio-2.1-experimental-channel-v2.schema.json')
foreach($relative in @($paths|Sort-Object -Unique)){
  $target=Join-Path $scratch $relative
  [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null
  [IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes((Join-Path $repo $relative)))
}
$null=Get-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $scratch
$scratchCap=Join-Path $scratch $script:MIR4F210CapHarnessV4Path
$original=[IO.File]::ReadAllBytes($scratchCap)
$cases=@(
  @{id='claimed-native-pass';mutate={param($r)$r.qualification.current_engine_qualification_passed=$true};code='cap-v4-schema'},
  @{id='release-authority';mutate={param($r)$r.boundaries.publication_authorized=$true};code='cap-v4-schema'},
  @{id='extra-harness';mutate={param($r)$r.admission.harnesses+=,'unreviewed-harness'};code='cap-v4-schema'},
  @{id='different-engine';mutate={param($r)$r.engine_channel_review.version='2.1.23'};code='cap-v4-schema'},
  @{id='changed-review-binding';mutate={param($r)$r.engine_channel_review.sha256='0'*64};code='cap-v4-authority-binding'},
  @{id='changed-predecessor';mutate={param($r)$r.predecessor.admission_v3.record_sha256='0'*64};code='cap-v4-authority-binding'},
  @{id='unknown-field';mutate={param($r)$r|Add-Member -NotePropertyName bypass -NotePropertyValue $true};code='cap-v4-schema'}
)
foreach($case in $cases){
  $changed=[Text.Encoding]::UTF8.GetString($original)|ConvertFrom-Json -Depth 100 -DateKind String
  & $case.mutate $changed
  $changed.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $changed
  [IO.File]::WriteAllText($scratchCap,(ConvertTo-MIR4BootstrapCanonicalJson -Value $changed),[Text.UTF8Encoding]::new($false))
  $failure='';try{Get-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $scratch|Out-Null}catch{$failure=$_.Exception.Message}
  if($failure-notmatch$case.code){throw "[mir4-f210-cap-v4-opponent] $($case.id): $failure"}
}
[IO.File]::WriteAllBytes($scratchCap,$original)
$wrongScope=$false
try{Resolve-MIR4F210CurrentEngineCapHarnessAdmission -RepoRoot $scratch -HarnessId 'unreviewed-harness'|Out-Null}catch{$wrongScope=$_.Exception.Message-match'cap-harness-admission-scope'}
if(-not$wrongScope){throw '[mir4-f210-cap-v4-unreviewed-harness-admitted]'}
$wrongAuthority=$false
try{Resolve-MIR4F210AdmittedCapHarnessEngine -RepoRoot $scratch -HarnessId $cap.admission.harnesses[0] -AuthorityPath 'unreviewed.json'|Out-Null}catch{$wrongAuthority=$_.Exception.Message-match'cap-harness-admission-authority'}
if(-not$wrongAuthority){throw '[mir4-f210-cap-v4-unreviewed-authority-admitted]'}
$null=Get-MIR4F210CurrentEngineCapHarnessAdmissionV4 -RepoRoot $scratch
Write-Host '[ok] Exact 2.1.22 cap admission: current reader/writer, seven rehashed authority opponents and unknown-harness refusal passed without an engine process. Native qualification remains pending.'
